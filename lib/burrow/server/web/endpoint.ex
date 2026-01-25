defmodule Burrow.Server.Web.Endpoint do
  @moduledoc """
  Phoenix Endpoint for the main domain.

  Handles:
  - Request inspector web UI (LiveView)
  - WebAuthn (passkey) authentication
  - Static assets (images, etc.)
  - Tunnel control API (/health, /tunnel/ws, /tunnel/connect, /tunnel/response)
  - ACME HTTP-01 challenges (Let's Encrypt)
  """

  use Phoenix.Endpoint, otp_app: :burrow

  @session_options [
    store: :cookie,
    key: "_burrow_inspector",
    signing_salt: "burrow_inspector_salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  # ACME HTTP-01 challenge must be first
  plug(Burrow.ACME.Challenge.HTTP01)

  # Tunnel control API (health, WebSocket, HTTP fallback)
  plug(Burrow.Server.Web.Plugs.TunnelControl)

  plug(Plug.Static,
    at: "/",
    from: {:burrow, "priv/static"},
    gzip: false,
    only: ~w(assets images)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)

  plug(Burrow.Server.Web.Router)
end
