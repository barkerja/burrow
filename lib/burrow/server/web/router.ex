defmodule Burrow.Server.Web.Router do
  @moduledoc """
  Router for the request inspector web UI.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, html: {Burrow.Server.Web.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :auth_required do
    plug Burrow.Server.Web.Plugs.RequireAuth
  end

  # Root redirect to inspector
  scope "/", Burrow.Server.Web do
    pipe_through :browser

    get "/", PageController, :index
  end

  # Auth routes (no auth required)
  scope "/auth", Burrow.Server.Web do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/logout", AuthController, :logout
  end

  # Public inspector routes (login page, unauthorized)
  scope "/inspector", Burrow.Server.Web do
    pipe_through :browser

    live "/login", InspectorLive.Login, :login
    live "/unauthorized", InspectorLive.Unauthorized, :unauthorized
  end

  # Protected inspector routes
  scope "/inspector", Burrow.Server.Web do
    pipe_through [:browser, :auth_required]

    live "/", InspectorLive.Index, :index
    live "/requests/:id", InspectorLive.Show, :show
  end
end
