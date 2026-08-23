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

  # Both the integer and the string form are accepted on purpose.
  # Rails serializes `version` as a JSON number, so Jason.decode/1 hands us the
  # integer 1. Comparing that against ["1"] never matches, and then
  # resolve_topics/1 returns [] and the event reaches no topic at all -
  # a silent drop with no error on either side. Do not narrow this list.
  @supported_versions [1, "1"]

  @required_fields ["type", "org_id", "user_id"]

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

  # Incoming pattern message - decode and route
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
      [] -> log_drop(event)
      topics -> Enum.each(topics, &broadcast/1)
    end
  end

  defp broadcast({topic, message}) do
    Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, topic, message)
  end

  # resolve_topics/1 returns [] for two unrelated reasons, and calling both
  # "missing required fields" points whoever is debugging at the wrong cause -
  # the old message printed an event that had every required field in it.
  #
  # The payload is never logged. It can carry user data, and logs are retained
  # and aggregated far more widely than the Redis channel they came from.
  defp log_drop(event) do
    case missing_fields(event) do
      [] ->
        Logger.warning(
          "[RedisSubscriber] Rejected event: unsupported version=" <>
            "#{inspect(field(event, "version"))} type=#{inspect(field(event, "type"))}"
        )

      missing ->
        Logger.warning(
          "[RedisSubscriber] Dropped event: missing or invalid field(s): " <>
            Enum.join(missing, ", ")
        )
    end
  end

  # A field only counts as present when it is a non-empty binary. A `type` that
  # decodes as a number used to reach String.starts_with?/2 and raise inside
  # handle_info, taking the subscriber down with it.
  defp missing_fields(event) when is_map(event) do
    Enum.reject(@required_fields, fn key ->
      case Map.get(event, key) do
        value when is_binary(value) -> value != ""
        _ -> false
      end
    end)
  end

  defp missing_fields(_event), do: @required_fields

  defp field(event, key) when is_map(event), do: Map.get(event, key)
  defp field(_event, _key), do: nil

  @doc """
  Maps an event envelope to a list of {topic, message} pairs.

  No broadcasting happens here, which is what makes the whole routing matrix
  testable without Redis or PubSub. It does emit a warning for an event type
  nothing routes - the type and org are only in scope here, and a silent drop
  is how nine event types went unnoticed. Keep it that way.

  Returns [] for exactly two reasons: an unsupported version, or a required
  field that is missing or not a binary. The caller tells them apart, so the
  log names the right cause.

  A missing version is accepted, for compatibility with events published before
  versioning existed.
  """
  def resolve_topics(%{"type" => type, "org_id" => org_id, "user_id" => user_id} = event)
      when is_binary(type) and is_binary(org_id) and is_binary(user_id) do
    version = Map.get(event, "version")

    if version != nil and version not in @supported_versions do
      []
    else
      [{"org_events:#{org_id}", {:event, event}}] ++ specific_topics(type, org_id, user_id, event)
    end
  end

  def resolve_topics(_event), do: []

  defp specific_topics(type, org_id, user_id, event) do
    cond do
      String.starts_with?(type, "notification.") ->
        [{"notifications:#{user_id}", {:event, event}}]

      String.starts_with?(type, "tournament_match.") ->
        tournament_topics(event)

      String.starts_with?(type, "inhouse.") ->
        [{"inhouse:#{org_id}", {:event, event}}]

      true ->
        # warning, not debug: production runs at :info and up, so an event type
        # nobody routes was invisible. It means either a new type the publisher
        # started sending or a typo - both need a human, and neither is normal.
        Logger.warning("[RedisSubscriber] Unrouted event type=#{type} org=#{org_id}")
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
