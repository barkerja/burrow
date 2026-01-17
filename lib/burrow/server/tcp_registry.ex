defmodule Burrow.Server.TCPRegistry do
  @moduledoc """
  Registry for TCP tunnels and connections.

  Tracks:
  - TCP tunnels (tcp_tunnel_id → listener info)
  - TCP connections (tcp_id → proxy pid)
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a TCP tunnel.
  """
  def register_tunnel(tcp_tunnel_id, info) do
    GenServer.call(__MODULE__, {:register_tunnel, tcp_tunnel_id, info})
  end

  @doc """
  Looks up a TCP tunnel by ID.
  """
  def lookup_tunnel(tcp_tunnel_id) do
    GenServer.call(__MODULE__, {:lookup_tunnel, tcp_tunnel_id})
  end

  @doc """
  Unregisters a TCP tunnel.
  """
  def unregister_tunnel(tcp_tunnel_id) do
    GenServer.cast(__MODULE__, {:unregister_tunnel, tcp_tunnel_id})
  end

  @doc """
  Registers a TCP connection (proxy).
  """
  def register_connection(tcp_id, proxy_pid) do
    GenServer.call(__MODULE__, {:register_connection, tcp_id, proxy_pid})
  end

  @doc """
  Looks up a TCP connection by ID.
  """
  def lookup_connection(tcp_id) do
    GenServer.call(__MODULE__, {:lookup_connection, tcp_id})
  end

  @doc """
  Unregisters a TCP connection.
  """
  def unregister_connection(tcp_id) do
    GenServer.cast(__MODULE__, {:unregister_connection, tcp_id})
  end

  @doc """
  Lists all TCP tunnels for a given connection PID.
  """
  def list_tunnels_for_connection(connection_pid) do
    GenServer.call(__MODULE__, {:list_tunnels_for_connection, connection_pid})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables for fast lookups
    tunnels = :ets.new(:tcp_tunnels, [:set, :protected])
    connections = :ets.new(:tcp_connections, [:set, :protected])

    {:ok, %{tunnels: tunnels, connections: connections}}
  end

  @impl true
  def handle_call({:register_tunnel, tcp_tunnel_id, info}, _from, state) do
    :ets.insert(state.tunnels, {tcp_tunnel_id, info})
    {:reply, :ok, state}
  end

  def handle_call({:lookup_tunnel, tcp_tunnel_id}, _from, state) do
    result =
      case :ets.lookup(state.tunnels, tcp_tunnel_id) do
        [{^tcp_tunnel_id, info}] -> {:ok, info}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:register_connection, tcp_id, proxy_pid}, _from, state) do
    :ets.insert(state.connections, {tcp_id, proxy_pid})
    {:reply, :ok, state}
  end

  def handle_call({:lookup_connection, tcp_id}, _from, state) do
    result =
      case :ets.lookup(state.connections, tcp_id) do
        [{^tcp_id, proxy_pid}] -> {:ok, proxy_pid}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:list_tunnels_for_connection, connection_pid}, _from, state) do
    tunnels =
      :ets.tab2list(state.tunnels)
      |> Enum.filter(fn {_id, info} -> info.connection_pid == connection_pid end)
      |> Enum.map(fn {id, info} -> {id, info} end)

    {:reply, tunnels, state}
  end

  @impl true
  def handle_cast({:unregister_tunnel, tcp_tunnel_id}, state) do
    :ets.delete(state.tunnels, tcp_tunnel_id)
    {:noreply, state}
  end

  def handle_cast({:unregister_connection, tcp_id}, state) do
    :ets.delete(state.connections, tcp_id)
    {:noreply, state}
  end
end
