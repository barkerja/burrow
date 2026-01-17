defmodule Burrow.ACME.DNS.Cloudflare do
  @moduledoc """
  Cloudflare DNS API client for ACME DNS-01 challenges.

  ## Configuration

  Requires a Cloudflare API token with DNS edit permissions:
  - Zone:DNS:Edit

  ## Usage

      # Create a TXT record
      {:ok, record_id} = Cloudflare.create_txt_record(
        "_acme-challenge.example.com",
        "challenge-value",
        api_token: "your-token",
        zone_id: "your-zone-id"
      )

      # Delete the record
      :ok = Cloudflare.delete_txt_record(record_id,
        api_token: "your-token",
        zone_id: "your-zone-id"
      )

  ## Getting Zone ID

  You can find your zone ID in the Cloudflare dashboard, or query it:

      {:ok, zone_id} = Cloudflare.get_zone_id("example.com",
        api_token: "your-token"
      )
  """

  require Logger

  @api_base "https://api.cloudflare.com/client/v4"

  @doc """
  Creates a TXT record in Cloudflare DNS.

  Returns `{:ok, record_id}` on success.
  """
  @spec create_txt_record(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def create_txt_record(name, content, opts) do
    api_token = Keyword.fetch!(opts, :api_token)
    zone_id = Keyword.fetch!(opts, :zone_id)
    ttl = Keyword.get(opts, :ttl, 120)

    url = "#{@api_base}/zones/#{zone_id}/dns_records"

    body =
      Jason.encode!(%{
        type: "TXT",
        name: name,
        content: content,
        ttl: ttl
      })

    case http_post(url, body, api_token) do
      {:ok, %{"success" => true, "result" => %{"id" => id}}} ->
        Logger.debug("Created Cloudflare TXT record: #{id}")
        {:ok, id}

      {:ok, %{"success" => false, "errors" => errors}} ->
        {:error, {:cloudflare_error, errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a DNS record by ID.
  """
  @spec delete_txt_record(String.t(), keyword()) :: :ok | {:error, term()}
  def delete_txt_record(record_id, opts) do
    api_token = Keyword.fetch!(opts, :api_token)
    zone_id = Keyword.fetch!(opts, :zone_id)

    url = "#{@api_base}/zones/#{zone_id}/dns_records/#{record_id}"

    case http_delete(url, api_token) do
      {:ok, %{"success" => true}} ->
        Logger.debug("Deleted Cloudflare TXT record: #{record_id}")
        :ok

      {:ok, %{"success" => false, "errors" => errors}} ->
        {:error, {:cloudflare_error, errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the zone ID for a domain.
  """
  @spec get_zone_id(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_zone_id(domain, opts) do
    api_token = Keyword.fetch!(opts, :api_token)

    # Extract root domain from subdomain
    root_domain = extract_root_domain(domain)
    url = "#{@api_base}/zones?name=#{root_domain}"

    case http_get(url, api_token) do
      {:ok, %{"success" => true, "result" => [%{"id" => id} | _]}} ->
        {:ok, id}

      {:ok, %{"success" => true, "result" => []}} ->
        {:error, :zone_not_found}

      {:ok, %{"success" => false, "errors" => errors}} ->
        {:error, {:cloudflare_error, errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists TXT records for a name.
  """
  @spec list_txt_records(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_txt_records(name, opts) do
    api_token = Keyword.fetch!(opts, :api_token)
    zone_id = Keyword.fetch!(opts, :zone_id)

    url = "#{@api_base}/zones/#{zone_id}/dns_records?type=TXT&name=#{name}"

    case http_get(url, api_token) do
      {:ok, %{"success" => true, "result" => records}} ->
        {:ok, records}

      {:ok, %{"success" => false, "errors" => errors}} ->
        {:error, {:cloudflare_error, errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private HTTP helpers

  defp http_get(url, api_token) do
    headers = [
      {"authorization", "Bearer #{api_token}"},
      {"content-type", "application/json"}
    ]

    uri = URI.parse(url)

    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, 443, []),
         path = if(uri.query, do: "#{uri.path}?#{uri.query}", else: uri.path),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "GET", path, headers, nil),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)
      {:ok, Jason.decode!(response.body)}
    end
  end

  defp http_post(url, body, api_token) do
    headers = [
      {"authorization", "Bearer #{api_token}"},
      {"content-type", "application/json"},
      {"content-length", Integer.to_string(byte_size(body))}
    ]

    uri = URI.parse(url)

    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, 443, []),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "POST", uri.path, headers, body),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)
      {:ok, Jason.decode!(response.body)}
    end
  end

  defp http_delete(url, api_token) do
    headers = [
      {"authorization", "Bearer #{api_token}"},
      {"content-type", "application/json"}
    ]

    uri = URI.parse(url)

    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, 443, []),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "DELETE", uri.path, headers, nil),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)
      {:ok, Jason.decode!(response.body)}
    end
  end

  defp receive_response(conn, ref) do
    receive_response_loop(conn, ref, %{status: nil, headers: [], body: [], done: false})
  end

  defp receive_response_loop(_conn, _ref, %{done: true} = response) do
    body = response.body |> Enum.reverse() |> IO.iodata_to_binary()
    {:ok, %{status: response.status, headers: response.headers, body: body}}
  end

  defp receive_response_loop(conn, ref, response) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          :unknown ->
            receive_response_loop(conn, ref, response)

          {:ok, conn, responses} ->
            response = process_responses(responses, ref, response)
            receive_response_loop(conn, ref, response)

          {:error, _conn, reason, _responses} ->
            {:error, reason}
        end
    after
      30_000 ->
        {:error, :timeout}
    end
  end

  defp process_responses([], _ref, response), do: response

  defp process_responses([{:status, ref, status} | rest], ref, response) do
    process_responses(rest, ref, %{response | status: status})
  end

  defp process_responses([{:headers, ref, headers} | rest], ref, response) do
    process_responses(rest, ref, %{response | headers: headers})
  end

  defp process_responses([{:data, ref, data} | rest], ref, response) do
    process_responses(rest, ref, %{response | body: [data | response.body]})
  end

  defp process_responses([{:done, ref} | rest], ref, response) do
    process_responses(rest, ref, %{response | done: true})
  end

  defp process_responses([_ | rest], ref, response) do
    process_responses(rest, ref, response)
  end

  defp extract_root_domain(domain) do
    # Simple extraction: take last two parts
    # Works for .com, .org, etc. but not .co.uk
    domain
    |> String.replace_prefix("*.", "")
    |> String.split(".")
    |> Enum.take(-2)
    |> Enum.join(".")
  end
end
