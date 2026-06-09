defmodule ProstaffEvents.InhouseQueue.ReconcilerTest do
  use ExUnit.Case, async: false

  import Mox

  alias ProstaffEvents.InhouseQueue.{Reconciler, Server}

  # set_mox_global makes the current test process the global owner so any
  # process (including the Reconciler GenServer) can use its expectations.
  setup :set_mox_global
  setup :verify_on_exit!

  defp future_deadline, do: DateTime.utc_now() |> DateTime.add(300) |> DateTime.to_iso8601()

  defp queue_fixture(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "q-#{System.unique_integer([:positive])}",
        "organization_id" => "org-#{System.unique_integer([:positive])}",
        "status" => "check_in",
        "check_in_deadline" => future_deadline(),
        "entries" => []
      },
      overrides
    )
  end

  describe "reconcile" do
    test "inicia GenServers para filas check_in retornadas pela API" do
      queue = queue_fixture(%{"status" => "check_in"})

      expect(ProstaffEvents.MockRailsClient, :get_active_queues, fn -> {:ok, [queue]} end)

      start_supervised!(Reconciler)
      Process.sleep(50)

      assert {:ok, _} = Server.get_state(queue["organization_id"])
    end

    test "inicia GenServers para filas open retornadas pela API" do
      queue = queue_fixture(%{"status" => "open", "check_in_deadline" => nil})

      expect(ProstaffEvents.MockRailsClient, :get_active_queues, fn -> {:ok, [queue]} end)

      start_supervised!(Reconciler)
      Process.sleep(50)

      assert {:ok, _} = Server.get_state(queue["organization_id"])
    end

    test "sobe sem estado se Rails retornar erro" do
      # stub (não expect) pois serão feitas 4 chamadas: 1 inicial + 3 retries
      stub(ProstaffEvents.MockRailsClient, :get_active_queues, fn ->
        {:error, "connection refused"}
      end)

      {:ok, reconciler_pid} = start_supervised(Reconciler)
      # aguarda todos os retries (3 × 10ms em test) + folga
      Process.sleep(200)

      assert Process.alive?(reconciler_pid)
    end

    test "inicia múltiplas filas" do
      queues = [queue_fixture(), queue_fixture()]
      org_ids = Enum.map(queues, & &1["organization_id"])

      expect(ProstaffEvents.MockRailsClient, :get_active_queues, fn -> {:ok, queues} end)

      start_supervised!(Reconciler)
      Process.sleep(50)

      for org_id <- org_ids do
        assert {:ok, _} = Server.get_state(org_id)
      end
    end
  end
end
