defmodule Burrow.Server.WSProxy do
  @moduledoc """
  WebSocket proxy handler for tunneled WebSocket connections.

  When a browser connects to a subdomain with a WebSocket upgrade request,
  this handler proxies frames between the browser and the tunnel client,
  which in turn connects to the local service.

  ## Flow

  1. Browser initiates WebSocket upgrade to subdomain
  2. Server creates WSProxy, sends ws_upgrade through tunnel
  3. Tunnel client connects to local service
  4. Client sends ws_upgraded back
  5. Server completes WebSocket handshake with browser
  6. Frames flow bidirectionally through the tunnel
  """

  @behaviour WebSock

  require Logger

  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.Server.WSRegistry

  defstruct [:ws_id, :tunnel_pid, :tunnel_id, :status]

  @impl WebSock
  def init(opts) do
    ws_id = Keyword.fetch!(opts, :ws_id)
    tunnel_pid = Keyword.fetch!(opts, :tunnel_pid)
    tunnel_id = Keyword.fetch!(opts, :tunnel_id)

    Logger.debug("[WSProxy #{ws_id}] Initializing server-side proxy")

    # Register ourselves so tunnel can send us frames
    WSRegistry.register(ws_id, self())

    {:ok,
     %__MODULE__{
       ws_id: ws_id,
       tunnel_pid: tunnel_pid,
       tunnel_id: tunnel_id,
       status: :connected
     }}
  end

  @impl WebSock
  def handle_in({data, [opcode: opcode]}, state) do
    # Browser sent a frame, forward to tunnel client
    Logger.debug("[WSProxy #{state.ws_id}] Browser sent frame: #{opcode}, #{byte_size(data)} bytes")
    frame_msg = Message.ws_frame(state.ws_id, opcode, data)
    send(state.tunnel_pid, {:forward_request, Codec.encode!(frame_msg)})
    {:ok, state}
  end

  @impl WebSock
  def handle_info({:ws_frame, opcode, data}, state) do
    # Tunnel client sent a frame, forward to browser
    Logger.debug("[WSProxy #{state.ws_id}] Forwarding frame to browser: #{opcode}, #{byte_size(data)} bytes")
    {:push, {opcode, data}, state}
  end

  def handle_info({:ws_close, code, reason}, state) do
    # Tunnel client wants to close
    Logger.debug("[WSProxy #{state.ws_id}] Received close from tunnel: #{code} #{reason}")
    WSRegistry.unregister(state.ws_id)
    {:stop, :normal, {code, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[WSProxy #{state.ws_id}] Unknown message: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSock
  def terminate(reason, state) do
    Logger.debug("[WSProxy #{state.ws_id}] Terminating: #{inspect(reason)}")
    # Notify tunnel client that WebSocket closed
    close_msg = Message.ws_close(state.ws_id, 1000, "connection closed")
    send(state.tunnel_pid, {:forward_request, Codec.encode!(close_msg)})

    WSRegistry.unregister(state.ws_id)
    :ok
  end
end
