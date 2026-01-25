defmodule Burrow.Server.Web.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires authentication for protected routes.

  Validates that the session contains a properly authenticated user
  with the new WebAuthn-based auth format (must have `id` field).
  Redirects unauthenticated or old-format sessions to the login page.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :current_user) do
      %{id: _id} = user ->
        conn
        |> assign(:current_user, user)

      _ ->
        conn
        |> clear_session()
        |> redirect(to: "/auth/login")
        |> halt()
    end
  end
end
