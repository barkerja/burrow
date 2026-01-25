defmodule Burrow.Server.Web.SubdomainController do
  @moduledoc """
  API controller for subdomain management.

  Requires token-based authentication via the ApiAuth plug.
  """

  use Phoenix.Controller, formats: [:json]

  alias Burrow.Accounts

  @doc """
  Lists all subdomain reservations for the current user.

  GET /api/subdomains
  """
  def index(conn, _params) do
    user = conn.assigns.current_user
    reservations = Accounts.list_reservations(user.id)

    json(conn, %{
      subdomains:
        Enum.map(reservations, fn r ->
          %{
            subdomain: r.subdomain,
            created_at: r.inserted_at
          }
        end)
    })
  end

  @doc """
  Releases a subdomain reservation.

  DELETE /api/subdomains/:subdomain
  """
  def delete(conn, %{"subdomain" => subdomain}) do
    user = conn.assigns.current_user

    case Accounts.release_subdomain(user.id, subdomain) do
      {:ok, _} ->
        json(conn, %{ok: true, message: "Subdomain released"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: %{code: "not_found", message: "Subdomain not found"}})

      {:error, :not_owner} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: %{code: "forbidden", message: "You don't own this subdomain"}})
    end
  end
end
