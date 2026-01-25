import Config

# PostgreSQL configuration (required)
database_url =
  System.get_env("DATABASE_URL") ||
    raise "DATABASE_URL environment variable is not set"

repo_config = [
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
]

repo_config =
  if database_host = System.get_env("DATABASE_HOST") do
    repo_config ++
      [
        ssl: [
          verify: :verify_peer,
          cacertfile: CAStore.file_path(),
          server_name_indication: String.to_charlist(database_host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ]
  else
    repo_config
  end

config :burrow, Burrow.Repo, repo_config

# Read mode from environment variable (works in all envs)
if mode = System.get_env("BURROW_MODE") do
  config :burrow, mode: String.to_existing_atom(mode)
end

# Read port from environment (works in all envs)
if port = System.get_env("PORT") do
  config :burrow, :server, port: String.to_integer(port)
end

# Read base domain from environment (works in all envs)
if base_domain = System.get_env("BASE_DOMAIN") do
  config :burrow, :server, base_domain: base_domain
end

# ACME storage directory (works in all envs)
if acme_dir = System.get_env("ACME_STORAGE_DIR") do
  config :burrow, :acme, storage_dir: acme_dir
end

# TCP tunnel port range (works in all envs)
# Format: "40000..40019" or defaults to 40000..40019
tcp_port_range =
  case System.get_env("TCP_PORT_RANGE") do
    nil ->
      40000..40019

    range_str ->
      [start_str, stop_str] = String.split(range_str, "..")
      String.to_integer(start_str)..String.to_integer(stop_str)
  end

config :burrow, tcp_port_range: tcp_port_range

if config_env() == :prod do
  base_domain = System.get_env("BURROW_DOMAIN") || raise("BURROW_DOMAIN required")

  # Phoenix endpoint configuration for production
  config :burrow, Burrow.Server.Web.Endpoint,
    url: [host: base_domain, scheme: "https", port: 443],
    secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("SECRET_KEY_BASE required"),
    live_view: [signing_salt: System.get_env("LIVE_VIEW_SALT") || "burrow_inspector_prod"]

  # WebAuthn configuration for production
  config :burrow, :webauthn,
    origin: "https://#{base_domain}",
    rp_id: base_domain,
    rp_name: "Burrow"

  # Production server configuration
  server_config = [
    port: String.to_integer(System.get_env("BURROW_PORT") || "443"),
    base_domain: base_domain
  ]

  # TLS configuration
  server_config =
    cond do
      # ACME/Let's Encrypt automatic TLS
      System.get_env("ACME_EMAIL") ->
        acme_config = [
          email: System.get_env("ACME_EMAIL"),
          domains:
            System.get_env("ACME_DOMAINS", "")
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == "")),
          directory_url:
            case System.get_env("ACME_DIRECTORY", "production") do
              "staging" -> :staging
              _ -> :production
            end
        ]

        # Add Cloudflare DNS provider config if present
        acme_config =
          if cf_token = System.get_env("CLOUDFLARE_API_TOKEN") do
            acme_config
            |> Keyword.put(:dns_provider, :cloudflare)
            |> Keyword.put(:cloudflare_api_token, cf_token)
            |> Keyword.put(:cloudflare_zone_id, System.get_env("CLOUDFLARE_ZONE_ID"))
          else
            acme_config
          end

        server_config
        |> Keyword.put(:tls, true)
        |> Keyword.put(:acme, acme_config)
        |> Keyword.put(:http_port, String.to_integer(System.get_env("HTTP_PORT") || "80"))

      # Manual certificate files
      System.get_env("BURROW_CERTFILE") && System.get_env("BURROW_KEYFILE") ->
        server_config
        |> Keyword.put(:tls, true)
        |> Keyword.put(:certfile, System.get_env("BURROW_CERTFILE"))
        |> Keyword.put(:keyfile, System.get_env("BURROW_KEYFILE"))

      # No TLS
      true ->
        server_config
    end

  config :burrow, :server, server_config

  config :burrow, dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")
end
