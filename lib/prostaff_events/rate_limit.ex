defmodule ProstaffEvents.RateLimit do
  @moduledoc false
  # Sliding window counter per org_id backed by an ETS table.
  # Unit: org_id (not per socket/player) - one org cannot flood the queue server.
  # Config keys (readable at runtime):
  #   :rate_limit_window_ms  - window size in ms (default: 60_000)
  #   :rate_limit_max        - max events per window per org (default: 10)

  use GenServer

  @table :inhouse_rate_limit
  # Cleanup runs every N windows to drop stale entries.
  @cleanup_interval_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns :ok or {:error, :rate_limited}."
  def check(org_id) do
    window_ms = Application.get_env(:prostaff_events, :rate_limit_window_ms, 60_000)
    max = Application.get_env(:prostaff_events, :rate_limit_max, 10)
    window = div(System.system_time(:millisecond), window_ms)
    count = :ets.update_counter(@table, {org_id, window}, {2, 1}, {{org_id, window}, 0})
    if count > max, do: {:error, :rate_limited}, else: :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    window_ms = Application.get_env(:prostaff_events, :rate_limit_window_ms, 60_000)
    current_window = div(System.system_time(:millisecond), window_ms)
    # Drop all entries from previous windows - record format: {{org_id, window}, count}
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current_window}], [true]}])
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
    {:noreply, state}
  end
end
