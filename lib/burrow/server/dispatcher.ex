defmodule Burrow.Server.Dispatcher do
  @moduledoc """
  Routes incoming requests based on hostname.

  - Main domain (e.g., barkerja.dev) → Web.Endpoint (inspector, auth, static assets)
  - Subdomains (e.g., myapp.barkerja.dev) → TunnelEndpoint (forwarding to tunnels)
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    base_domain = get_base_domain()

    if main_domain?(conn.host, base_domain) do
      Burrow.Server.Web.Endpoint.call(conn, [])
    else
      Burrow.Server.TunnelEndpoint.call(conn, [])
    end
  end

  defp main_domain?(host, base_domain) do
    host == base_domain or host == "localhost" or is_ip_address?(host)
  end

  defp is_ip_address?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp get_base_domain do
    Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
  end
end
