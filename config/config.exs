import Config

# Default mode is :none - CLI and scripts should start supervisors explicitly
# Set mode: :server or mode: :client to auto-start on application boot
config :burrow,
  mode: :none

# Phoenix endpoint configuration for request inspector
# server: false means it won't start its own HTTP server - we plug it into the main endpoint
config :burrow, Burrow.Server.Web.Endpoint,
  url: [host: "localhost"],
  server: false,
  secret_key_base: "generate_a_proper_secret_for_production_use_please_this_is_just_dev",
  live_view: [signing_salt: "burrow_inspector_salt"],
  render_errors: [formats: [html: Burrow.Server.Web.ErrorHTML], layout: false],
  pubsub_server: Burrow.PubSub

# WebAuthn configuration for passkey authentication
config :burrow, :webauthn,
  origin: "http://localhost:4000",
  rp_id: "localhost",
  rp_name: "Burrow"

# Oban background job configuration
config :burrow, Oban,
  repo: Burrow.Repo,
  queues: [default: 10]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Ecto Repo configuration
config :burrow, ecto_repos: [Burrow.Repo]

config :burrow, Burrow.Repo,
  migration_primary_key: [type: :binary_id],
  migration_timestamps: [type: :utc_datetime_usec]

import_config "#{config_env()}.exs"
