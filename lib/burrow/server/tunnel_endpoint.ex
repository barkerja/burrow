defmodule Burrow.Server.TunnelEndpoint do
  @moduledoc """
  Endpoint for tunnel subdomains.

  Handles all requests to subdomains (e.g., myapp.barkerja.dev) by
  forwarding them through the appropriate tunnel to the connected client.
  """

  use Plug.Router

  alias Burrow.Server.{RequestForwarder, ErrorPage}

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  # CORS preflight for tunnel requests
  options _ do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type, authorization")
    |> send_resp(200, "")
  end

  # All requests get forwarded through the tunnel
  match _ do
    case extract_subdomain(conn) do
      {:ok, subdomain} ->
        RequestForwarder.forward(conn, subdomain)

      :error ->
        ErrorPage.render(conn, 404)
    end
  end

  @doc """
  Extracts subdomain from the connection's host header.

  ## Examples

      iex> conn = %{host: "myapp.burrow.example.com"}
      iex> TunnelEndpoint.extract_subdomain(conn)
      {:ok, "myapp"}

      iex> conn = %{host: "burrow.example.com"}
      iex> TunnelEndpoint.extract_subdomain(conn)
      :error
  """
  @spec extract_subdomain(Plug.Conn.t()) :: {:ok, String.t()} | :error
  def extract_subdomain(conn) do
    host = conn.host
    base_domain = get_base_domain()
    suffix = "." <> base_domain

    cond do
      host == base_domain ->
        :error

      String.ends_with?(host, suffix) ->
        subdomain = String.replace_suffix(host, suffix, "")
        if subdomain != "", do: {:ok, subdomain}, else: :error

      true ->
        :error
    end
  end

  defp get_base_domain do
    Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
  end
end
