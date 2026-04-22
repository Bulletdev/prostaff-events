import Config

config :prostaff_events, ProstaffEventsWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: ProstaffEventsWeb.ErrorView], layout: false],
  pubsub_server: ProstaffEvents.PubSub,
  live_view: [signing_salt: "prostaff_events"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :event_type, :org_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
