defmodule ProstaffEvents.InhouseQueue.ServerTest do
  use ExUnit.Case, async: true

  alias ProstaffEvents.InhouseQueue.Server

  @registry ProstaffEvents.InhouseQueue.Registry

  # Registry, PubSub and DynamicSupervisor are started by the Application.
  # Tests use unique org_ids via System.unique_integer to avoid cross-test conflicts.
  setup do
    :ok
  end

  defp start_server(overrides \\ %{}) do
    args =
      Map.merge(
        %{
          queue_id: "q-1",
          org_id: "org-test-#{System.unique_integer([:positive])}",
          status: "open",
          check_in_deadline: nil,
          entries: %{}
        },
        overrides
      )

    start_supervised!({Server, args})
    args.org_id
  end

  describe "join/3" do
    test "adiciona jogador ao estado" do
      org_id = start_server()
      assert {:ok, state} = Server.join(org_id, "player-1", "top")
      assert state.player_count == 1
      assert state.entries["player-1"].role == "top"
    end

    test "rejeita quando queue não está open" do
      org_id = start_server(%{status: "check_in"})
      assert {:error, "queue_not_open"} = Server.join(org_id, "player-1", "top")
    end

    test "retorna erro se não existe queue para o org" do
      assert {:error, "no_active_queue"} = Server.join("org-inexistente", "p1", "top")
    end
  end

  describe "leave/2" do
    test "remove jogador do estado" do
      org_id = start_server(%{entries: %{"player-1" => %{role: "top", checked_in: false}}})
      assert {:ok, state} = Server.leave(org_id, "player-1")
      assert state.player_count == 0
    end

    test "não falha se jogador não estava na queue" do
      org_id = start_server()
      assert {:ok, state} = Server.leave(org_id, "player-inexistente")
      assert state.player_count == 0
    end
  end

  describe "checkin/2" do
    test "marca jogador como confirmado" do
      org_id =
        start_server(%{
          status: "check_in",
          check_in_deadline: DateTime.utc_now() |> DateTime.add(60),
          entries: %{"player-1" => %{role: "top", checked_in: false}}
        })

      assert {:ok, state} = Server.checkin(org_id, "player-1")
      assert state.entries["player-1"].checked_in == true
    end

    test "rejeita se status não é check_in" do
      org_id = start_server(%{entries: %{"player-1" => %{role: "top", checked_in: false}}})
      assert {:error, "not_in_check_in_phase"} = Server.checkin(org_id, "player-1")
    end

    test "rejeita se jogador não está na queue" do
      org_id = start_server(%{status: "check_in", check_in_deadline: DateTime.utc_now() |> DateTime.add(60)})
      assert {:error, "player_not_in_queue"} = Server.checkin(org_id, "player-ausente")
    end
  end

  describe ":check_in_expired" do
    test "remove jogadores não confirmados e fecha se restam < 2" do
      org_id =
        start_server(%{
          status: "check_in",
          check_in_deadline: DateTime.utc_now() |> DateTime.add(-1),
          entries: %{
            "p1" => %{role: "top", checked_in: true},
            "p2" => %{role: "jg", checked_in: false}
          }
        })

      # Com 1 confirmado (< 2), o servidor deve parar (status closed)
      # Aguarda o processo encerrar
      ref = Process.monitor(GenServer.whereis({:via, Registry, {@registry, org_id}}))
      assert_receive {:DOWN, ^ref, :process, _, :normal}, 1_000
    end

    test "mantém a queue aberta se restam >= 2 confirmados" do
      deadline = DateTime.utc_now() |> DateTime.add(50, :millisecond)

      org_id =
        start_server(%{
          status: "check_in",
          check_in_deadline: deadline,
          entries: %{
            "p1" => %{role: "top", checked_in: true},
            "p2" => %{role: "jg", checked_in: true},
            "p3" => %{role: "mid", checked_in: false}
          }
        })

      Process.sleep(200)
      # Com 2 confirmados (>= 2), o GenServer permanece vivo
      assert {:ok, state} = Server.get_state(org_id)
      assert state.player_count == 2
    end
  end
end
