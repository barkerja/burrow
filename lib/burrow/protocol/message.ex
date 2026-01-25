defmodule Burrow.Protocol.Message do
  @moduledoc """
  Message type definitions and builders for the tunnel protocol.

  All messages are maps with a `type` field indicating the message type.

  ## Message Types

  - `register_tunnel` - Client → Server: Request tunnel registration
  - `tunnel_registered` - Server → Client: Tunnel created with subdomain
  - `tunnel_request` - Server → Client: Incoming HTTP request
  - `tunnel_response` - Client → Server: HTTP response
  - `ws_upgrade` - Server → Client: Request WebSocket upgrade to local service
  - `ws_upgraded` - Client → Server: WebSocket upgrade successful
  - `ws_frame` - Bidirectional: Forward a WebSocket frame
  - `ws_close` - Bidirectional: Close the proxied WebSocket
  - `heartbeat` - Bidirectional: Keep-alive ping
  - `error` - Bidirectional: Error notification
  """

  @type message_type ::
          :register_tunnel
          | :tunnel_registered
          | :tunnel_request
          | :tunnel_response
          | :ws_upgrade
          | :ws_upgraded
          | :ws_frame
          | :ws_close
          | :register_tcp_tunnel
          | :tcp_tunnel_registered
          | :tcp_connect
          | :tcp_connected
          | :tcp_data
          | :tcp_close
          | :heartbeat
          | :error

  @doc """
  Builds a register_tunnel message.

  ## Examples

      iex> msg = Burrow.Protocol.Message.register_tunnel("brw_abc123", "localhost", 3000)
      iex> msg.type
      "register_tunnel"

      iex> msg = Burrow.Protocol.Message.register_tunnel("brw_abc123", "localhost", 3000, "myapp")
      iex> msg.requested_subdomain
      "myapp"
  """
  @spec register_tunnel(String.t(), String.t(), pos_integer(), String.t() | nil) :: map()
  def register_tunnel(token, local_host, local_port, requested_subdomain \\ nil) do
    %{
      type: "register_tunnel",
      token: token,
      local_host: local_host,
      local_port: local_port,
      requested_subdomain: requested_subdomain
    }
  end

  @doc """
  Builds a tunnel_registered response.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tunnel_registered("tid", "abc", "https://abc.example.com")
      iex> msg.type
      "tunnel_registered"
  """
  @spec tunnel_registered(String.t(), String.t(), String.t()) :: map()
  def tunnel_registered(tunnel_id, subdomain, full_url) do
    %{
      type: "tunnel_registered",
      tunnel_id: tunnel_id,
      subdomain: subdomain,
      full_url: full_url
    }
  end

  @doc """
  Builds a tunnel_request message.

  ## Examples

      iex> req = %{method: "GET", path: "/", query_string: "", headers: [], body: nil}
      iex> msg = Burrow.Protocol.Message.tunnel_request("rid", "tid", req)
      iex> msg.type
      "tunnel_request"
  """
  @spec tunnel_request(String.t(), String.t(), map()) :: map()
  def tunnel_request(request_id, tunnel_id, request_data) do
    %{
      type: "tunnel_request",
      request_id: request_id,
      tunnel_id: tunnel_id,
      method: request_data.method,
      path: request_data.path,
      query_string: request_data.query_string || "",
      headers: request_data.headers,
      body: request_data.body,
      client_ip: request_data[:client_ip]
    }
  end

  @doc """
  Builds a tunnel_response message.

  Binary bodies are automatically base64 encoded for JSON transport.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tunnel_response("rid", 200, [], "OK")
      iex> msg.type
      "tunnel_response"
  """
  @spec tunnel_response(String.t(), integer(), list(), binary() | nil) :: map()
  def tunnel_response(request_id, status, headers, body) do
    {encoded_body, encoding} = encode_body(body)

    %{
      type: "tunnel_response",
      request_id: request_id,
      status: status,
      headers: encode_headers(headers),
      body: encoded_body,
      body_encoding: encoding
    }
  end

  defp encode_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      # Convert tuples to lists for JSON
      {k, v} -> [k, v]
      # Already a list
      [k, v] -> [k, v]
      other -> other
    end)
  end

  defp encode_headers(nil), do: []

  defp encode_body(nil), do: {nil, nil}
  defp encode_body(""), do: {"", nil}

  defp encode_body(body) when is_binary(body) do
    if String.valid?(body) do
      {body, nil}
    else
      {Base.encode64(body), "base64"}
    end
  end

  @doc """
  Builds a heartbeat message.

  ## Examples

      iex> msg = Burrow.Protocol.Message.heartbeat()
      iex> msg.type
      "heartbeat"
  """
  @spec heartbeat() :: map()
  def heartbeat do
    %{
      type: "heartbeat",
      timestamp: System.system_time(:second)
    }
  end

  @doc """
  Builds an error message.

  ## Examples

      iex> msg = Burrow.Protocol.Message.error("invalid_token", "Token expired")
      iex> msg.type
      "error"
  """
  @spec error(String.t(), String.t()) :: map()
  def error(code, message) do
    %{
      type: "error",
      code: code,
      message: message
    }
  end

  @doc """
  Returns the message type as an atom.

  ## Examples

      iex> Burrow.Protocol.Message.type(%{type: "heartbeat"})
      :heartbeat
      iex> Burrow.Protocol.Message.type(%{type: "unknown"})
      :unknown
  """
  @spec type(map() | nil) :: message_type() | :unknown
  def type(%{type: "register_tunnel"}), do: :register_tunnel
  def type(%{type: "tunnel_registered"}), do: :tunnel_registered
  def type(%{type: "tunnel_request"}), do: :tunnel_request
  def type(%{type: "tunnel_response"}), do: :tunnel_response
  def type(%{type: "heartbeat"}), do: :heartbeat
  def type(%{type: "error"}), do: :error
  def type(%{type: "ws_upgrade"}), do: :ws_upgrade
  def type(%{type: "ws_upgraded"}), do: :ws_upgraded
  def type(%{type: "ws_frame"}), do: :ws_frame
  def type(%{type: "ws_close"}), do: :ws_close
  def type(%{type: "register_tcp_tunnel"}), do: :register_tcp_tunnel
  def type(%{type: "tcp_tunnel_registered"}), do: :tcp_tunnel_registered
  def type(%{type: "tcp_connect"}), do: :tcp_connect
  def type(%{type: "tcp_connected"}), do: :tcp_connected
  def type(%{type: "tcp_data"}), do: :tcp_data
  def type(%{type: "tcp_close"}), do: :tcp_close
  def type(_), do: :unknown

  # WebSocket Passthrough Messages

  @doc """
  Builds a ws_upgrade message (Server → Client).

  Sent when an incoming request is a WebSocket upgrade request.
  The client should establish a WebSocket connection to the local service.

  ## Examples

      iex> msg = Burrow.Protocol.Message.ws_upgrade("wsid", "tid", "/socket", [["upgrade", "websocket"]])
      iex> msg.type
      "ws_upgrade"
  """
  @spec ws_upgrade(String.t(), String.t(), String.t(), list()) :: map()
  def ws_upgrade(ws_id, tunnel_id, path, headers) do
    %{
      type: "ws_upgrade",
      ws_id: ws_id,
      tunnel_id: tunnel_id,
      path: path,
      headers: headers
    }
  end

  @doc """
  Builds a ws_upgraded message (Client → Server).

  Sent when the client successfully establishes a WebSocket connection
  to the local service.

  ## Examples

      iex> msg = Burrow.Protocol.Message.ws_upgraded("wsid", [["sec-websocket-accept", "abc"]])
      iex> msg.type
      "ws_upgraded"
  """
  @spec ws_upgraded(String.t(), list()) :: map()
  def ws_upgraded(ws_id, headers) do
    %{
      type: "ws_upgraded",
      ws_id: ws_id,
      headers: headers
    }
  end

  @doc """
  Builds a ws_frame message (Bidirectional).

  Forwards a WebSocket frame between browser and local service.

  ## Examples

      iex> msg = Burrow.Protocol.Message.ws_frame("wsid", :text, "hello")
      iex> msg.type
      "ws_frame"
  """
  @spec ws_frame(String.t(), atom(), binary()) :: map()
  def ws_frame(ws_id, opcode, data) do
    {encoded_data, encoding} = encode_frame_data(opcode, data)

    %{
      type: "ws_frame",
      ws_id: ws_id,
      opcode: Atom.to_string(opcode),
      data: encoded_data,
      data_encoding: encoding
    }
  end

  defp encode_frame_data(:text, data), do: {data, nil}
  defp encode_frame_data(:binary, data), do: {Base.encode64(data), "base64"}
  defp encode_frame_data(:ping, data), do: {Base.encode64(data), "base64"}
  defp encode_frame_data(:pong, data), do: {Base.encode64(data), "base64"}
  defp encode_frame_data(_opcode, data), do: {Base.encode64(data), "base64"}

  @doc """
  Builds a ws_close message (Bidirectional).

  Indicates the WebSocket connection should be closed.

  ## Examples

      iex> msg = Burrow.Protocol.Message.ws_close("wsid", 1000, "normal closure")
      iex> msg.type
      "ws_close"
  """
  @spec ws_close(String.t(), integer(), String.t()) :: map()
  def ws_close(ws_id, code \\ 1000, reason \\ "") do
    %{
      type: "ws_close",
      ws_id: ws_id,
      code: code,
      reason: reason
    }
  end

  # TCP Tunneling Messages

  @doc """
  Builds a register_tcp_tunnel message (Client → Server).

  Sent when the client wants to register a TCP tunnel.
  The server will allocate a port and start listening.

  ## Examples

      iex> msg = Burrow.Protocol.Message.register_tcp_tunnel(5432)
      iex> msg.type
      "register_tcp_tunnel"
  """
  @spec register_tcp_tunnel(pos_integer()) :: map()
  def register_tcp_tunnel(local_port) do
    %{
      type: "register_tcp_tunnel",
      local_port: local_port
    }
  end

  @doc """
  Builds a tcp_tunnel_registered message (Server → Client).

  Sent when the server has allocated a port for the TCP tunnel.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tcp_tunnel_registered("tid", 45123, 5432)
      iex> msg.type
      "tcp_tunnel_registered"
  """
  @spec tcp_tunnel_registered(String.t(), pos_integer(), pos_integer()) :: map()
  def tcp_tunnel_registered(tcp_tunnel_id, server_port, local_port) do
    %{
      type: "tcp_tunnel_registered",
      tcp_tunnel_id: tcp_tunnel_id,
      server_port: server_port,
      local_port: local_port
    }
  end

  @doc """
  Builds a tcp_connect message (Server → Client).

  Sent when an external client connects to the server's TCP port.
  The tunnel client should establish a connection to the local service.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tcp_connect("connid", "tid")
      iex> msg.type
      "tcp_connect"
  """
  @spec tcp_connect(String.t(), String.t()) :: map()
  def tcp_connect(tcp_id, tcp_tunnel_id) do
    %{
      type: "tcp_connect",
      tcp_id: tcp_id,
      tcp_tunnel_id: tcp_tunnel_id
    }
  end

  @doc """
  Builds a tcp_connected message (Client → Server).

  Sent when the tunnel client has established a connection to the local service.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tcp_connected("connid")
      iex> msg.type
      "tcp_connected"
  """
  @spec tcp_connected(String.t()) :: map()
  def tcp_connected(tcp_id) do
    %{
      type: "tcp_connected",
      tcp_id: tcp_id
    }
  end

  @doc """
  Builds a tcp_data message (Bidirectional).

  Forwards TCP data between external client and local service.
  Binary data is automatically base64 encoded.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tcp_data("connid", "hello")
      iex> msg.type
      "tcp_data"
  """
  @spec tcp_data(String.t(), binary()) :: map()
  def tcp_data(tcp_id, data) do
    %{
      type: "tcp_data",
      tcp_id: tcp_id,
      data: Base.encode64(data),
      data_encoding: "base64"
    }
  end

  @doc """
  Builds a tcp_close message (Bidirectional).

  Indicates the TCP connection should be closed.

  ## Examples

      iex> msg = Burrow.Protocol.Message.tcp_close("connid", "connection reset")
      iex> msg.type
      "tcp_close"
  """
  @spec tcp_close(String.t(), String.t()) :: map()
  def tcp_close(tcp_id, reason \\ "closed") do
    %{
      type: "tcp_close",
      tcp_id: tcp_id,
      reason: reason
    }
  end
end
