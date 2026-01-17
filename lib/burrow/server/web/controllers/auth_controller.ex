defmodule Burrow.Server.Web.AuthController do
  @moduledoc """
  Handles GitHub OAuth authentication for the request inspector.
  """

  use Phoenix.Controller, formats: [:html]

  plug Ueberauth

  require Logger

  def request(conn, _params) do
    # Ueberauth handles the redirect to GitHub
    conn
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_info = %{
      username: auth.info.nickname,
      name: auth.info.name,
      email: auth.info.email,
      avatar_url: auth.info.image,
      access_token: auth.credentials.token
    }

    # Check if user is authorized
    case authorize_user(user_info) do
      :ok ->
        Logger.info("[Auth] User #{user_info.username} authenticated successfully")

        conn
        |> put_session(:current_user, user_info)
        |> put_flash(:info, "Welcome, #{user_info.name || user_info.username}!")
        |> redirect(to: "/inspector")

      {:error, reason} ->
        Logger.warning("[Auth] User #{user_info.username} denied access: #{reason}")

        conn
        |> put_flash(:error, "Access denied: #{reason}")
        |> redirect(to: "/inspector/unauthorized")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.error("[Auth] Authentication failed: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: "/inspector/login")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: "/inspector/login")
  end

  # Private functions

  defp authorize_user(user_info) do
    config = Application.get_env(:burrow, :inspector_auth, [])
    allowed_users = Keyword.get(config, :allowed_users, [])
    allowed_orgs = Keyword.get(config, :allowed_orgs, [])

    cond do
      # Check if user is in allowed users list
      user_info.username in allowed_users ->
        :ok

      # Check organization membership
      allowed_orgs != [] ->
        check_org_membership(user_info, allowed_orgs)

      # No restrictions configured - allow all authenticated users
      allowed_users == [] and allowed_orgs == [] ->
        :ok

      true ->
        {:error, "You are not authorized to access the inspector"}
    end
  end

  defp check_org_membership(user_info, allowed_orgs) do
    case fetch_user_orgs(user_info.access_token) do
      {:ok, user_orgs} ->
        user_org_logins = Enum.map(user_orgs, & &1["login"])

        if Enum.any?(allowed_orgs, &(&1 in user_org_logins)) do
          :ok
        else
          {:error, "You are not a member of an authorized organization"}
        end

      {:error, reason} ->
        Logger.error("[Auth] Failed to fetch orgs: #{inspect(reason)}")
        {:error, "Could not verify organization membership"}
    end
  end

  defp fetch_user_orgs(access_token) do
    url = "https://api.github.com/user/orgs"

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"User-Agent", "Burrow-Inspector"}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, {{_, status, _}, _headers, body}} ->
        {:error, "GitHub API returned #{status}: #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
