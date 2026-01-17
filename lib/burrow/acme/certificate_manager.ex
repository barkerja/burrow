defmodule Burrow.ACME.CertificateManager do
  @moduledoc """
  High-level certificate management for Burrow.

  Handles:
  - Account creation/loading
  - Certificate issuance (HTTP-01 and DNS-01)
  - Certificate renewal
  - Certificate loading for Bandit

  ## Usage

      # Get or issue a certificate
      {:ok, cert_paths} = CertificateManager.ensure_certificate(
        domains: ["tunnel.example.com", "*.tunnel.example.com"],
        email: "admin@example.com",
        dns_provider: :cloudflare,
        cloudflare_api_token: "...",
        cloudflare_zone_id: "..."
      )

      # Use with Bandit
      Bandit.start_link(
        plug: MyApp.Endpoint,
        scheme: :https,
        certfile: cert_paths.certfile,
        keyfile: cert_paths.keyfile
      )
  """

  require Logger

  alias Burrow.ACME.{Client, Store}
  alias Burrow.ACME.Challenge.{HTTP01, DNS01}

  @doc """
  Ensures a valid certificate exists for the given domains.

  If a valid certificate exists (not expiring within 30 days), returns it.
  Otherwise, issues a new certificate.

  ## Options

  - `:domains` - List of domains (required)
  - `:email` - Contact email for Let's Encrypt (required)
  - `:directory_url` - ACME directory (default: :staging)
  - `:dns_provider` - DNS provider for wildcard certs (:cloudflare)
  - `:cloudflare_api_token` - Cloudflare API token
  - `:cloudflare_zone_id` - Cloudflare zone ID
  - `:force_renew` - Force renewal even if cert is valid (default: false)
  """
  @spec ensure_certificate(keyword()) :: {:ok, map()} | {:error, term()}
  def ensure_certificate(opts) do
    domains = Keyword.fetch!(opts, :domains)
    [primary_domain | _] = domains
    force_renew = Keyword.get(opts, :force_renew, false)

    if not force_renew and Store.certificate_valid?(primary_domain) do
      Logger.info("Using existing valid certificate for #{primary_domain}")
      Store.load_certificate_paths(primary_domain)
    else
      Logger.info("Issuing new certificate for #{inspect(domains)}")
      issue_certificate(opts)
    end
  end

  @doc """
  Issues a new certificate for the given domains.
  """
  @spec issue_certificate(keyword()) :: {:ok, map()} | {:error, term()}
  def issue_certificate(opts) do
    domains = Keyword.fetch!(opts, :domains)
    email = Keyword.fetch!(opts, :email)
    directory_url = Keyword.get(opts, :directory_url, :staging)
    [primary_domain | _] = domains

    Logger.info("Starting certificate issuance for #{inspect(domains)}")

    with {:ok, account} <- get_or_create_account(email, directory_url),
         {:ok, order} <- Client.new_order(account, domains),
         :ok <- complete_authorizations(account, order, opts),
         {:ok, cert_pem, key_pem} <- finalize_and_download(account, order, domains) do
      # Save certificate
      :ok = Store.save_certificate(primary_domain, cert_pem, key_pem, cert_pem, domains)

      Logger.info("Certificate issued successfully for #{primary_domain}")
      Store.load_certificate_paths(primary_domain)
    end
  end

  @doc """
  Gets or creates an ACME account.
  """
  @spec get_or_create_account(String.t(), atom() | String.t()) ::
          {:ok, map()} | {:error, term()}
  def get_or_create_account(email, directory_url) do
    case Store.load_account() do
      {:ok, saved_account} ->
        # Refresh directory and verify account
        Logger.info("Using existing ACME account")

        Client.get_or_create_account(
          email: email,
          directory_url: directory_url,
          key: saved_account.key
        )

      {:error, :not_found} ->
        Logger.info("Creating new ACME account for #{email}")

        case Client.get_or_create_account(email: email, directory_url: directory_url) do
          {:ok, account} = result ->
            :ok = Store.save_account(account)
            result

          error ->
            error
        end
    end
  end

  # Private Functions

  defp complete_authorizations(account, order, opts) do
    order.authorizations
    |> Enum.reduce_while(:ok, fn auth_url, :ok ->
      case complete_authorization(account, auth_url, opts) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp complete_authorization(account, auth_url, opts) do
    with {:ok, auth} <- Client.get_authorization(account, auth_url) do
      if auth.status == "valid" do
        Logger.debug("Authorization already valid for #{inspect(auth.identifier)}")
        :ok
      else
        complete_challenge(account, auth, opts)
      end
    end
  end

  defp complete_challenge(account, auth, opts) do
    domain = auth.identifier["value"]
    is_wildcard = auth.wildcard

    # Choose challenge type based on domain
    challenge =
      if is_wildcard do
        # Wildcard requires DNS-01
        Enum.find(auth.challenges, &(&1.type == "dns-01"))
      else
        # Prefer HTTP-01 for non-wildcard
        Enum.find(auth.challenges, &(&1.type == "http-01")) ||
          Enum.find(auth.challenges, &(&1.type == "dns-01"))
      end

    if is_nil(challenge) do
      {:error, {:no_suitable_challenge, domain}}
    else
      Logger.info("Using #{challenge.type} challenge for #{domain}")
      do_challenge(account, domain, challenge, opts)
    end
  end

  defp do_challenge(account, _domain, %{type: "http-01"} = challenge, _opts) do
    token = challenge.token
    key_auth = Client.key_authorization(account, token)

    # Register challenge response
    HTTP01.register_challenge(token, key_auth)

    try do
      # Tell ACME server we're ready
      with {:ok, _} <- Client.respond_to_challenge(account, challenge.url),
           # Wait for validation
           {:ok, _} <- Client.poll_status(account, challenge.url) do
        :ok
      end
    after
      HTTP01.remove_challenge(token)
    end
  end

  defp do_challenge(account, domain, %{type: "dns-01"} = challenge, opts) do
    token = challenge.token
    challenge_value = Client.dns_challenge_value(account, token)

    dns_opts = [
      provider: Keyword.fetch!(opts, :dns_provider),
      api_token: Keyword.fetch!(opts, :cloudflare_api_token),
      zone_id: Keyword.fetch!(opts, :cloudflare_zone_id)
    ]

    # Create DNS record
    with {:ok, record_id} <- DNS01.create_challenge(domain, challenge_value, dns_opts),
         # Wait for propagation
         :ok <- DNS01.wait_for_propagation(domain, challenge_value),
         # Tell ACME server we're ready
         {:ok, _} <- Client.respond_to_challenge(account, challenge.url),
         # Wait for validation
         {:ok, _} <- Client.poll_status(account, challenge.url) do
      # Clean up DNS record
      DNS01.delete_challenge(record_id, dns_opts)
      :ok
    else
      error ->
        # Try to clean up on error
        Logger.error("DNS-01 challenge failed: #{inspect(error)}")
        error
    end
  end

  defp finalize_and_download(account, order, domains) do
    # Generate certificate key and CSR
    {private_key, key_pem} = Store.generate_cert_key()
    {csr_der, _csr_pem} = Store.generate_csr(private_key, domains)

    with {:ok, _finalized} <- Client.finalize_order(account, order.finalize, csr_der),
         # Poll until certificate is ready
         {:ok, completed_order} <- Client.poll_status(account, order.url),
         # Download certificate
         {:ok, cert_pem} <- Client.download_certificate(account, completed_order["certificate"]) do
      {:ok, cert_pem, key_pem}
    end
  end
end
