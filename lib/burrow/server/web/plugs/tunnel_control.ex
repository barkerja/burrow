defmodule Burrow.Server.Web.Plugs.TunnelControl do
  @moduledoc """
  Handles tunnel control endpoints on the main domain.

  These are API endpoints used by tunnel clients to:
  - Check server health
  - Establish WebSocket tunnel connections
  - Register tunnels (HTTP fallback)
  - Send tunnel responses (HTTP fallback)
  """

  import Plug.Conn

  alias Burrow.Server.{ControlHandler, TunnelSocket}

  def init(opts), do: opts

  def call(%{method: "GET", request_path: "/health"} = conn, _opts) do
    conn
    |> send_resp(200, "ok")
    |> halt()
  end

  def call(%{method: "GET", request_path: "/tunnel/ws"} = conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    if is_nil(origin) or origin_allowed?(origin) do
      conn
      |> WebSockAdapter.upgrade(TunnelSocket, [], timeout: :infinity)
      |> halt()
    else
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end

  def call(%{method: "POST", request_path: "/tunnel/connect"} = conn, _opts) do
    ControlHandler.handle_registration(conn)
    |> halt()
  end

  def call(%{method: "POST", request_path: "/tunnel/response"} = conn, _opts) do
    ControlHandler.handle_response(conn)
    |> halt()
  end

  def call(%{method: "OPTIONS"} = conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn =
      if origin && origin_allowed?(origin) do
        put_resp_header(conn, "access-control-allow-origin", origin)
      else
        conn
      end

    conn
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp origin_allowed?(origin) do
    base_domain = Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"

    allowed = [
      "https://#{base_domain}",
      "http://#{base_domain}",
      "http://localhost:4000"
    ]

    origin in allowed or String.ends_with?(origin, ".#{base_domain}")
  end
end
