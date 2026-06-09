import Config

# All secrets and environment-specific config are read at runtime.
# This allows the same Docker image to run in dev/staging/prod.

redis_url =
  case System.get_env("REDIS_URL") do
    nil ->
      "redis://localhost:6379/0"

    "" ->
      "redis://localhost:6379/0"

    url ->
      # Defend against a missing scheme - Coolify sometimes strips it
      if String.contains?(url, "://"), do: url, else: "redis://#{url}"
  end

# Phoenix.PubSub with Redis adapter for multi-node support and Rails integration.
# Rails publishes to: prostaff:events:<org_id>
# Phoenix subscribes via RedisSubscriber and re-broadcasts via PubSub.
internal_jwt_secret =
  if config_env() == :test do
    System.get_env("INTERNAL_JWT_SECRET", "test_jwt_secret")
  else
    System.get_env("INTERNAL_JWT_SECRET") || raise("INTERNAL_JWT_SECRET is required")
  end

scraper_api_key =
  if config_env() == :test,
    do: Application.get_env(:prostaff_events, :scraper_api_key, ""),
    else: System.get_env("SCRAPER_API_KEY") || ""

config :prostaff_events,
  redis_url: redis_url,
  internal_jwt_secret: internal_jwt_secret,
  rails_api_url: System.get_env("RAILS_API_URL") || "http://localhost:3333",
  rails_internal_secret: internal_jwt_secret,
  scraper_api_key: scraper_api_key

if config_env() == :prod do
  config :prostaff_events, ProstaffEventsWeb.Endpoint,
    http: [
      port: String.to_integer(System.get_env("PORT") || "4000"),
      transport_options: [socket_opts: [:inet6]]
    ],
    secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE is required"),
    url: [host: System.get_env("PHX_HOST") || "localhost", port: 443, scheme: "https"],
    # TLS is terminated at Traefik; force_ssl ensures Phoenix redirects HTTP
    # and sets HSTS headers on responses that pass through the proxy.
    force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]
end

config :prostaff_events, ProstaffEventsWeb.Endpoint,
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "dev_secret_key_base_at_least_64_chars_long_xxxxxxxxxxxxxxxxxxxxxx"
