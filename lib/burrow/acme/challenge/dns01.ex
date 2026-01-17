defmodule Burrow.ACME.Challenge.DNS01 do
  @moduledoc """
  DNS-01 ACME challenge handler.

  Creates and cleans up DNS TXT records for domain validation.
  Required for wildcard certificates.

  ## Supported Providers

  - `:cloudflare` - Cloudflare DNS API

  ## Usage

      # Set DNS TXT record
      {:ok, record_id} = DNS01.create_challenge(
        "example.com",
        "challenge-value",
        provider: :cloudflare,
        api_token: "your-token",
        zone_id: "your-zone-id"
      )

      # After validation, clean up
      :ok = DNS01.delete_challenge(record_id,
        provider: :cloudflare,
        api_token: "your-token",
        zone_id: "your-zone-id"
      )
  """

  require Logger

  @acme_challenge_prefix "_acme-challenge"

  @doc """
  Creates a DNS TXT record for the ACME challenge.

  ## Options

  - `:provider` - DNS provider (`:cloudflare`)
  - `:api_token` - Provider API token
  - `:zone_id` - DNS zone ID

  Returns `{:ok, record_id}` for later cleanup.
  """
  @spec create_challenge(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def create_challenge(domain, challenge_value, opts) do
    provider = Keyword.fetch!(opts, :provider)
    record_name = challenge_record_name(domain)

    Logger.info("Creating DNS-01 challenge for #{domain} at #{record_name}")

    case provider do
      :cloudflare ->
        Burrow.ACME.DNS.Cloudflare.create_txt_record(
          record_name,
          challenge_value,
          opts
        )

      other ->
        {:error, {:unsupported_provider, other}}
    end
  end

  @doc """
  Deletes a DNS TXT record after challenge validation.
  """
  @spec delete_challenge(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_challenge(record_id, opts) do
    provider = Keyword.fetch!(opts, :provider)

    Logger.info("Deleting DNS-01 challenge record #{record_id}")

    case provider do
      :cloudflare ->
        Burrow.ACME.DNS.Cloudflare.delete_txt_record(record_id, opts)

      other ->
        {:error, {:unsupported_provider, other}}
    end
  end

  @doc """
  Waits for DNS propagation by querying public DNS servers.
  """
  @spec wait_for_propagation(String.t(), String.t(), keyword()) ::
          :ok | {:error, :timeout}
  def wait_for_propagation(domain, expected_value, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 60)
    delay_ms = Keyword.get(opts, :delay_ms, 5000)
    record_name = challenge_record_name(domain)

    Logger.info("Waiting for DNS propagation of #{record_name}...")

    do_wait_propagation(record_name, expected_value, max_attempts, delay_ms)
  end

  defp do_wait_propagation(_record_name, _expected, 0, _delay) do
    {:error, :timeout}
  end

  defp do_wait_propagation(record_name, expected, attempts, delay) do
    case query_txt_record(record_name) do
      {:ok, values} when is_list(values) ->
        if expected in values do
          Logger.info("DNS propagation complete for #{record_name}")
          :ok
        else
          Process.sleep(delay)
          do_wait_propagation(record_name, expected, attempts - 1, delay)
        end

      _ ->
        Process.sleep(delay)
        do_wait_propagation(record_name, expected, attempts - 1, delay)
    end
  end

  defp query_txt_record(name) do
    # Use Erlang's inet_res to query DNS
    name_charlist = String.to_charlist(name)

    case :inet_res.lookup(name_charlist, :in, :txt) do
      [] ->
        {:ok, []}

      records ->
        values =
          records
          |> Enum.map(fn parts ->
            parts |> Enum.join() |> to_string()
          end)

        {:ok, values}
    end
  rescue
    _ -> {:error, :dns_query_failed}
  end

  defp challenge_record_name(domain) do
    # For wildcard domains like *.example.com, use _acme-challenge.example.com
    # For regular domains like sub.example.com, use _acme-challenge.sub.example.com
    clean_domain = String.replace_prefix(domain, "*.", "")
    "#{@acme_challenge_prefix}.#{clean_domain}"
  end
end
