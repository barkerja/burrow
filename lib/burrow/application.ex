defmodule Burrow.Application do
  @moduledoc """
  Main application module for the Burrow server.

  ## Configuration

  Set the mode via config or environment variable:

      # config/runtime.exs
      config :burrow, mode: :server

  Or via environment:

      BURROW_MODE=server mix run --no-halt

  ## Modes

  - `:server` - Starts the tunnel server
  - `:none` - Starts no children (default, for testing)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = children_for_mode(mode())
    opts = [strategy: :one_for_one, name: Burrow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp mode do
    Application.get_env(:burrow, :mode, :none)
  end

  defp children_for_mode(:server) do
    server_config = Application.get_env(:burrow, :server, [])
    port = Keyword.get(server_config, :port, 4000)

    [
      {DNSCluster, query: Application.get_env(:burrow, :dns_cluster_query) || :ignore},
      Burrow.ClusterMonitor,
      {Burrow.Server.Supervisor, port: port}
    ]
  end

  defp children_for_mode(_) do
    []
  end
end
