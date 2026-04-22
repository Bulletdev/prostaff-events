defmodule ProstaffEventsWeb.TournamentChannel do
  use Phoenix.Channel

  # Frontend subscribes to: "tournament:{tournament_id}"
  # Open subscription — spectators and participants alike can follow live.
  # Auth is still required at the socket level (JWT in UserSocket.connect/2).
  def join("tournament:" <> _tournament_id, _params, socket) do
    {:ok, socket}
  end

  # Rails publishes tournament_match.confirmed / .walkover via Redis.
  # RedisSubscriber routes to the appropriate tournament topic.
  def handle_info({:event, event}, socket) do
    push(socket, event["type"] || "match_update", event)
    {:noreply, socket}
  end
end
