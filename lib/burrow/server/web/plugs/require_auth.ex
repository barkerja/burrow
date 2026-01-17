defmodule Burrow.Server.Web.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires authentication for the request inspector.

  Redirects unauthenticated users to the login page.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :current_user) do
      nil ->
        conn
        |> redirect(to: "/inspector/login")
        |> halt()

      _user ->
        conn
    end
  end
end
