defmodule Burrow.Server.Web.Router do
  @moduledoc """
  Router for the request inspector web UI.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  import Oban.Web.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:put_root_layout, html: {Burrow.Server.Web.Layouts, :root})
    plug(:protect_from_forgery)

    plug(:put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; " <>
          "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; " <>
          "style-src 'self' 'unsafe-inline'; " <>
          "img-src 'self' data:; " <>
          "font-src 'self'; " <>
          "connect-src 'self' wss:; " <>
          "frame-ancestors 'none'",
      "strict-transport-security" => "max-age=63072000; includeSubDomains"
    })
  end

  pipeline :auth_required do
    plug(Burrow.Server.Web.Plugs.RequireAuth)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_auth do
    plug(Burrow.Server.Web.Plugs.ApiAuth)
  end

  pipeline :auth_rate_limited do
    plug(Burrow.Server.Web.Plugs.RateLimit, limit: 10, window_ms: 60_000, scope: "auth")
  end

  # Root redirect to inspector
  scope "/", Burrow.Server.Web do
    pipe_through(:browser)

    get("/", PageController, :index)
  end

  # Auth routes (no auth required, rate limited)
  scope "/auth", Burrow.Server.Web do
    pipe_through([:browser, :auth_rate_limited])

    live("/login", AuthLive.Login, :login)
    live("/register", AuthLive.Register, :register)
    post("/session", SessionController, :create)
    post("/logout", SessionController, :logout)
  end

  # Protected inspector routes
  scope "/inspector", Burrow.Server.Web do
    pipe_through([:browser, :auth_required])

    live("/", InspectorLive.Index, :index)
    live("/requests/:id", InspectorLive.Show, :show)
  end

  # Account management (protected)
  scope "/account", Burrow.Server.Web do
    pipe_through([:browser, :auth_required])

    live("/", AccountLive.Index, :index)
  end

  # API routes (token auth)
  scope "/api", Burrow.Server.Web do
    pipe_through([:api, :api_auth])

    get("/subdomains", SubdomainController, :index)
    delete("/subdomains/:subdomain", SubdomainController, :delete)
  end

  # Oban Web dashboard (protected)
  scope "/" do
    pipe_through([:browser, :auth_required])

    oban_dashboard("/oban")
  end
end
