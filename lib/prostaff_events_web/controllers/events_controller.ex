defmodule ProstaffEventsWeb.EventsController do
  use Phoenix.Controller, formats: [:json]

  alias ProstaffEvents.Auth

  # POST /events/notify
  # Called by Scraper (external HTTP) with X-API-Key auth.
  # Rails publishes via Redis pub/sub directly — this endpoint is only for the Scraper.
  def notify(conn, params) do
    with :ok <- verify_api_key(conn),
         {:ok, event} <- validate_event(params) do
      route_event(event)
      send_resp(conn, 200, Jason.encode!(%{ok: true}))
    else
      {:error, :invalid_api_key} ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  # GET /health
  def health(conn, _params) do
    json(conn, %{status: "ok", service: "prostaff-events", vsn: "0.1.0"})
  end

  defp verify_api_key(conn) do
    key = get_req_header(conn, "x-api-key") |> List.first()
    Auth.verify_api_key(key)
  end

  defp validate_event(%{"type" => type, "org_id" => org_id} = params) when is_binary(type) and is_binary(org_id) do
    {:ok, params}
  end

  defp validate_event(_), do: {:error, "missing required fields: type, org_id"}

  defp route_event(%{"type" => type, "org_id" => org_id} = event) do
    require Logger

    # Broadcast to org-scoped topic
    Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "org_events:#{org_id}", {:event, event})

    # Additional routing for specific event types
    cond do
      String.starts_with?(type, "match.") ->
        # Broadcast to all connected clients subscribed to this org
        Logger.info("[EventsController] Routed #{type} for org=#{org_id}")

      true ->
        Logger.debug("[EventsController] Forwarded #{type} to org=#{org_id}")
    end
  end
end
