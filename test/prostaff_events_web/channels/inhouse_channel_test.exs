defmodule ProstaffEventsWeb.InhouseChannelTest do
  use ProstaffEventsWeb.ChannelCase

  alias ProstaffEvents.InhouseQueue.Server
  alias ProstaffEventsWeb.UserSocket

  defp connect_socket(org_id) do
    token = user_token(org_id: org_id, user_id: "user-123")
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  describe "join/3" do
    test "aceita usuário da org correta" do
      socket = connect_socket("org-abc")
      assert {:ok, _, _socket} = subscribe_and_join(socket, "inhouse:org-abc")
    end

    test "rejeita usuário de org diferente" do
      socket = connect_socket("org-abc")
      assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(socket, "inhouse:org-xyz")
    end
  end

  describe "join_queue" do
    setup do
      org_id = "org-channel-#{System.unique_integer([:positive])}"

      start_supervised!(
        {Server,
         %{
           queue_id: "q-1",
           org_id: org_id,
           status: "open",
           check_in_deadline: nil,
           entries: %{}
         }}
      )

      socket = connect_socket(org_id)
      {:ok, _, socket} = subscribe_and_join(socket, "inhouse:#{org_id}")

      {:ok, socket: socket, org_id: org_id}
    end

    test "entra na queue com sucesso", %{socket: socket} do
      ref = push(socket, "join_queue", %{"player_id" => "player-1", "role" => "top"})
      assert_reply ref, :ok, state
      assert state.player_count == 1
    end

    test "bloqueia após exceder rate limit (max=3 no test)", %{socket: socket} do
      # Envia 3 joins (dentro do limite) - todos devem ser aceitos
      for i <- 1..3 do
        ref = push(socket, "join_queue", %{"player_id" => "rl-player-#{i}", "role" => "top"})
        assert_reply ref, :ok, _
      end

      # 4º join excede o limite
      ref = push(socket, "join_queue", %{"player_id" => "rl-player-4", "role" => "top"})
      assert_reply ref, :error, %{reason: "rate_limited"}
    end

    test "retorna erro quando queue está em check_in (não open)" do
      org_id = "org-check-in-#{System.unique_integer([:positive])}"

      start_supervised!(
        {Server,
         %{
           queue_id: "q-ci",
           org_id: org_id,
           status: "check_in",
           check_in_deadline: DateTime.utc_now() |> DateTime.add(60),
           entries: %{}
         }},
        id: :check_in_server,
        restart: :temporary
      )

      socket = connect_socket(org_id)
      {:ok, _, socket} = subscribe_and_join(socket, "inhouse:#{org_id}")

      ref = push(socket, "join_queue", %{"player_id" => "player-1", "role" => "top"})
      assert_reply ref, :error, %{reason: "queue_not_open"}
    end
  end
end
