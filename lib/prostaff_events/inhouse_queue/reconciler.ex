defmodule ProstaffEvents.InhouseQueue.Reconciler do
  @moduledoc """
  On startup, fetches all InhouseQueues in check_in state with a future deadline
  from the Rails API and starts a GenServer for each.

  This ensures timers survive Phoenix restarts — if Phoenix was down for 1 hour
  and the deadline already passed, the GenServer fires :check_in_expired immediately
  (ms = 0 via max/2 in Server.schedule_deadline_check).
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Run reconciliation after the supervision tree is fully started
    send(self(), :reconcile)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:reconcile, state) do
    case fetch_active_queues() do
      {:ok, queues} ->
        Logger.info("[Reconciler] Starting #{length(queues)} InhouseQueue GenServers from Rails")
        Enum.each(queues, &start_queue_server/1)

      {:error, reason} ->
        Logger.warn("[Reconciler] Failed to fetch active queues: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp fetch_active_queues do
    rails_url = Application.get_env(:prostaff_events, :rails_api_url)
    token = generate_internal_token()

    case Req.get("#{rails_url}/internal/api/inhouse_queues/active",
           headers: [{"authorization", "Bearer #{token}"}],
           receive_timeout: 5_000
         ) do
      {:ok, %{status: 200, body: %{"queues" => queues}}} -> {:ok, queues}
      {:ok, resp} -> {:error, "unexpected status #{resp.status}"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp start_queue_server(queue_data) do
    deadline = parse_deadline(queue_data["check_in_deadline"])

    args = %{
      queue_id: queue_data["id"],
      org_id: queue_data["organization_id"],
      status: queue_data["status"],
      check_in_deadline: deadline,
      entries: build_entries(queue_data["entries"] || [])
    }

    case DynamicSupervisor.start_child(
           ProstaffEvents.InhouseQueue.Supervisor,
           {ProstaffEvents.InhouseQueue.Server, args}
         ) do
      {:ok, _pid} ->
        Logger.info("[Reconciler] Started queue=#{args.queue_id} org=#{args.org_id}")

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.warn("[Reconciler] Failed to start queue=#{args.queue_id}: #{inspect(reason)}")
    end
  end

  defp parse_deadline(nil), do: DateTime.utc_now()
  defp parse_deadline(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp build_entries(entries) do
    Map.new(entries, fn e ->
      {e["player_id"], %{role: e["role"], checked_in: e["checked_in"] || false}}
    end)
  end

  defp generate_internal_token do
    secret = Application.get_env(:prostaff_events, :internal_jwt_secret, "")
    signer = Joken.Signer.create("HS256", secret)
    claims = %{"type" => "internal", "iss" => "prostaff-events", "iat" => DateTime.to_unix(DateTime.utc_now())}
    {:ok, token, _} = Joken.encode_and_sign(claims, signer)
    token
  end
end
