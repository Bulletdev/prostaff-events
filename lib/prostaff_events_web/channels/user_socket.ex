defmodule ProstaffEventsWeb.UserSocket do
  use Phoenix.Socket

  channel "notifications:*", ProstaffEventsWeb.NotificationChannel
  channel "tournament:*", ProstaffEventsWeb.TournamentChannel
  channel "inhouse:*", ProstaffEventsWeb.InhouseChannel

  # JWT authentication on WebSocket connect.
  # Accepts both user JWTs (from frontend) and internal JWTs (from Rails/services).
  # Token passed as ?token= query param or Authorization header.
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case ProstaffEvents.Auth.verify_token(token) do
      {:ok, %{user_id: user_id, org_id: org_id}} ->
        {:ok, assign(socket, user_id: user_id, org_id: org_id)}

      {:error, reason} ->
        require Logger
        Logger.warn("[UserSocket] Auth rejected: #{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
