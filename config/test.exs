import Config

# Don't auto-start server in test mode
config :burrow, mode: :none

config :burrow, :server,
  port: 4001,
  base_domain: "localhost"

config :burrow, :client,
  server_host: "localhost",
  server_port: 4001

# Test database configuration (only used if DATABASE_URL is set)
config :burrow, Burrow.Repo,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Disable Oban queues in test
config :burrow, Oban, testing: :inline

config :logger, level: :warning
