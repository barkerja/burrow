defmodule Burrow.ACME.Client do
  @moduledoc """
  ACME protocol client for Let's Encrypt certificate management.

  Implements RFC 8555 (ACME) for automated certificate issuance.

  ## Usage

      # Create or load account
      {:ok, account} = Burrow.ACME.Client.get_or_create_account(
        email: "admin@example.com",
        directory_url: :lets_encrypt_staging
      )

      # Order a certificate
      {:ok, order} = Burrow.ACME.Client.new_order(account, [
        "tunnel.example.com",
        "*.tunnel.example.com"
      ])

      # Complete challenges and finalize
      {:ok, cert} = Burrow.ACME.Client.complete_order(account, order)
  """

  require Logger

  @lets_encrypt_staging "https://acme-staging-v02.api.letsencrypt.org/directory"
  @lets_encrypt_production "https://acme-v02.api.letsencrypt.org/directory"

  @type directory :: %{
          new_nonce: String.t(),
          new_account: String.t(),
          new_order: String.t(),
          revoke_cert: String.t(),
          key_change: String.t()
        }

  @type account :: %{
          key: map(),
          kid: String.t(),
          directory: directory(),
          directory_url: String.t()
        }

  @doc """
  Returns the directory URL for the given environment.
  """
  def directory_url(:staging), do: @lets_encrypt_staging
  def directory_url(:lets_encrypt_staging), do: @lets_encrypt_staging
  def directory_url(:production), do: @lets_encrypt_production
  def directory_url(:lets_encrypt), do: @lets_encrypt_production
  def directory_url(url) when is_binary(url), do: url

  @doc """
  Fetches the ACME directory from the server.
  """
  @spec fetch_directory(String.t()) :: {:ok, directory()} | {:error, term()}
  def fetch_directory(url) do
    case http_get(url) do
      {:ok, 200, _headers, body} ->
        directory = %{
          new_nonce: body["newNonce"],
          new_account: body["newAccount"],
          new_order: body["newOrder"],
          revoke_cert: body["revokeCert"],
          key_change: body["keyChange"]
        }

        {:ok, directory}

      {:ok, status, _headers, body} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new ACME account or retrieves existing one.

  ## Options

  - `:email` - Contact email (required)
  - `:directory_url` - ACME directory URL or atom (:staging, :production)
  - `:key` - Existing account key (optional, generates new if not provided)
  """
  @spec get_or_create_account(keyword()) :: {:ok, account()} | {:error, term()}
  def get_or_create_account(opts) do
    email = Keyword.fetch!(opts, :email)
    dir_url = directory_url(Keyword.get(opts, :directory_url, :staging))
    key = Keyword.get(opts, :key) || generate_account_key()

    with {:ok, directory} <- fetch_directory(dir_url),
         {:ok, nonce} <- fetch_nonce(directory.new_nonce),
         {:ok, account_url, _response} <-
           create_or_fetch_account(directory, key, email, nonce) do
      account = %{
        key: key,
        kid: account_url,
        directory: directory,
        directory_url: dir_url
      }

      {:ok, account}
    end
  end

  @doc """
  Creates a new certificate order for the given domains.
  """
  @spec new_order(account(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def new_order(account, domains) when is_list(domains) do
    identifiers =
      Enum.map(domains, fn domain ->
        %{"type" => "dns", "value" => domain}
      end)

    payload = %{"identifiers" => identifiers}

    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, 201, headers, body} <-
           signed_request(account, account.directory.new_order, payload, nonce) do
      order = %{
        url: get_header(headers, "location"),
        status: body["status"],
        expires: body["expires"],
        identifiers: body["identifiers"],
        authorizations: body["authorizations"],
        finalize: body["finalize"],
        certificate: body["certificate"]
      }

      {:ok, order}
    else
      {:ok, status, _headers, body} ->
        {:error, {:order_failed, status, body}}

      error ->
        error
    end
  end

  @doc """
  Fetches authorization details including challenges.
  """
  @spec get_authorization(account(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_authorization(account, auth_url) do
    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, 200, _headers, body} <- signed_request(account, auth_url, nil, nonce) do
      auth = %{
        identifier: body["identifier"],
        status: body["status"],
        expires: body["expires"],
        challenges: parse_challenges(body["challenges"]),
        wildcard: body["wildcard"] || false
      }

      {:ok, auth}
    end
  end

  @doc """
  Notifies ACME server that a challenge is ready for validation.
  """
  @spec respond_to_challenge(account(), String.t()) :: {:ok, map()} | {:error, term()}
  def respond_to_challenge(account, challenge_url) do
    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, 200, _headers, body} <- signed_request(account, challenge_url, %{}, nonce) do
      {:ok, %{status: body["status"], token: body["token"]}}
    end
  end

  @doc """
  Polls an order or authorization until it reaches a final state.
  """
  @spec poll_status(account(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def poll_status(account, url, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 30)
    delay_ms = Keyword.get(opts, :delay_ms, 2000)

    do_poll_status(account, url, max_attempts, delay_ms)
  end

  defp do_poll_status(_account, _url, 0, _delay_ms) do
    {:error, :timeout}
  end

  defp do_poll_status(account, url, attempts, delay_ms) do
    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, 200, _headers, body} <- signed_request(account, url, nil, nonce) do
      case body["status"] do
        "valid" ->
          {:ok, body}

        "invalid" ->
          {:error, {:invalid, body}}

        "pending" ->
          Process.sleep(delay_ms)
          do_poll_status(account, url, attempts - 1, delay_ms)

        "processing" ->
          Process.sleep(delay_ms)
          do_poll_status(account, url, attempts - 1, delay_ms)

        "ready" ->
          {:ok, body}

        other ->
          {:error, {:unexpected_status, other}}
      end
    end
  end

  @doc """
  Finalizes an order by submitting a CSR.
  """
  @spec finalize_order(account(), String.t(), binary()) :: {:ok, map()} | {:error, term()}
  def finalize_order(account, finalize_url, csr_der) do
    payload = %{"csr" => Base.url_encode64(csr_der, padding: false)}

    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, status, _headers, body} when status in [200, 201] <-
           signed_request(account, finalize_url, payload, nonce) do
      {:ok, body}
    else
      {:ok, status, _headers, body} ->
        {:error, {:finalize_failed, status, body}}

      error ->
        error
    end
  end

  @doc """
  Downloads the certificate chain.
  """
  @spec download_certificate(account(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def download_certificate(account, cert_url) do
    with {:ok, nonce} <- fetch_nonce(account.directory.new_nonce),
         {:ok, 200, _headers, body} <-
           signed_request(account, cert_url, nil, nonce,
             accept: "application/pem-certificate-chain"
           ) do
      {:ok, body}
    end
  end

  @doc """
  Generates the key authorization string for HTTP-01 challenge.
  """
  @spec key_authorization(account(), String.t()) :: String.t()
  def key_authorization(account, token) do
    thumbprint = jwk_thumbprint(account.key)
    "#{token}.#{thumbprint}"
  end

  @doc """
  Generates the DNS TXT record value for DNS-01 challenge.
  """
  @spec dns_challenge_value(account(), String.t()) :: String.t()
  def dns_challenge_value(account, token) do
    key_auth = key_authorization(account, token)
    :crypto.hash(:sha256, key_auth) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a new EC P-256 account key.
  """
  @spec generate_account_key() :: map()
  def generate_account_key do
    {_pub, priv} = :crypto.generate_key(:ecdh, :secp256r1)

    # Convert to JWK format
    <<4, x::binary-size(32), y::binary-size(32)>> =
      elem(:crypto.generate_key(:ecdh, :secp256r1, priv), 0)

    %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => Base.url_encode64(x, padding: false),
      "y" => Base.url_encode64(y, padding: false),
      "d" => Base.url_encode64(priv, padding: false)
    }
  end

  @doc """
  Serializes an account key to JSON.
  """
  def serialize_key(key), do: Jason.encode!(key)

  @doc """
  Deserializes an account key from JSON.
  """
  def deserialize_key(json), do: Jason.decode!(json)

  # Private Functions

  defp create_or_fetch_account(directory, key, email, nonce) do
    payload = %{
      "termsOfServiceAgreed" => true,
      "contact" => ["mailto:#{email}"]
    }

    jwk = JOSE.JWK.from_map(key)

    protected = %{
      "alg" => "ES256",
      "nonce" => nonce,
      "url" => directory.new_account,
      "jwk" => jwk_public(key)
    }

    body = sign_payload(jwk, protected, payload)

    case http_post(directory.new_account, body, [{"content-type", "application/jose+json"}]) do
      {:ok, status, headers, response} when status in [200, 201] ->
        account_url = get_header(headers, "location")
        {:ok, account_url, response}

      {:ok, status, _headers, response} ->
        {:error, {:account_error, status, response}}

      error ->
        error
    end
  end

  defp signed_request(account, url, payload, nonce, opts \\ []) do
    jwk = JOSE.JWK.from_map(account.key)

    protected = %{
      "alg" => "ES256",
      "nonce" => nonce,
      "url" => url,
      "kid" => account.kid
    }

    body = sign_payload(jwk, protected, payload)
    headers = [{"content-type", "application/jose+json"}]

    headers =
      if accept = opts[:accept] do
        [{"accept", accept} | headers]
      else
        headers
      end

    http_post(url, body, headers)
  end

  defp sign_payload(jwk, protected, nil) do
    # POST-as-GET: empty payload
    protected_b64 = Base.url_encode64(Jason.encode!(protected), padding: false)
    payload_b64 = ""

    signing_input = "#{protected_b64}.#{payload_b64}"
    signature = sign_es256(jwk, signing_input)

    Jason.encode!(%{
      "protected" => protected_b64,
      "payload" => payload_b64,
      "signature" => signature
    })
  end

  defp sign_payload(jwk, protected, payload) do
    protected_b64 = Base.url_encode64(Jason.encode!(protected), padding: false)
    payload_b64 = Base.url_encode64(Jason.encode!(payload), padding: false)

    signing_input = "#{protected_b64}.#{payload_b64}"
    signature = sign_es256(jwk, signing_input)

    Jason.encode!(%{
      "protected" => protected_b64,
      "payload" => payload_b64,
      "signature" => signature
    })
  end

  defp sign_es256(jwk, message) do
    {_, signature} = JOSE.JWK.sign(message, %{"alg" => "ES256"}, jwk) |> JOSE.JWS.compact()
    # Extract just the signature part from the compact JWS
    [_header, _payload, sig] = String.split(signature, ".")
    sig
  end

  defp jwk_public(key) do
    Map.take(key, ["kty", "crv", "x", "y"])
  end

  defp jwk_thumbprint(key) do
    # RFC 7638 thumbprint
    public = jwk_public(key)

    ordered =
      Jason.encode!(%{
        "crv" => public["crv"],
        "kty" => public["kty"],
        "x" => public["x"],
        "y" => public["y"]
      })

    :crypto.hash(:sha256, ordered) |> Base.url_encode64(padding: false)
  end

  defp fetch_nonce(nonce_url) do
    case http_head(nonce_url) do
      {:ok, 200, headers} ->
        {:ok, get_header(headers, "replay-nonce")}

      {:ok, 204, headers} ->
        {:ok, get_header(headers, "replay-nonce")}

      error ->
        {:error, {:nonce_fetch_failed, error}}
    end
  end

  defp parse_challenges(challenges) do
    Enum.map(challenges, fn c ->
      %{
        type: c["type"],
        url: c["url"],
        token: c["token"],
        status: c["status"]
      }
    end)
  end

  defp get_header(headers, name) do
    name_lower = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == name_lower, do: v
    end)
  end

  # HTTP helpers using Mint

  defp http_get(url) do
    uri = URI.parse(url)
    scheme = if uri.scheme == "https", do: :https, else: :http

    with {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port || 443, []),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "GET", uri.path || "/", [], nil),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)

      body =
        if is_binary(response.body) and String.starts_with?(response.body, "{") do
          Jason.decode!(response.body)
        else
          response.body
        end

      {:ok, response.status, response.headers, body}
    end
  end

  defp http_head(url) do
    uri = URI.parse(url)
    scheme = if uri.scheme == "https", do: :https, else: :http

    with {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port || 443, []),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "HEAD", uri.path || "/", [], nil),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)
      {:ok, response.status, response.headers}
    end
  end

  defp http_post(url, body, headers) do
    uri = URI.parse(url)
    scheme = if uri.scheme == "https", do: :https, else: :http

    headers = [{"content-length", Integer.to_string(byte_size(body))} | headers]

    with {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port || 443, []),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "POST", uri.path || "/", headers, body),
         {:ok, response} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)

      resp_body =
        cond do
          is_binary(response.body) and String.starts_with?(response.body, "{") ->
            Jason.decode!(response.body)

          is_binary(response.body) and String.starts_with?(response.body, "-----BEGIN") ->
            response.body

          true ->
            response.body
        end

      {:ok, response.status, response.headers, resp_body}
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
            response = process_mint_responses(responses, ref, response)
            receive_response_loop(conn, ref, response)

          {:error, _conn, reason, _responses} ->
            {:error, reason}
        end
    after
      30_000 ->
        {:error, :timeout}
    end
  end

  defp process_mint_responses([], _ref, response), do: response

  defp process_mint_responses([{:status, ref, status} | rest], ref, response) do
    process_mint_responses(rest, ref, %{response | status: status})
  end

  defp process_mint_responses([{:headers, ref, headers} | rest], ref, response) do
    process_mint_responses(rest, ref, %{response | headers: headers})
  end

  defp process_mint_responses([{:data, ref, data} | rest], ref, response) do
    process_mint_responses(rest, ref, %{response | body: [data | response.body]})
  end

  defp process_mint_responses([{:done, ref} | rest], ref, response) do
    process_mint_responses(rest, ref, %{response | done: true})
  end

  defp process_mint_responses([_ | rest], ref, response) do
    process_mint_responses(rest, ref, response)
  end
end
