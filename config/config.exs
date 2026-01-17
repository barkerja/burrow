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

# GitHub OAuth configuration for inspector authentication
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email,read:org"]}
  ]

# GitHub OAuth credentials - set via environment variables in runtime.exs
# GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET must be set for auth to work
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: nil,
  client_secret: nil

# Inspector authorization - defaults allow all authenticated users
# Override via INSPECTOR_ALLOWED_USERS and INSPECTOR_ALLOWED_ORGS env vars
config :burrow, :inspector_auth,
  allowed_users: [],
  allowed_orgs: []

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
