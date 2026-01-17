defmodule Burrow.Server.Web.PageController do
  use Phoenix.Controller, formats: [:html]

  alias Burrow.Server.LandingPage

  def index(conn, _params) do
    LandingPage.render(conn)
  end
end
