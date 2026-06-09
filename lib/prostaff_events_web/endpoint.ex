defmodule ProstaffEventsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :prostaff_events

  socket "/socket", ProstaffEventsWeb.UserSocket,
    websocket: [connect_info: [params: [:token]]],
    longpoll: false

  plug Corsica,
    origins: "*",
    allow_headers: ["content-type", "authorization", "x-api-key"],
    allow_methods: ["GET", "POST", "OPTIONS"]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug ProstaffEventsWeb.Router
end
