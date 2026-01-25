defmodule Burrow.Server.Web.SessionController do
  @moduledoc """
  Handles session management for WebAuthn authentication.
  """

  use Phoenix.Controller, formats: [:html, :json]

  alias Burrow.Accounts

  require Logger

  @doc """
  Creates a session for a user after successful WebAuthn authentication.

  Called via JavaScript after WebAuthn verification succeeds.
  """
  def create(conn, %{"user_id" => user_id}) do
    case Accounts.get_user(user_id) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "User not found"})

      user ->
        user_info = %{
          id: user.id,
          username: user.username,
          display_name: user.display_name
        }

        Logger.info("[Auth] User #{user.username} authenticated successfully")

        conn
        |> put_session(:current_user, user_info)
        |> json(%{ok: true, redirect: "/inspector"})
    end
  end

  @doc """
  Logs out the current user.
  """
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/auth/login")
  end
end
