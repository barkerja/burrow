defmodule Burrow.Server.Web.Plugs.ApiAuth do
  @moduledoc """
  Plug that authenticates API requests using bearer tokens.

  Expects `Authorization: Bearer brw_...` header.
  """

  import Plug.Conn

  alias Burrow.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, api_token} <- Accounts.verify_api_token(token) do
      conn
      |> assign(:current_user, api_token.user)
      |> assign(:api_token, api_token)
    else
      {:error, :no_token} ->
        conn
        |> send_json_error(401, "missing_token", "Authorization header required")
        |> halt()

      {:error, :invalid_token} ->
        conn
        |> send_json_error(401, "invalid_token", "Invalid API token")
        |> halt()

      {:error, :expired_token} ->
        conn
        |> send_json_error(401, "expired_token", "API token has expired")
        |> halt()
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      ["bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :no_token}
    end
  end

  defp send_json_error(conn, status, code, message) do
    body = Jason.encode!(%{error: %{code: code, message: message}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
  end
end
