defmodule ProstaffEvents.InhouseQueue.Reconciler do
  @moduledoc """
  On startup, fetches all active InhouseQueues from the Rails API and starts a
  GenServer for each. Handles both "open" and "check_in" states.

  Ensures timers survive Phoenix restarts - if the check_in deadline already
  passed while Phoenix was down, the GenServer fires :check_in_expired immediately
  (ms = 0 via max/2 in Server.schedule_deadline_check).
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), {:reconcile, 0})
    {:ok, %{}}
  end

  @impl true
  def handle_info({:reconcile, attempt}, state) do
    case rails_client().get_active_queues() do
      {:ok, queues} ->
        open = Enum.count(queues, &(&1["status"] == "open"))
        check_in = Enum.count(queues, &(&1["status"] == "check_in"))
        Logger.info("[Reconciler] Reconciling queues", open: open, check_in: check_in)
        Enum.each(queues, &start_queue_server/1)

      {:error, reason} ->
        delays =
          Application.get_env(:prostaff_events, :reconciler_retry_delays, [1_000, 2_000, 4_000])

        if attempt < length(delays) do
          delay = Enum.at(delays, attempt)

          Logger.warning(
            "[Reconciler] Fetch failed (attempt #{attempt + 1}/#{length(delays) + 1}), retrying in #{delay}ms",
            reason: inspect(reason)
          )

          Process.send_after(self(), {:reconcile, attempt + 1}, delay)
        else
          Logger.warning(
            "[Reconciler] Failed to fetch active queues after #{attempt + 1} attempts - starting without state",
            reason: inspect(reason)
          )
        end
    end

    {:noreply, state}
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
        Logger.info("[Reconciler] Started queue",
          queue_id: args.queue_id,
          org_id: args.org_id,
          status: args.status
        )

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Reconciler] Failed to start queue",
          queue_id: args.queue_id,
          reason: inspect(reason)
        )
    end
  end

  defp parse_deadline(nil), do: nil

  defp parse_deadline(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _} ->
        dt

      _ ->
        Logger.warning("[Reconciler] Invalid check_in_deadline format",
          reason: inspect(iso8601)
        )

        nil
    end
  end

  defp build_entries(entries) do
    Map.new(entries, fn e ->
      {e["player_id"], %{role: e["role"], checked_in: e["checked_in"] || false}}
    end)
  end

  defp rails_client, do: ProstaffEvents.RailsClient.impl()
end
