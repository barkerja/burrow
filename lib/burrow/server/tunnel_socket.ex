defmodule Burrow.Server.TunnelSocket do
  @moduledoc """
  WebSocket handler for tunnel connections.

  Implements the WebSock behavior to handle bidirectional communication
  between the server and tunnel clients.

  ## Connection Lifecycle

  1. Client connects via WebSocket
  2. Client sends `register_tunnel` message with attestation
  3. Server verifies attestation, registers tunnel, sends `tunnel_registered`
  4. Server sends `tunnel_request` messages when HTTP requests arrive
  5. Client sends `tunnel_response` messages with HTTP responses
  6. Either side can send `heartbeat` messages

  ## State

  - `:awaiting_registration` - Initial state, waiting for registration
  - `:connected` - Tunnel registered and active
  """

  @behaviour WebSock

  require Logger

  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.Crypto.Attestation
  alias Burrow.Server.{TunnelRegistry, PendingRequests, Subdomain, WSRegistry, TCPRegistry, TCPListener, TCPProxy}
  alias Burrow.ULID

  # Send heartbeat every 30 seconds to keep connection alive
  @heartbeat_interval_ms 30_000

  defstruct status: :awaiting_registration,
            tunnels: %{},
            tcp_tunnels: %{},
            client_public_key: nil

  @impl WebSock
  def init(_opts) do
    # Schedule first heartbeat
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval_ms)
    {:ok, %__MODULE__{}}
  end

  @impl WebSock
  def handle_in({text, [opcode: :text]}, state) do
    case Codec.decode(text) do
      {:ok, message} ->
        msg_type = Message.type(message)
        Logger.debug("[TunnelSocket] Received message type: #{msg_type}")
        handle_message(msg_type, message, state)

      {:error, _reason} ->
        error = Message.error("invalid_json", "Could not parse message as JSON")
        {:reply, :ok, {:text, Codec.encode!(error)}, state}
    end
  end

  def handle_in({_data, [opcode: :binary]}, state) do
    error = Message.error("unsupported_format", "Binary messages not supported")
    {:reply, :ok, {:text, Codec.encode!(error)}, state}
  end

  @impl WebSock
  def handle_info({:forward_request, json}, state) do
    {:push, {:text, json}, state}
  end

  def handle_info(:send_heartbeat, state) do
    # Schedule next heartbeat
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval_ms)
    # Send ping frame to keep connection alive
    {:push, {:ping, ""}, state}
  end

  def handle_info(_message, state) do
    {:ok, state}
  end

  @impl WebSock
  def terminate(_reason, state) do
    # Unregister all HTTP tunnels for this connection
    for {subdomain, _tunnel} <- state.tunnels do
      TunnelRegistry.unregister(subdomain)
    end

    # Stop all TCP listeners for this connection
    for {tcp_tunnel_id, tcp_tunnel} <- state.tcp_tunnels do
      if Process.alive?(tcp_tunnel.listener_pid) do
        GenServer.stop(tcp_tunnel.listener_pid, :normal)
      end
      TCPRegistry.unregister_tunnel(tcp_tunnel_id)
    end

    :ok
  end

  # Message Handlers

  defp handle_message(:register_tunnel, message, state) do
    case process_registration(message, state) do
      {:ok, tunnel_info, new_state} ->
        response =
          Message.tunnel_registered(
            tunnel_info.tunnel_id,
            tunnel_info.subdomain,
            tunnel_info.full_url
          )

        {:reply, :ok, {:text, Codec.encode!(response)}, new_state}

      {:error, :expired} ->
        error = Message.error("attestation_expired", "Attestation has expired")
        {:reply, :ok, {:text, Codec.encode!(error)}, state}

      {:error, :invalid_signature} ->
        error = Message.error("invalid_signature", "Attestation signature is invalid")
        {:reply, :ok, {:text, Codec.encode!(error)}, state}

      {:error, :subdomain_taken} ->
        error = Message.error("subdomain_taken", "Requested subdomain is already in use")
        {:reply, :ok, {:text, Codec.encode!(error)}, state}

      {:error, reason} ->
        error = Message.error("registration_failed", "Registration failed: #{inspect(reason)}")
        {:reply, :ok, {:text, Codec.encode!(error)}, state}
    end
  end

  defp handle_message(:tunnel_response, message, state) do
    request_id = message.request_id

    response_data = %{
      status: message.status,
      headers: message.headers,
      body: Map.get(message, :body),
      body_encoding: Map.get(message, :body_encoding)
    }

    case PendingRequests.complete(request_id, response_data) do
      :ok -> {:ok, state}
      {:error, :not_found} -> {:ok, state}
    end
  end

  defp handle_message(:heartbeat, _message, state) do
    response = Message.heartbeat()
    {:reply, :ok, {:text, Codec.encode!(response)}, state}
  end

  defp handle_message(:ws_upgraded, message, state) do
    # Client successfully connected to local WebSocket
    ws_id = message.ws_id
    headers = Map.get(message, :headers, [])
    Logger.debug("[TunnelSocket] Received ws_upgraded for #{ws_id}")
    WSRegistry.complete_pending(ws_id, {:ok, headers})
    {:ok, state}
  end

  defp handle_message(:ws_frame, message, state) do
    # Client forwarding a frame from local WebSocket to browser
    ws_id = message.ws_id
    opcode = parse_opcode(message.opcode)
    data = decode_frame_data(message.data, Map.get(message, :data_encoding))

    # Use forward_frame which buffers if WSProxy not yet registered
    WSRegistry.forward_frame(ws_id, opcode, data)

    {:ok, state}
  end

  defp handle_message(:ws_close, message, state) do
    # Client closing WebSocket connection
    ws_id = message.ws_id
    code = Map.get(message, :code, 1000)
    reason = Map.get(message, :reason, "")

    case WSRegistry.lookup(ws_id) do
      {:ok, proxy_pid} ->
        send(proxy_pid, {:ws_close, code, reason})

      {:error, :not_found} ->
        # Check if there's a pending upgrade for this ws_id
        # This handles the case where client couldn't connect to local WS
        Logger.debug("[TunnelSocket] Completing pending upgrade #{ws_id} with error: #{reason}")
        WSRegistry.complete_pending(ws_id, {:error, reason})
    end

    {:ok, state}
  end

  defp handle_message(:register_tcp_tunnel, message, state) do
    local_port = message.local_port
    tcp_tunnel_id = ULID.generate()

    Logger.info("[TunnelSocket] Registering TCP tunnel for local port #{local_port}")

    # Start the TCP listener
    {:ok, listener_pid} =
      TCPListener.start_link(
        tcp_tunnel_id: tcp_tunnel_id,
        connection_pid: self(),
        local_port: local_port
      )

    server_port = TCPListener.get_port(listener_pid)

    tcp_tunnels = Map.put(state.tcp_tunnels, tcp_tunnel_id, %{
      listener_pid: listener_pid,
      local_port: local_port,
      server_port: server_port
    })

    response = Message.tcp_tunnel_registered(tcp_tunnel_id, server_port, local_port)
    {:reply, :ok, {:text, Codec.encode!(response)}, %{state | tcp_tunnels: tcp_tunnels}}
  end

  defp handle_message(:tcp_connected, message, state) do
    # Client successfully connected to local service
    tcp_id = get_field(message, :tcp_id)

    case TCPRegistry.lookup_connection(tcp_id) do
      {:ok, proxy_pid} ->
        TCPProxy.connected(proxy_pid)

      {:error, :not_found} ->
        Logger.warning("[TunnelSocket] tcp_connected for unknown tcp_id: #{tcp_id}")
    end

    {:ok, state}
  end

  defp handle_message(:tcp_data, message, state) do
    # Client forwarding data from local service
    tcp_id = get_field(message, :tcp_id)
    data = decode_tcp_data(get_field(message, :data), get_field(message, :data_encoding))

    case TCPRegistry.lookup_connection(tcp_id) do
      {:ok, proxy_pid} ->
        TCPProxy.forward_data(proxy_pid, data)

      {:error, :not_found} ->
        Logger.warning("[TunnelSocket] tcp_data for unknown tcp_id: #{tcp_id}")
    end

    {:ok, state}
  end

  defp handle_message(:tcp_close, message, state) do
    # Client closing TCP connection
    tcp_id = get_field(message, :tcp_id)
    reason = get_field(message, :reason) || "closed"

    case TCPRegistry.lookup_connection(tcp_id) do
      {:ok, proxy_pid} ->
        TCPProxy.close(proxy_pid, reason)

      {:error, :not_found} ->
        :ok
    end

    {:ok, state}
  end

  defp handle_message(:unknown, _message, state) do
    error = Message.error("unknown_message", "Unknown message type")
    {:reply, :ok, {:text, Codec.encode!(error)}, state}
  end

  defp handle_message(_type, _message, state) do
    {:ok, state}
  end

  defp parse_opcode("text"), do: :text
  defp parse_opcode("binary"), do: :binary
  defp parse_opcode("ping"), do: :ping
  defp parse_opcode("pong"), do: :pong
  defp parse_opcode("close"), do: :close
  defp parse_opcode(_), do: :text

  # Helper to get field from message with either atom or string key
  defp get_field(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp decode_frame_data(data, "base64") when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  defp decode_frame_data(data, _), do: data

  defp decode_tcp_data(data, "base64") when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> decoded
      :error -> data
    end
  end

  defp decode_tcp_data(data, _), do: data

  # Registration Processing

  defp process_registration(message, state) do
    with {:ok, attestation} <- parse_attestation(message.attestation),
         :ok <- Attestation.verify(attestation),
         {:ok, subdomain} <- assign_subdomain(attestation, message),
         {:ok, tunnel_id} <- register_tunnel(subdomain, attestation, message) do
      tunnel_info = %{
        tunnel_id: tunnel_id,
        subdomain: subdomain,
        full_url: build_url(subdomain),
        local_host: message.local_host,
        local_port: message.local_port
      }

      new_state = %{
        state
        | status: :connected,
          client_public_key: attestation.public_key,
          tunnels: Map.put(state.tunnels, subdomain, tunnel_info)
      }

      {:ok, tunnel_info, new_state}
    end
  end

  defp parse_attestation(att_map) when is_map(att_map) do
    Attestation.from_map(att_map)
  end

  defp parse_attestation(_), do: {:error, :missing_attestation}

  defp assign_subdomain(attestation, message) do
    requested = Map.get(message, :requested_subdomain) || attestation.requested_subdomain

    cond do
      is_nil(requested) or requested == "" ->
        {:ok, Subdomain.from_public_key(attestation.public_key)}

      not Subdomain.valid?(requested) ->
        {:ok, Subdomain.from_public_key(attestation.public_key)}

      subdomain_available?(requested) ->
        {:ok, requested}

      true ->
        {:error, :subdomain_taken}
    end
  end

  defp subdomain_available?(subdomain) do
    case TunnelRegistry.lookup(subdomain) do
      {:error, :not_found} -> true
      {:ok, _} -> false
    end
  end

  defp register_tunnel(subdomain, attestation, message) do
    tunnel_id = ULID.generate()
    stream_ref = make_ref()

    params = %{
      tunnel_id: tunnel_id,
      subdomain: subdomain,
      client_public_key: attestation.public_key,
      connection_pid: self(),
      stream_ref: stream_ref,
      local_host: Map.get(message, :local_host, "localhost"),
      local_port: Map.get(message, :local_port, 80)
    }

    case TunnelRegistry.register(params) do
      {:ok, _} -> {:ok, tunnel_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_url(subdomain) do
    base_domain = Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
    "https://#{subdomain}.#{base_domain}"
  end
end
