import Config

config :burrow, :server,
  port: 4000,
  base_domain: "localhost"

config :burrow, :client,
  server_host: "localhost",
  server_port: 4000
