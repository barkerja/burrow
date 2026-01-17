defmodule Burrow.ACME.Supervisor do
  @moduledoc """
  Supervisor for ACME certificate management.

  Manages:
  - HTTP-01 challenge response agent
  - Certificate renewal worker (optional)

  ## Usage

      # Start with renewal worker
      {:ok, _} = Burrow.ACME.Supervisor.start_link(
        domains: ["tunnel.example.com", "*.tunnel.example.com"],
        email: "admin@example.com",
        dns_provider: :cloudflare,
        cloudflare_api_token: "...",
        cloudflare_zone_id: "...",
        on_renewal: fn paths -> reload_tls(paths) end
      )

      # Start without renewal (for initial cert only)
      {:ok, _} = Burrow.ACME.Supervisor.start_link([])
  """

  use Supervisor

  alias Burrow.ACME.{Challenge.HTTP01, RenewalWorker}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      # HTTP-01 challenge response store
      {HTTP01, []}
    ]

    # Add renewal worker if domains are configured
    children =
      if opts[:domains] do
        renewal_opts = [
          domains: opts[:domains],
          email: opts[:email],
          directory_url: opts[:directory_url] || :production,
          dns_provider: opts[:dns_provider],
          cloudflare_api_token: opts[:cloudflare_api_token],
          cloudflare_zone_id: opts[:cloudflare_zone_id],
          check_interval: opts[:check_interval] || :timer.hours(12),
          on_renewal: opts[:on_renewal],
          name: RenewalWorker
        ]

        children ++ [{RenewalWorker, renewal_opts}]
      else
        children
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
