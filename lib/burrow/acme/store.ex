defmodule Burrow.ACME.Store do
  @moduledoc """
  Persistent storage for ACME account and certificates.

  Stores:
  - Account key and registration
  - Domain certificates (cert + key + chain)
  - Certificate metadata (expiry, domains)

  ## Storage Structure

      /var/lib/burrow/acme/
        account.json          # Account key and kid
        certs/
          tunnel.example.com/
            cert.pem          # Certificate
            key.pem           # Private key
            chain.pem         # Full chain
            meta.json         # Metadata (expiry, domains)
  """

  require Logger

  @default_base_dir "/var/lib/burrow/acme"

  @doc """
  Returns the base directory for ACME storage.
  """
  def base_dir do
    Application.get_env(:burrow, :acme, [])[:storage_dir] || @default_base_dir
  end

  @doc """
  Ensures the storage directories exist.
  """
  @spec ensure_dirs() :: :ok | {:error, term()}
  def ensure_dirs do
    base = base_dir()

    with :ok <- File.mkdir_p(base),
         :ok <- File.mkdir_p(Path.join(base, "certs")) do
      :ok
    end
  end

  # Account Storage

  @doc """
  Saves the ACME account.
  """
  @spec save_account(map()) :: :ok | {:error, term()}
  def save_account(account) do
    path = account_path()

    data = %{
      key: account.key,
      kid: account.kid,
      directory_url: account.directory_url
    }

    with :ok <- ensure_dirs(),
         :ok <- File.write(path, Jason.encode!(data, pretty: true)) do
      File.chmod(path, 0o600)
    end
  end

  @doc """
  Loads the ACME account.
  """
  @spec load_account() :: {:ok, map()} | {:error, :not_found | term()}
  def load_account do
    path = account_path()

    case File.read(path) do
      {:ok, content} ->
        data = Jason.decode!(content)

        account = %{
          key: data["key"],
          kid: data["kid"],
          directory_url: data["directory_url"]
        }

        {:ok, account}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp account_path do
    Path.join(base_dir(), "account.json")
  end

  # Certificate Storage

  @doc """
  Saves a certificate with its private key and chain.

  ## Parameters

  - `domain` - Primary domain (used as directory name)
  - `cert_pem` - Certificate PEM string
  - `key_pem` - Private key PEM string
  - `chain_pem` - Full certificate chain PEM string
  - `domains` - List of all domains covered by cert
  """
  @spec save_certificate(String.t(), String.t(), String.t(), String.t(), [String.t()]) ::
          :ok | {:error, term()}
  def save_certificate(domain, cert_pem, key_pem, chain_pem, domains) do
    dir = cert_dir(domain)

    with :ok <- File.mkdir_p(dir),
         :ok <- write_secure(Path.join(dir, "cert.pem"), cert_pem),
         :ok <- write_secure(Path.join(dir, "key.pem"), key_pem),
         :ok <- write_secure(Path.join(dir, "chain.pem"), chain_pem) do
      # Parse certificate to get expiry
      {:ok, cert} = X509.Certificate.from_pem(cert_pem)
      {:Validity, not_before, not_after} = X509.Certificate.validity(cert)

      meta = %{
        domains: domains,
        not_before: format_asn1_time(not_before),
        not_after: format_asn1_time(not_after),
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      File.write(Path.join(dir, "meta.json"), Jason.encode!(meta, pretty: true))
    end
  end

  @doc """
  Loads certificate files for a domain.

  Returns `{:ok, %{cert: path, key: path, chain: path}}` or `{:error, reason}`.
  """
  @spec load_certificate_paths(String.t()) :: {:ok, map()} | {:error, term()}
  def load_certificate_paths(domain) do
    dir = cert_dir(domain)
    cert_path = Path.join(dir, "cert.pem")
    key_path = Path.join(dir, "key.pem")
    chain_path = Path.join(dir, "chain.pem")

    if File.exists?(cert_path) and File.exists?(key_path) do
      {:ok,
       %{
         cert: cert_path,
         key: key_path,
         chain: chain_path,
         certfile: chain_path,
         keyfile: key_path
       }}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Loads certificate metadata for a domain.
  """
  @spec load_certificate_meta(String.t()) :: {:ok, map()} | {:error, term()}
  def load_certificate_meta(domain) do
    path = Path.join(cert_dir(domain), "meta.json")

    case File.read(path) do
      {:ok, content} ->
        {:ok, Jason.decode!(content)}

      {:error, :enoent} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  @doc """
  Checks if a certificate exists and is valid (not expired or expiring soon).

  Returns `true` if certificate exists and has more than `min_days` until expiry.
  """
  @spec certificate_valid?(String.t(), integer()) :: boolean()
  def certificate_valid?(domain, min_days \\ 30) do
    case load_certificate_meta(domain) do
      {:ok, meta} ->
        case DateTime.from_iso8601(meta["not_after"]) do
          {:ok, expiry, _offset} ->
            days_until_expiry = DateTime.diff(expiry, DateTime.utc_now(), :day)
            days_until_expiry > min_days

          _ ->
            false
        end

      _ ->
        false
    end
  end

  @doc """
  Lists all stored certificates.
  """
  @spec list_certificates() :: [{String.t(), map()}]
  def list_certificates do
    certs_dir = Path.join(base_dir(), "certs")

    case File.ls(certs_dir) do
      {:ok, domains} ->
        domains
        |> Enum.map(fn domain ->
          case load_certificate_meta(domain) do
            {:ok, meta} -> {domain, meta}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  @doc """
  Generates a new RSA private key for certificate signing.
  """
  @spec generate_cert_key() :: {binary(), binary()}
  def generate_cert_key do
    key = X509.PrivateKey.new_rsa(2048)
    pem = X509.PrivateKey.to_pem(key)
    {key, pem}
  end

  @doc """
  Generates a CSR (Certificate Signing Request) for the given domains.
  """
  @spec generate_csr(X509.PrivateKey.t(), [String.t()]) :: {binary(), binary()}
  def generate_csr(private_key, domains) do
    [primary | _alt_names] = domains

    csr =
      X509.CSR.new(private_key, "/CN=#{primary}",
        extension_request: [
          X509.Certificate.Extension.subject_alt_name(domains)
        ]
      )

    der = X509.CSR.to_der(csr)
    pem = X509.CSR.to_pem(csr)

    {der, pem}
  end

  # Private Helpers

  defp cert_dir(domain) do
    # Sanitize domain name for filesystem
    safe_domain = String.replace(domain, "*.", "wildcard.")
    Path.join([base_dir(), "certs", safe_domain])
  end

  defp write_secure(path, content) do
    with :ok <- File.write(path, content) do
      File.chmod(path, 0o600)
    end
  end

  defp format_asn1_time({:utcTime, time}) do
    # Format: YYMMDDHHMMSSZ
    <<y1, y2, m1, m2, d1, d2, h1, h2, min1, min2, s1, s2, ?Z>> = IO.iodata_to_binary(time)
    year = String.to_integer(<<y1, y2>>)
    year = if year >= 50, do: 1900 + year, else: 2000 + year

    "#{year}-#{<<m1, m2>>}-#{<<d1, d2>>}T#{<<h1, h2>>}:#{<<min1, min2>>}:#{<<s1, s2>>}Z"
  end

  defp format_asn1_time({:generalTime, time}) do
    # Format: YYYYMMDDHHMMSSZ
    <<y1, y2, y3, y4, m1, m2, d1, d2, h1, h2, min1, min2, s1, s2, ?Z>> =
      IO.iodata_to_binary(time)

    "#{<<y1, y2, y3, y4>>}-#{<<m1, m2>>}-#{<<d1, d2>>}T#{<<h1, h2>>}:#{<<min1, min2>>}:#{<<s1, s2>>}Z"
  end
end
