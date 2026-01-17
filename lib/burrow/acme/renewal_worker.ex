defmodule Burrow.ACME.RenewalWorker do
  @moduledoc """
  Background worker for automatic certificate renewal.

  Periodically checks certificate expiry and renews certificates
  that will expire within 30 days.

  ## Usage

      # Start as part of supervision tree
      children = [
        {Burrow.ACME.RenewalWorker, [
          domains: ["tunnel.example.com", "*.tunnel.example.com"],
          email: "admin@example.com",
          dns_provider: :cloudflare,
          cloudflare_api_token: "...",
          cloudflare_zone_id: "...",
          check_interval: :timer.hours(12),
          on_renewal: fn cert_paths -> reload_tls(cert_paths) end
        ]}
      ]
  """

  use GenServer

  require Logger

  alias Burrow.ACME.{CertificateManager, Store}

  @default_check_interval :timer.hours(12)
  @renewal_threshold_days 30

  defstruct [
    :domains,
    :email,
    :directory_url,
    :dns_provider,
    :cloudflare_api_token,
    :cloudflare_zone_id,
    :check_interval,
    :on_renewal,
    :timer_ref
  ]

  @doc """
  Starts the renewal worker.

  ## Options

  - `:domains` - List of domains (required)
  - `:email` - Contact email (required)
  - `:directory_url` - ACME directory (default: :production)
  - `:dns_provider` - DNS provider for wildcard certs
  - `:cloudflare_api_token` - Cloudflare API token
  - `:cloudflare_zone_id` - Cloudflare zone ID
  - `:check_interval` - How often to check (default: 12 hours)
  - `:on_renewal` - Callback function when certificate is renewed
  - `:name` - Process name (optional)
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Forces an immediate certificate check and renewal if needed.
  """
  def check_now(server \\ __MODULE__) do
    GenServer.call(server, :check_now, :timer.minutes(10))
  end

  @doc """
  Returns the current certificate status.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  # Callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      domains: Keyword.fetch!(opts, :domains),
      email: Keyword.fetch!(opts, :email),
      directory_url: Keyword.get(opts, :directory_url, :production),
      dns_provider: Keyword.get(opts, :dns_provider),
      cloudflare_api_token: Keyword.get(opts, :cloudflare_api_token),
      cloudflare_zone_id: Keyword.get(opts, :cloudflare_zone_id),
      check_interval: Keyword.get(opts, :check_interval, @default_check_interval),
      on_renewal: Keyword.get(opts, :on_renewal)
    }

    # Schedule first check after a short delay
    send(self(), :check_certificate)

    {:ok, state}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    result = do_check_and_renew(state)
    {:reply, result, state}
  end

  def handle_call(:status, _from, state) do
    [primary | _] = state.domains

    status =
      case Store.load_certificate_meta(primary) do
        {:ok, meta} ->
          %{
            domains: meta["domains"],
            expires: meta["not_after"],
            valid: Store.certificate_valid?(primary, @renewal_threshold_days)
          }

        {:error, :not_found} ->
          %{
            domains: state.domains,
            expires: nil,
            valid: false
          }
      end

    {:reply, status, state}
  end

  @impl true
  def handle_info(:check_certificate, state) do
    do_check_and_renew(state)
    timer_ref = schedule_check(state.check_interval)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  # Private Functions

  defp do_check_and_renew(state) do
    [primary | _] = state.domains

    if Store.certificate_valid?(primary, @renewal_threshold_days) do
      Logger.debug("Certificate for #{primary} is valid, no renewal needed")
      {:ok, :valid}
    else
      Logger.info("Certificate for #{primary} needs renewal")
      renew_certificate(state)
    end
  end

  defp renew_certificate(state) do
    opts = [
      domains: state.domains,
      email: state.email,
      directory_url: state.directory_url,
      force_renew: true
    ]

    opts =
      if state.dns_provider do
        opts
        |> Keyword.put(:dns_provider, state.dns_provider)
        |> Keyword.put(:cloudflare_api_token, state.cloudflare_api_token)
        |> Keyword.put(:cloudflare_zone_id, state.cloudflare_zone_id)
      else
        opts
      end

    case CertificateManager.issue_certificate(opts) do
      {:ok, cert_paths} ->
        Logger.info("Certificate renewed successfully")

        # Call renewal callback if provided
        if state.on_renewal do
          state.on_renewal.(cert_paths)
        end

        {:ok, :renewed}

      {:error, reason} = error ->
        Logger.error("Certificate renewal failed: #{inspect(reason)}")
        error
    end
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_certificate, interval)
  end
end
