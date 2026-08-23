defmodule ProstaffEventsWeb.EventsController do
  use Phoenix.Controller, formats: [:json]

  alias ProstaffEvents.{Auth, Health}

  # POST /events/notify
  # Called by Scraper (external HTTP) with X-API-Key auth.
  # Rails publishes via Redis pub/sub directly - this endpoint is only for the Scraper.
  def notify(conn, params) do
    with :ok <- verify_api_key(conn),
         {:ok, event} <- validate_event(params) do
      route_event(event)
      json(conn, %{ok: true})
    else
      {:error, :invalid_api_key} ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  # GET /health - liveness (no I/O, always fast)
  def health(conn, _params) do
    json(conn, %{status: "ok", service: "prostaff-events", vsn: "0.1.0"})
  end

  # GET /health/ready - readiness (checks Redis + Rails)
  def ready(conn, _params) do
    case Health.ready() do
      {:ok, checks} ->
        json(conn, %{status: "ok", checks: checks})

      {:error, checks} ->
        conn |> put_status(503) |> json(%{status: "unavailable", checks: checks})
    end
  end

  defp verify_api_key(conn) do
    key = get_req_header(conn, "x-api-key") |> List.first()
    Auth.verify_api_key(key)
  end

  # Both the integer and the string form are accepted on purpose.
  # Rails serializes `version` as a JSON number, so Jason.decode/1 hands us the
  # integer 1. Comparing that against ["1"] never matches, and then
  # the request is rejected as an unsupported version -
  # a silent drop with no error on either side. Do not narrow this list.
  @supported_versions [1, "1"]

  defp validate_event(%{"type" => type, "org_id" => org_id} = params)
       when is_binary(type) and is_binary(org_id) do
    case Map.get(params, "version") do
      nil -> {:ok, params}
      v when v in @supported_versions -> {:ok, params}
      v -> {:error, "unsupported schema version: #{v}"}
    end
  end

  defp validate_event(_), do: {:error, "missing required fields: type, org_id"}

  defp route_event(%{"type" => type, "org_id" => org_id} = event) do
    require Logger

    # Broadcast to org-scoped topic
    Phoenix.PubSub.broadcast(ProstaffEvents.PubSub, "org_events:#{org_id}", {:event, event})

    # Additional routing for specific event types
    if String.starts_with?(type, "match.") do
      Logger.info("[EventsController] Routed #{type} for org=#{org_id}")
    else
      Logger.debug("[EventsController] Forwarded #{type} to org=#{org_id}")
    end
  end
end
