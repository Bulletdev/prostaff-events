defmodule ProstaffEvents.RedisSubscriber do
  @moduledoc """
  Subscribes to Redis pub/sub channel prostaff:events:* and re-broadcasts
  incoming events via Phoenix.PubSub to the appropriate channels.

  Rails publishes to Redis (via Events::EventPublishJob) and Phoenix picks up
  here - no HTTP between Rails and Phoenix.

  Uses Redix.PubSub for pattern subscription (PSUBSCRIBE).

  Channel routing:
    notification.*     → "notifications:{user_id}"
    tournament_match.* → "tournament:{tournament_id}"
    inhouse.*          → "inhouse:{org_id}"
    (all events)       → "org_events:{org_id}"
  """

  use GenServer
  require Logger

  @redis_pattern "prostaff:events:*"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    redis_url = Application.get_env(:prostaff_events, :redis_url, "redis://localhost:6379/0")
    {:ok, pubsub} = Redix.PubSub.start_link(redis_url, name: :redis_pubsub)
    {:ok, _ref} = Redix.PubSub.psubscribe(pubsub, @redis_pattern, self())
    Logger.info("[RedisSubscriber] Subscribed to #{@redis_pattern}")
    {:ok, %{pubsub: pubsub}}
  end

  # Subscription confirmation - ignore
  @impl true
  def handle_info({:redix_pubsub, _pubsub, _ref, :psubscribe, _details}, state) do
    {:noreply, state}
  end

  # Pattern subscription confirmation - ignore
  def handle_info({:redix_pubsub, _pubsub, _ref, :pmessage, %{payload: payload}}, state) do
    case Jason.decode(payload) do
      {:ok, event} -> route_event(event)
      {:error, _} -> Logger.warning("[RedisSubscriber] Failed to decode event payload")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp route_event(event) do
    case resolve_topics(event) do
      [] ->
        Logger.warning("[RedisSubscriber] Event missing required fields: #{inspect(event)}")

      topics ->
        Enum.each(topics, fn {topic, message} ->
          Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, topic, message)
        end)
    end
  end

  @supported_versions ["1"]

  @doc """
  Pure function: maps an event envelope to a list of {topic, message} pairs.
  All broadcasting side effects happen outside this function, making it testable
  without PubSub infrastructure.

  Rejects events with unknown versions. Accepts missing version for backward
  compatibility with events published before versioning was introduced.
  """
  def resolve_topics(%{"type" => type, "org_id" => org_id, "user_id" => user_id} = event) do
    version = Map.get(event, "version")

    if version != nil and version not in @supported_versions do
      Logger.warning("[RedisSubscriber] Rejected event with unknown version=#{version} type=#{type}")
      []
    else
      [{"org_events:#{org_id}", {:event, event}}] ++ specific_topics(type, org_id, user_id, event)
    end
  end

  def resolve_topics(_event), do: []

  defp specific_topics(type, org_id, user_id, event) do
    cond do
      String.starts_with?(type, "notification.") -> [{"notifications:#{user_id}", {:event, event}}]
      String.starts_with?(type, "tournament_match.") -> tournament_topics(event)
      String.starts_with?(type, "inhouse.") -> [{"inhouse:#{org_id}", {:event, event}}]
      true ->
        Logger.debug("[RedisSubscriber] Unrouted event type=#{type} org=#{org_id}")
        []
    end
  end

  defp tournament_topics(event) do
    case get_in(event, ["payload", "tournament_id"]) do
      nil -> []
      t_id -> [{"tournament:#{t_id}", {:event, event}}]
    end
  end
end
