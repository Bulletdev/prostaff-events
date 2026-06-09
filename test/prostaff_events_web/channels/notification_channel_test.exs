defmodule ProstaffEventsWeb.NotificationChannelTest do
  use ProstaffEventsWeb.ChannelCase

  alias ProstaffEventsWeb.UserSocket

  defp connect_socket(user_id, org_id) do
    token = user_token(user_id: user_id, org_id: org_id)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  describe "join/3" do
    test "aceita usuário subscrevendo ao próprio canal" do
      socket = connect_socket("user-1", "org-1")
      assert {:ok, _, _} = subscribe_and_join(socket, "notifications:user-1")
    end

    test "rejeita usuário tentando subscribar canal de outro" do
      socket = connect_socket("user-1", "org-1")
      assert {:error, %{reason: "unauthorized"}} = subscribe_and_join(socket, "notifications:user-2")
    end
  end

  describe "handle_info/2" do
    test "encaminha evento ao cliente" do
      socket = connect_socket("user-fw", "org-1")
      {:ok, _, socket} = subscribe_and_join(socket, "notifications:user-fw")

      event = %{"type" => "notification.created", "org_id" => "org-1", "user_id" => "user-fw"}
      send(socket.channel_pid, {:event, event})

      assert_push "notification.created", ^event
    end
  end
end
