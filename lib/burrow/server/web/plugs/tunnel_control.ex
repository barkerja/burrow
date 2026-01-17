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
    conn
    |> WebSockAdapter.upgrade(TunnelSocket, [], timeout: :infinity)
    |> halt()
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
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> send_resp(200, "")
    |> halt()
  end

  def call(conn, _opts), do: conn
end
