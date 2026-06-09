defmodule ProstaffEventsWeb.NotificationChannel do
  @moduledoc false
  use Phoenix.Channel

  # Frontend subscribes to: "notifications:{user_id}"
  # Receives domain events pushed by Rails via EventPublisher → Redis pub/sub.
  # Only the owning user can subscribe to their notification stream.
  def join("notifications:" <> user_id, _params, socket) do
    if user_id == socket.assigns.user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Rails publishes notification.created via Redis → RedisSubscriber → PubSub.
  # The RedisSubscriber broadcasts to this topic and the channel forwards to the client.
  def handle_info({:event, event}, socket) do
    push(socket, event["type"] || "event", event)
    {:noreply, socket}
  end
end
