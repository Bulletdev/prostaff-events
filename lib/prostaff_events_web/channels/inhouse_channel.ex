defmodule ProstaffEventsWeb.InhouseChannel do
  @moduledoc false
  use Phoenix.Channel

  alias ProstaffEvents.{InhouseQueue, RateLimit}

  # Frontend subscribes to: "inhouse:{org_id}"
  # Only members of the organization can subscribe.
  def join("inhouse:" <> org_id, _params, socket) do
    if org_id == socket.assigns.org_id do
      # Subscribe to InhouseQueue GenServer broadcasts for this org
      Phoenix.PubSub.subscribe(ProstaffEvents.PubSub, "inhouse_queue:#{org_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Queue state change (join/leave/checkin/expired)
  def handle_info({:queue_update, payload}, socket) do
    push(socket, "queue_update", payload)
    {:noreply, socket}
  end

  # Domain event from Rails via Redis
  def handle_info({:event, event}, socket) do
    push(socket, event["type"] || "event", event)
    {:noreply, socket}
  end

  # Client actions - delegate to InhouseQueue.Server for serialized execution
  def handle_in("join_queue", %{"player_id" => player_id, "role" => role}, socket) do
    case RateLimit.check(socket.assigns.org_id) do
      :ok ->
        case InhouseQueue.Server.join(socket.assigns.org_id, player_id, role) do
          {:ok, state} -> {:reply, {:ok, state}, socket}
          {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
        end

      {:error, :rate_limited} ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}
    end
  end

  def handle_in("checkin", %{"player_id" => player_id}, socket) do
    case InhouseQueue.Server.checkin(socket.assigns.org_id, player_id) do
      {:ok, state} -> {:reply, {:ok, state}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end
end
