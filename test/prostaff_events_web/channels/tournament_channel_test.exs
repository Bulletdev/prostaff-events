defmodule ProstaffEventsWeb.TournamentChannelTest do
  use ProstaffEventsWeb.ChannelCase

  alias ProstaffEventsWeb.UserSocket

  defp connect_socket do
    token = user_token()
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  describe "join/3" do
    test "aceita qualquer usuário autenticado" do
      socket = connect_socket()
      assert {:ok, _, _} = subscribe_and_join(socket, "tournament:t-123")
    end
  end

  describe "handle_info/2" do
    test "encaminha evento de partida ao cliente" do
      socket = connect_socket()
      {:ok, _, socket} = subscribe_and_join(socket, "tournament:t-fw")

      event = %{"type" => "tournament_match.confirmed", "org_id" => "org-1", "user_id" => "sys"}
      send(socket.channel_pid, {:event, event})

      assert_push "tournament_match.confirmed", ^event
    end

    test "usa fallback match_update quando type ausente" do
      socket = connect_socket()
      {:ok, _, socket} = subscribe_and_join(socket, "tournament:t-fb")

      event = %{"org_id" => "org-1", "user_id" => "sys"}
      send(socket.channel_pid, {:event, event})

      assert_push "match_update", ^event
    end
  end
end
