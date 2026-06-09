import Config

config :prostaff_events, ProstaffEventsWeb.Endpoint,
  server: true,
  force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]

config :logger, level: :info
