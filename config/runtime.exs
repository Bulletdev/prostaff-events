import Config

# All secrets and environment-specific config are read at runtime.
# This allows the same Docker image to run in dev/staging/prod.

redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379/0"

# Phoenix.PubSub with Redis adapter for multi-node support and Rails integration.
# Rails publishes to: prostaff:events:<org_id>
# Phoenix subscribes via RedisSubscriber and re-broadcasts via PubSub.
config :prostaff_events,
  redis_url: redis_url,
  internal_jwt_secret: System.get_env("INTERNAL_JWT_SECRET") || raise("INTERNAL_JWT_SECRET is required"),
  rails_api_url: System.get_env("RAILS_API_URL") || "http://localhost:3333",
  rails_internal_secret: System.get_env("INTERNAL_JWT_SECRET"),
  scraper_api_key: System.get_env("SCRAPER_API_KEY") || ""

if config_env() == :prod do
  config :prostaff_events, ProstaffEventsWeb.Endpoint,
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE is required"),
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"]
end

config :prostaff_events, ProstaffEventsWeb.Endpoint,
  secret_key_base: System.get_env("SECRET_KEY_BASE") || "dev_secret_key_base_at_least_64_chars_long_xxxxxxxxxxxxxxxxxxxxxx"
