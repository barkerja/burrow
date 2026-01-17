defmodule Burrow.Server.TCPListener do
  @moduledoc """
  TCP listener for a single TCP tunnel.

  Listens on a dynamically allocated port and accepts connections.
  Each connection is handled by a TCPProxy process.
  """

  use GenServer

  require Logger

  alias Burrow.Server.{TCPRegistry, TCPProxy}
  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.ULID

  @default_port_range 40000..40019

  defstruct [
    :tcp_tunnel_id,
    :connection_pid,
    :local_port,
    :listen_socket,
    :server_port
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get_port(pid) do
    GenServer.call(pid, :get_port)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    tcp_tunnel_id = Keyword.fetch!(opts, :tcp_tunnel_id)
    connection_pid = Keyword.fetch!(opts, :connection_pid)
    local_port = Keyword.fetch!(opts, :local_port)

    port_range = Application.get_env(:burrow, :tcp_port_range, @default_port_range)

    case find_available_port(port_range) do
      {:ok, listen_socket, server_port} ->
        Logger.info("[TCPListener #{tcp_tunnel_id}] Listening on port #{server_port} -> local:#{local_port}")

        # Register in registry
        TCPRegistry.register_tunnel(tcp_tunnel_id, %{
          listener_pid: self(),
          connection_pid: connection_pid,
          local_port: local_port,
          server_port: server_port
        })

        # Monitor the tunnel connection
        Process.monitor(connection_pid)

        # Start accepting connections
        send(self(), :accept)

        state = %__MODULE__{
          tcp_tunnel_id: tcp_tunnel_id,
          connection_pid: connection_pid,
          local_port: local_port,
          listen_socket: listen_socket,
          server_port: server_port
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("[TCPListener] Failed to find available port: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:reply, state.server_port, state}
  end

  @impl true
  def handle_info(:accept, state) do
    # Accept in a non-blocking way
    case :gen_tcp.accept(state.listen_socket, 0) do
      {:ok, client_socket} ->
        handle_new_connection(client_socket, state)
        send(self(), :accept)
        {:noreply, state}

      {:error, :timeout} ->
        # No connection waiting, try again soon
        Process.send_after(self(), :accept, 50)
        {:noreply, state}

      {:error, :closed} ->
        Logger.info("[TCPListener #{state.tcp_tunnel_id}] Listen socket closed")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("[TCPListener #{state.tcp_tunnel_id}] Accept error: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{connection_pid: pid} = state) do
    Logger.info("[TCPListener #{state.tcp_tunnel_id}] Tunnel connection died, shutting down")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    TCPRegistry.unregister_tunnel(state.tcp_tunnel_id)

    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    :ok
  end

  # Private Functions

  defp find_available_port(port_range) do
    Enum.reduce_while(port_range, {:error, :no_ports_available}, fn port, acc ->
      case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true]) do
        {:ok, socket} ->
          {:halt, {:ok, socket, port}}

        {:error, :eaddrinuse} ->
          {:cont, acc}

        {:error, reason} ->
          {:cont, {:error, reason}}
      end
    end)
  end

  defp handle_new_connection(client_socket, state) do
    tcp_id = ULID.generate()

    Logger.info("[TCPListener #{state.tcp_tunnel_id}] New connection: #{tcp_id}")

    # Start the server-side proxy
    {:ok, proxy_pid} =
      TCPProxy.start_link(
        tcp_id: tcp_id,
        tcp_tunnel_id: state.tcp_tunnel_id,
        connection_pid: state.connection_pid,
        local_port: state.local_port,
        client_socket: client_socket
      )

    # Transfer socket ownership to the proxy
    :gen_tcp.controlling_process(client_socket, proxy_pid)

    # Tell proxy to start
    TCPProxy.socket_transferred(proxy_pid)

    # Send tcp_connect to tunnel client
    msg = Message.tcp_connect(tcp_id, state.tcp_tunnel_id)
    send(state.connection_pid, {:forward_request, Codec.encode!(msg)})
  end
end
