defmodule Burrow.Server.RequestForwarder do
  @moduledoc """
  Forwards incoming HTTP requests through tunnels to connected clients.

  This module manages the request lifecycle:
  1. Receive incoming request
  2. Look up tunnel by subdomain
  3. Forward request through tunnel
  4. Await response
  5. Return response to original caller

  For WebSocket upgrade requests, this module initiates the upgrade
  handshake through the tunnel and hands off to WSProxy for frame forwarding.
  """

  import Plug.Conn

  require Logger

  alias Burrow.Server.{TunnelRegistry, PendingRequests, WSRegistry, WSProxy, RequestStore, ErrorPage}
  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.ULID

  @request_timeout_ms 30_000
  @ws_upgrade_timeout_ms 10_000
  # Maximum request body size (10MB) - prevents memory exhaustion from large uploads
  @max_body_size 10 * 1024 * 1024

  @doc """
  Forwards an incoming HTTP request through a tunnel.

  This is a synchronous operation that blocks until a response is received
  or the request times out.
  """
  @spec forward(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def forward(conn, subdomain) do
    case TunnelRegistry.lookup(subdomain) do
      {:ok, tunnel_info} ->
        forward_through_tunnel(conn, subdomain, tunnel_info)

      {:error, :not_found} ->
        ErrorPage.render(conn, 404, subdomain: subdomain)
    end
  end

  # Private functions

  defp forward_through_tunnel(conn, subdomain, tunnel_info) do
    if websocket_upgrade?(conn) do
      forward_websocket_upgrade(conn, tunnel_info)
    else
      forward_http_request(conn, subdomain, tunnel_info)
    end
  end

  defp websocket_upgrade?(conn) do
    # Check for WebSocket upgrade request
    connection = get_req_header(conn, "connection") |> List.first() || ""
    upgrade = get_req_header(conn, "upgrade") |> List.first() || ""

    String.downcase(connection) =~ "upgrade" and String.downcase(upgrade) == "websocket"
  end

  defp forward_http_request(conn, subdomain, tunnel_info) do
    request_id = ULID.generate()
    start_time = System.monotonic_time(:millisecond)

    # Read request body with size limit to prevent memory exhaustion
    case read_body_with_limit(conn) do
      {:ok, body, conn} ->
        forward_http_request_with_body(conn, subdomain, tunnel_info, request_id, start_time, body)

      {:error, :body_too_large} ->
        ErrorPage.render(conn, 413, max_size: @max_body_size)
    end
  end

  defp forward_http_request_with_body(conn, subdomain, tunnel_info, request_id, start_time, body) do

    # Extract useful header values for display
    headers = conn.req_headers
    user_agent = get_header(headers, "user-agent")
    content_type = get_header(headers, "content-type")
    referer = get_header(headers, "referer")
    client_ip = get_client_ip(headers, conn.remote_ip)

    # Log request to inspector
    RequestStore.log_request(%{
      id: request_id,
      tunnel_id: tunnel_info.tunnel_id,
      subdomain: subdomain,
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string,
      headers: headers,
      body: body,
      started_at: DateTime.utc_now(),
      # Additional metrics
      request_size: byte_size(body || ""),
      client_ip: client_ip,
      user_agent: user_agent,
      content_type: content_type,
      referer: referer
    })

    # Build request message
    request_data = %{
      method: conn.method,
      path: conn.request_path,
      query_string: conn.query_string,
      headers: format_headers(conn.req_headers),
      body: body,
      client_ip: client_ip
    }

    request_message =
      Message.tunnel_request(
        request_id,
        tunnel_info.tunnel_id,
        request_data
      )

    # Register as pending request
    :ok = PendingRequests.register(request_id, tunnel_info.tunnel_id, self())

    # Forward request to tunnel connection
    send(tunnel_info.connection_pid, {:forward_request, Codec.encode!(request_message)})

    # Wait for response
    receive do
      {:tunnel_response, ^request_id, response} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        log_response(request_id, response, duration_ms)
        build_response(conn, response)
    after
      @request_timeout_ms ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        log_response(request_id, {:error, :timeout}, duration_ms)
        PendingRequests.cancel(request_id)

        ErrorPage.render(conn, 504, context: :request)
    end
  end

  defp log_response(request_id, {:error, reason}, duration_ms) do
    error_body = "Error: #{inspect(reason)}"

    RequestStore.log_response(request_id, %{
      status: 504,
      headers: [],
      body: error_body,
      duration_ms: duration_ms,
      response_size: byte_size(error_body),
      response_content_type: nil
    })
  end

  defp log_response(request_id, response, duration_ms) when is_map(response) do
    status = get_field(response, :status, "status", 200)
    headers = get_field(response, :headers, "headers", [])
    body = get_field(response, :body, "body", "")
    body_encoding = get_field(response, :body_encoding, "body_encoding", nil)

    decoded_body = decode_body(body, body_encoding)
    response_content_type = get_response_header(headers, "content-type")

    # Store raw body (before decoding) for inspector
    RequestStore.log_response(request_id, %{
      status: status,
      headers: headers,
      body: decoded_body,
      duration_ms: duration_ms,
      response_size: byte_size(decoded_body || ""),
      response_content_type: response_content_type
    })
  end

  defp forward_websocket_upgrade(conn, tunnel_info) do
    ws_id = ULID.generate()

    # Build path with query string
    path =
      if conn.query_string == "" do
        conn.request_path
      else
        "#{conn.request_path}?#{conn.query_string}"
      end

    Logger.debug("[WS Upgrade] Starting upgrade for #{path}, ws_id=#{ws_id}")

    # Send ws_upgrade message to tunnel client
    upgrade_msg =
      Message.ws_upgrade(
        ws_id,
        tunnel_info.tunnel_id,
        path,
        format_headers(conn.req_headers)
      )

    # Register as pending WebSocket upgrade
    :ok = WSRegistry.register_pending(ws_id, self())

    # Forward to tunnel client
    send(tunnel_info.connection_pid, {:forward_request, Codec.encode!(upgrade_msg)})

    # Wait for ws_upgraded response
    receive do
      {:ws_upgrade_result, ^ws_id, {:ok, _response_headers}} ->
        Logger.debug("[WS Upgrade] Client connected, upgrading browser connection")
        # Client successfully connected to local WebSocket
        # Now upgrade browser connection to WebSocket
        conn
        |> WebSockAdapter.upgrade(
          WSProxy,
          [ws_id: ws_id, tunnel_pid: tunnel_info.connection_pid, tunnel_id: tunnel_info.tunnel_id],
          timeout: :infinity
        )
        |> halt()

      {:ws_upgrade_result, ^ws_id, {:error, reason}} ->
        Logger.error("[WS Upgrade] Client failed to connect: #{inspect(reason)}")
        ErrorPage.render(conn, 502, reason: inspect(reason))
    after
      @ws_upgrade_timeout_ms ->
        Logger.error("[WS Upgrade] Timeout waiting for client to connect")
        WSRegistry.unregister(ws_id)

        ErrorPage.render(conn, 504, context: :websocket)
    end
  end

  defp format_headers(headers) do
    Enum.map(headers, fn {key, value} -> [key, value] end)
  end

  defp build_response(conn, {:error, :timeout}) do
    ErrorPage.render(conn, 504, context: :request)
  end

  defp build_response(conn, {:error, reason}) do
    ErrorPage.render(conn, 502, reason: inspect(reason))
  end

  defp build_response(conn, response) when is_map(response) do
    # Handle both atom and string keys (JSON decodes to strings)
    status = get_field(response, :status, "status", 200)
    headers = get_field(response, :headers, "headers", [])
    body = get_field(response, :body, "body", "")
    body_encoding = get_field(response, :body_encoding, "body_encoding", nil)

    # Decode base64 body if needed
    body = decode_body(body, body_encoding)

    # For gateway errors (502, 504) from the tunnel client, render a nice HTML error page
    # These are tunnel infrastructure errors, not application errors
    if status in [502, 504] and is_tunnel_error?(body) do
      ErrorPage.render(conn, status, reason: body)
    else
      # Pass through normal responses (including application errors like 404, 500)
      # Filter out headers that Bandit should calculate
      skip_headers = ["content-length", "transfer-encoding"]

      conn =
        Enum.reduce(headers, conn, fn
          [key, value], acc ->
            if String.downcase(key) in skip_headers, do: acc, else: put_resp_header(acc, key, value)

          {key, value}, acc ->
            if String.downcase(key) in skip_headers, do: acc, else: put_resp_header(acc, key, value)

          _, acc ->
            acc
        end)

      send_resp(conn, status, body || "")
    end
  end

  # Detect if this is a tunnel client error (not an application error)
  defp is_tunnel_error?(body) when is_binary(body) do
    String.starts_with?(body, "Bad Gateway:") or
      String.starts_with?(body, "Gateway Timeout:")
  end

  defp is_tunnel_error?(_), do: false

  defp get_field(map, atom_key, string_key, default) do
    Map.get(map, atom_key) || Map.get(map, string_key) || default
  end

  defp decode_body(body, "base64") when is_binary(body) do
    case Base.decode64(body) do
      {:ok, decoded} -> decoded
      :error -> body
    end
  end

  defp decode_body(body, _encoding), do: body

  defp get_header(headers, name) do
    case List.keyfind(headers, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_response_header(headers, name) do
    # Response headers can be [[key, value], ...] or [{key, value}, ...]
    Enum.find_value(headers, fn
      [key, value] -> if String.downcase(key) == name, do: value
      {key, value} -> if String.downcase(key) == name, do: value
      _ -> nil
    end)
  end

  defp get_client_ip(headers, remote_ip) do
    case get_header(headers, "x-forwarded-for") do
      nil ->
        format_ip(remote_ip)

      forwarded_for ->
        # X-Forwarded-For can be "client, proxy1, proxy2" - take the first
        forwarded_for
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp format_ip(ip) when is_tuple(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp format_ip(ip), do: inspect(ip)

  # Read body with size limit to prevent memory exhaustion
  defp read_body_with_limit(conn, acc \\ <<>>) do
    case read_body(conn, length: @max_body_size) do
      {:ok, chunk, conn} ->
        body = acc <> chunk

        if byte_size(body) > @max_body_size do
          {:error, :body_too_large}
        else
          {:ok, body, conn}
        end

      {:more, chunk, conn} ->
        body = acc <> chunk

        if byte_size(body) > @max_body_size do
          {:error, :body_too_large}
        else
          read_body_with_limit(conn, body)
        end

      {:error, _} = error ->
        error
    end
  end
end
