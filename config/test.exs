import Config

# Don't auto-start server in test mode
config :burrow, mode: :none

config :burrow, :server,
  port: 4001,
  base_domain: "localhost"

config :burrow, :client,
  server_host: "localhost",
  server_port: 4001

config :logger, level: :warning
