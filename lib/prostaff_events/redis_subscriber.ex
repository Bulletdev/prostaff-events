defmodule ProstaffEvents.RedisSubscriber do
  @moduledoc """
  Subscribes to Redis pub/sub channel prostaff:events:* and re-broadcasts
  incoming events via Phoenix.PubSub to the appropriate channels.

  Rails publishes to Redis (via Events::EventPublishJob) and Phoenix picks up
  here — no HTTP between Rails and Phoenix.

  Channel routing:
    org_id present  → org-scoped PubSub topic  "org_events:{org_id}"
    tournament_*    → tournament topic          "tournament:{tournament_id}"
    notification.*  → user topic               "notifications:{user_id}"
    inhouse.*       → inhouse topic            "inhouse:{org_id}"
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
    {:ok, conn} = Redix.start_link(redis_url, name: :redis_pubsub)
    Redix.command(:redis_pubsub, ["PSUBSCRIBE", @redis_pattern])
    Logger.info("[RedisSubscriber] Subscribed to #{@redis_pattern}")
    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_info({:redix_pubsub, _conn, _ref, :pmessage, %{payload: payload}}, state) do
    case Jason.decode(payload) do
      {:ok, event} -> route_event(event)
      {:error, _} -> Logger.warn("[RedisSubscriber] Failed to decode event: #{payload}")
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp route_event(%{"type" => type, "org_id" => org_id, "user_id" => user_id} = event) do
    # Always broadcast to org-scoped topic
    Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "org_events:#{org_id}", {:event, event})

    # Route to type-specific topics
    cond do
      String.starts_with?(type, "notification.") ->
        Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "notifications:#{user_id}", {:event, event})

      String.starts_with?(type, "tournament_match.") ->
        tournament_id = event["payload"]["tournament_id"]
        if tournament_id do
          Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "tournament:#{tournament_id}", {:event, event})
        end

      String.starts_with?(type, "inhouse.") ->
        Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "inhouse:#{org_id}", {:event, event})

      true ->
        Logger.debug("[RedisSubscriber] Unrouted event type=#{type} org=#{org_id}")
    end
  end

  defp route_event(event) do
    Logger.warn("[RedisSubscriber] Event missing required fields: #{inspect(event)}")
  end
end
