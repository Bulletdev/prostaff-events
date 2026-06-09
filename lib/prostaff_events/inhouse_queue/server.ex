defmodule ProstaffEvents.InhouseQueue.Server do
  @moduledoc """
  GenServer per active InhouseQueue. Serializes all mutations (join/leave/checkin)
  so no race conditions are possible at the application level.

  State is ephemeral - PostgreSQL (via Rails) is the source of truth.
  On startup, Reconciler rebuilds GenServers for queues in check_in state
  with deadlines still in the future.

  Timer enforcement: Process.send_after(:check_in_expired, ms) fires once at
  check_in_deadline. If the process crashes and restarts, the timer is
  recalculated from the DB deadline stored in state.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @telemetry_prefix [:prostaff, :inhouse_queue]

  defstruct [:queue_id, :org_id, :status, :check_in_deadline, :entries, :timer_ref]

  # --- Client API ---

  def start_link(%{queue_id: queue_id, org_id: org_id} = args) do
    GenServer.start_link(__MODULE__, args, name: via(queue_id, org_id))
  end

  def join(org_id, player_id, role) do
    case lookup(org_id) do
      nil -> {:error, "no_active_queue"}
      pid -> GenServer.call(pid, {:join, player_id, role})
    end
  end

  def leave(org_id, player_id) do
    case lookup(org_id) do
      nil -> {:error, "no_active_queue"}
      pid -> GenServer.call(pid, {:leave, player_id})
    end
  end

  def checkin(org_id, player_id) do
    case lookup(org_id) do
      nil -> {:error, "no_active_queue"}
      pid -> GenServer.call(pid, {:checkin, player_id})
    end
  end

  def get_state(org_id) do
    case lookup(org_id) do
      nil -> {:error, "no_active_queue"}
      pid -> {:ok, GenServer.call(pid, :get_state)}
    end
  end

  def stop(org_id) do
    case lookup(org_id) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  # --- Server callbacks ---

  @impl true
  def init(%{
        queue_id: queue_id,
        org_id: org_id,
        status: status,
        check_in_deadline: deadline,
        entries: entries
      }) do
    timer_ref = schedule_deadline_check(status, deadline)

    state = %__MODULE__{
      queue_id: queue_id,
      org_id: org_id,
      status: status,
      check_in_deadline: deadline,
      entries: entries || %{},
      timer_ref: timer_ref
    }

    Logger.info(
      "[InhouseQueue] Started GenServer queue=#{queue_id} org=#{org_id} status=#{status}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id, role}, _from, state) do
    if state.status != "open" do
      {:reply, {:error, "queue_not_open"}, state}
    else
      new_entries = Map.put(state.entries, player_id, %{role: role, checked_in: false})
      new_state = %{state | entries: new_entries}
      broadcast_queue_update(new_state, "player_joined", %{player_id: player_id, role: role})

      :telemetry.execute(@telemetry_prefix ++ [:join], %{count: 1}, %{
        org_id: state.org_id,
        queue_id: state.queue_id,
        player_id: player_id
      })

      {:reply, {:ok, queue_summary(new_state)}, new_state}
    end
  end

  @impl true
  def handle_call({:leave, player_id}, _from, state) do
    new_entries = Map.delete(state.entries, player_id)
    new_state = %{state | entries: new_entries}
    broadcast_queue_update(new_state, "player_left", %{player_id: player_id})

    :telemetry.execute(@telemetry_prefix ++ [:leave], %{count: 1}, %{
      org_id: state.org_id,
      queue_id: state.queue_id,
      player_id: player_id
    })

    {:reply, {:ok, queue_summary(new_state)}, new_state}
  end

  @impl true
  def handle_call({:checkin, player_id}, _from, state) do
    if state.status != "check_in" do
      {:reply, {:error, "not_in_check_in_phase"}, state}
    else
      case Map.get(state.entries, player_id) do
        nil ->
          {:reply, {:error, "player_not_in_queue"}, state}

        entry ->
          new_entries = Map.put(state.entries, player_id, %{entry | checked_in: true})
          new_state = %{state | entries: new_entries}
          broadcast_queue_update(new_state, "player_checked_in", %{player_id: player_id})

          :telemetry.execute(@telemetry_prefix ++ [:checkin], %{count: 1}, %{
            org_id: state.org_id,
            queue_id: state.queue_id,
            player_id: player_id
          })

          {:reply, {:ok, queue_summary(new_state)}, new_state}
      end
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, queue_summary(state), state}
  end

  @impl true
  def handle_info(:check_in_expired, state) do
    Logger.info("[InhouseQueue] Check-in deadline expired queue=#{state.queue_id}")

    unchecked = Enum.filter(state.entries, fn {_id, e} -> not e.checked_in end)
    new_entries = Map.drop(state.entries, Enum.map(unchecked, &elem(&1, 0)))

    checked_in_count = Enum.count(new_entries, fn {_id, e} -> e.checked_in end)

    new_status = if checked_in_count < 2, do: "closed", else: state.status

    new_state = %{state | entries: new_entries, status: new_status}

    broadcast_queue_update(new_state, "check_in_expired", %{
      removed_count: length(unchecked),
      checked_in_count: checked_in_count,
      queue_closed: new_status == "closed"
    })

    if new_status == "closed" do
      {:stop, :normal, new_state}
    else
      {:noreply, new_state}
    end
  end

  # --- Private ---

  # Key is org_id only - one active queue per org at a time.
  defp via(_queue_id, org_id) do
    {:via, Registry, {ProstaffEvents.InhouseQueue.Registry, org_id}}
  end

  defp lookup(org_id) do
    case Registry.lookup(ProstaffEvents.InhouseQueue.Registry, org_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp schedule_deadline_check("check_in", nil) do
    Logger.warning("[InhouseQueue] check_in queue has no deadline - expiry will not be enforced")
    nil
  end

  defp schedule_deadline_check("check_in", %DateTime{} = deadline) do
    ms = max(DateTime.diff(deadline, DateTime.utc_now(), :millisecond), 0)
    Process.send_after(self(), :check_in_expired, ms)
  end

  defp schedule_deadline_check(_status, _deadline), do: nil

  defp broadcast_queue_update(state, event_type, extra) do
    PubSub.broadcast(
      ProstaffEvents.PubSub,
      "inhouse:#{state.org_id}",
      {:queue_update,
       Map.merge(extra, %{
         event: event_type,
         queue_id: state.queue_id,
         org_id: state.org_id,
         status: state.status,
         player_count: map_size(state.entries)
       })}
    )
  end

  defp queue_summary(state) do
    %{
      queue_id: state.queue_id,
      org_id: state.org_id,
      status: state.status,
      check_in_deadline: state.check_in_deadline,
      player_count: map_size(state.entries),
      entries: state.entries
    }
  end
end
