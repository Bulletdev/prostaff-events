import Config

config :prostaff_events, ProstaffEventsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_long_enough_for_phoenix_to_accept_it_here",
  server: false

config :prostaff_events,
  internal_jwt_secret: "test_jwt_secret",
  scraper_api_key: "test_scraper_key",
  rails_api_url: "http://localhost:4010",
  rails_client: ProstaffEvents.MockRailsClient,
  reconciler_retry_delays: [10, 10, 10],
  rate_limit_window_ms: 60_000,
  rate_limit_max: 3

config :prostaff_events, :env, :test

config :logger, level: :warning
