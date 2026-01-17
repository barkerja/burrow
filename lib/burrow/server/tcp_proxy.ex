defmodule Burrow.Server.TCPProxy do
  @moduledoc """
  Server-side proxy for a single TCP connection through a tunnel.

  Handles:
  - Receiving data from external client, forwarding to tunnel
  - Receiving data from tunnel, forwarding to external client
  - Cleanup on connection close
  """

  use GenServer

  require Logger

  alias Burrow.Server.TCPRegistry
  alias Burrow.Protocol.{Codec, Message}

  defstruct [
    :tcp_id,
    :tcp_tunnel_id,
    :connection_pid,
    :local_port,
    :client_socket,
    :status
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Called after socket ownership is transferred to this process.
  """
  def socket_transferred(pid) do
    GenServer.cast(pid, :socket_transferred)
  end

  @doc """
  Called when the tunnel client has connected to the local service.
  """
  def connected(pid) do
    GenServer.cast(pid, :connected)
  end

  @doc """
  Forward data from tunnel to external client.
  """
  def forward_data(pid, data) do
    GenServer.cast(pid, {:forward_data, data})
  end

  @doc """
  Close the connection.
  """
  def close(pid, reason \\ "closed") do
    GenServer.cast(pid, {:close, reason})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    tcp_id = Keyword.fetch!(opts, :tcp_id)
    tcp_tunnel_id = Keyword.fetch!(opts, :tcp_tunnel_id)
    connection_pid = Keyword.fetch!(opts, :connection_pid)
    local_port = Keyword.fetch!(opts, :local_port)
    client_socket = Keyword.fetch!(opts, :client_socket)

    # Register in registry
    TCPRegistry.register_connection(tcp_id, self())

    # Monitor the tunnel connection
    Process.monitor(connection_pid)

    state = %__MODULE__{
      tcp_id: tcp_id,
      tcp_tunnel_id: tcp_tunnel_id,
      connection_pid: connection_pid,
      local_port: local_port,
      client_socket: client_socket,
      status: :waiting_for_transfer
    }

    {:ok, state}
  end

  @impl true
  def handle_cast(:socket_transferred, state) do
    # Now we own the socket, wait for tunnel client to connect
    {:noreply, %{state | status: :waiting_for_client}}
  end

  def handle_cast(:connected, state) do
    # Tunnel client connected to local service, start receiving data
    Logger.debug("[TCPProxy #{state.tcp_id}] Client connected, activating socket")
    :inet.setopts(state.client_socket, active: true)
    {:noreply, %{state | status: :connected}}
  end

  def handle_cast({:forward_data, data}, state) do
    if state.status == :connected do
      case :gen_tcp.send(state.client_socket, data) do
        :ok ->
          {:noreply, state}

        {:error, reason} ->
          Logger.debug("[TCPProxy #{state.tcp_id}] Failed to send to client: #{inspect(reason)}")
          send_close(state, inspect(reason))
          {:stop, :normal, state}
      end
    else
      # Buffer data if not yet connected?
      # For simplicity, drop it
      Logger.warning("[TCPProxy #{state.tcp_id}] Received data before connected, dropping")
      {:noreply, state}
    end
  end

  def handle_cast({:close, reason}, state) do
    Logger.debug("[TCPProxy #{state.tcp_id}] Closing: #{reason}")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    # Data from external client, forward to tunnel
    Logger.debug("[TCPProxy #{state.tcp_id}] Received #{byte_size(data)} bytes from client")
    msg = Message.tcp_data(state.tcp_id, data)
    send(state.connection_pid, {:forward_request, Codec.encode!(msg)})
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.debug("[TCPProxy #{state.tcp_id}] Client closed connection")
    send_close(state, "client closed")
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.debug("[TCPProxy #{state.tcp_id}] Socket error: #{inspect(reason)}")
    send_close(state, inspect(reason))
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{connection_pid: pid} = state) do
    Logger.debug("[TCPProxy #{state.tcp_id}] Tunnel connection died")
    {:stop, :normal, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    TCPRegistry.unregister_connection(state.tcp_id)

    if state.client_socket do
      :gen_tcp.close(state.client_socket)
    end

    :ok
  end

  # Private Functions

  defp send_close(state, reason) do
    msg = Message.tcp_close(state.tcp_id, reason)
    send(state.connection_pid, {:forward_request, Codec.encode!(msg)})
  end
end
