defmodule Burrow.Server.Supervisor do
  @moduledoc """
  Supervisor for the Burrow server components.

  Starts and manages:
  - TunnelRegistry - Manages subdomain → tunnel mappings
  - PendingRequests - Tracks in-flight requests
  - ACME Supervisor - Certificate management (if TLS enabled)
  - Bandit HTTP/HTTPS server - Handles incoming requests

  ## TLS Configuration

  To enable TLS with automatic Let's Encrypt certificates:

      Burrow.Server.Supervisor.start_link(
        port: 443,
        tls: true,
        acme: [
          email: "admin@example.com",
          domains: ["tunnel.example.com", "*.tunnel.example.com"],
          directory_url: :production,  # or :staging for testing
          dns_provider: :cloudflare,
          cloudflare_api_token: "...",
          cloudflare_zone_id: "..."
        ]
      )

  Or with pre-existing certificates:

      Burrow.Server.Supervisor.start_link(
        port: 443,
        tls: true,
        certfile: "/path/to/cert.pem",
        keyfile: "/path/to/key.pem"
      )
  """

  use Supervisor

  require Logger

  @doc """
  Starts the server supervisor.

  ## Options

  - `:port` - Port to listen on (default: 4000)
  - `:tls` - Enable TLS (default: false)
  - `:certfile` - Path to certificate file (for manual TLS)
  - `:keyfile` - Path to private key file (for manual TLS)
  - `:acme` - ACME/Let's Encrypt options (for automatic TLS)
  - `:http_port` - Port for HTTP (ACME challenges) when TLS enabled (default: 80)
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 4000)
    tls_enabled = Keyword.get(opts, :tls, false)

    # Allow custom names for testing
    registry_name = Keyword.get(opts, :registry_name, Burrow.Server.TunnelRegistry)
    pending_name = Keyword.get(opts, :pending_name, Burrow.Server.PendingRequests)

    children = [
      # PubSub for real-time updates
      {Phoenix.PubSub, name: Burrow.PubSub},
      # State management
      {Burrow.Server.TunnelRegistry, name: registry_name},
      {Burrow.Server.PendingRequests, name: pending_name},
      Burrow.Server.WSRegistry,
      Burrow.Server.TCPRegistry,
      # Request inspector storage and IP lookup
      Burrow.Server.IPLookup,
      Burrow.Server.RequestStore,
      # Request inspector Phoenix endpoint (no separate server, plugged into main endpoint)
      Burrow.Server.Web.Endpoint
    ]

    # Add ACME supervisor and server(s) based on TLS config
    children =
      if tls_enabled do
        children ++ tls_children(port, opts)
      else
        children ++ [{Bandit, plug: Burrow.Server.Dispatcher, port: port, scheme: :http}]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp tls_children(https_port, opts) do
    acme_opts = Keyword.get(opts, :acme)
    http_port = Keyword.get(opts, :http_port, 80)

    children = []

    # Add ACME supervisor if configured
    {children, tls_opts} =
      cond do
        # ACME automatic certificates
        acme_opts != nil ->
          acme_children = [
            {Burrow.ACME.Supervisor,
             Keyword.merge(acme_opts,
               on_renewal: &handle_certificate_renewal/1
             )}
          ]

          # Try to get existing certificate or issue new one
          cert_paths = ensure_acme_certificate(acme_opts)

          tls_opts =
            if cert_paths do
              [
                scheme: :https,
                certfile: cert_paths.certfile,
                keyfile: cert_paths.keyfile
              ]
            else
              Logger.warning("No certificate available yet, starting HTTP only")
              [scheme: :http]
            end

          {children ++ acme_children, tls_opts}

        # Manual certificate paths
        opts[:certfile] && opts[:keyfile] ->
          tls_opts = [
            scheme: :https,
            certfile: opts[:certfile],
            keyfile: opts[:keyfile]
          ]

          {children, tls_opts}

        # TLS enabled but no certs configured
        true ->
          Logger.warning("TLS enabled but no certificates configured, starting HTTP")
          {children, [scheme: :http]}
      end

    # Add HTTP server for ACME challenges (always on port 80 when TLS enabled)
    children =
      if acme_opts != nil and http_port != https_port do
        children ++
          [
            {Bandit,
             plug: Burrow.Server.Dispatcher,
             port: http_port,
             scheme: :http,
             thousand_island_options: [supervisor_options: [id: :http_server]]}
          ]
      else
        children
      end

    # Add main HTTPS server
    bandit_opts =
      [plug: Burrow.Server.Dispatcher, port: https_port] ++ tls_opts

    children ++ [{Bandit, bandit_opts}]
  end

  defp ensure_acme_certificate(acme_opts) do
    domains = Keyword.fetch!(acme_opts, :domains)
    [primary | _] = domains

    case Burrow.ACME.Store.load_certificate_paths(primary) do
      {:ok, paths} ->
        if Burrow.ACME.Store.certificate_valid?(primary, 7) do
          Logger.info("Using existing certificate for #{primary}")
          paths
        else
          Logger.info("Certificate expired or expiring soon, will renew")
          nil
        end

      {:error, :not_found} ->
        Logger.info("No certificate found for #{primary}, will issue on startup")
        # The renewal worker will handle initial issuance
        nil
    end
  end

  defp handle_certificate_renewal(cert_paths) do
    Logger.info("Certificate renewed, TLS will use new cert on next connection")
    # Bandit doesn't support hot-reload of certs, but new connections
    # will use the new files. For truly zero-downtime, we'd need to
    # implement cert reload via :ssl.ssl_accept options.
    # For now, this is sufficient for most use cases.
    cert_paths
  end
end
