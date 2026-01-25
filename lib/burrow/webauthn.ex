defmodule Burrow.WebAuthn do
  @moduledoc """
  WebAuthn authentication wrapper using the Wax library.

  Handles both registration (creating new passkeys) and authentication
  (verifying passkey signatures).
  """

  alias Burrow.Accounts
  alias Burrow.Schemas.User

  @type challenge :: Wax.Challenge.t()
  @type credential_data :: %{
          credential_id: binary(),
          cose_key: map(),
          sign_count: non_neg_integer()
        }

  # ----------------------------------------------------------------------------
  # Registration
  # ----------------------------------------------------------------------------

  @doc """
  Generates a registration challenge for a new user.

  Returns `{challenge, options}` where options should be passed to the
  JavaScript WebAuthn API.
  """
  @spec registration_challenge(String.t()) :: {challenge(), map()}
  def registration_challenge(username) do
    challenge =
      Wax.new_registration_challenge(
        origin: origin(),
        rp_id: rp_id(),
        trusted_attestation_types: [:none, :basic, :uncertain, :attca, :self]
      )

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{
        id: rp_id(),
        name: rp_name()
      },
      user: %{
        id: Base.url_encode64(:crypto.hash(:sha256, username), padding: false),
        name: username,
        displayName: username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      authenticatorSelection: %{
        residentKey: "preferred",
        userVerification: "preferred"
      },
      timeout: 60_000,
      attestation: "none"
    }

    {challenge, options}
  end

  @doc """
  Generates a registration challenge for adding a credential to existing user.

  Returns `{challenge, options}` where options excludes existing credentials.
  """
  @spec registration_challenge(User.t(), [binary()]) :: {challenge(), map()}
  def registration_challenge(%User{} = user, existing_credential_ids) do
    challenge =
      Wax.new_registration_challenge(
        origin: origin(),
        rp_id: rp_id(),
        trusted_attestation_types: [:none, :basic, :uncertain, :attca, :self]
      )

    exclude_credentials =
      Enum.map(existing_credential_ids, fn cred_id ->
        %{
          type: "public-key",
          id: Base.url_encode64(cred_id, padding: false)
        }
      end)

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp: %{
        id: rp_id(),
        name: rp_name()
      },
      user: %{
        id: Base.url_encode64(:crypto.hash(:sha256, user.username), padding: false),
        name: user.username,
        displayName: user.display_name || user.username
      },
      pubKeyCredParams: [
        %{type: "public-key", alg: -7},
        %{type: "public-key", alg: -257}
      ],
      authenticatorSelection: %{
        residentKey: "preferred",
        userVerification: "preferred"
      },
      excludeCredentials: exclude_credentials,
      timeout: 60_000,
      attestation: "none"
    }

    {challenge, options}
  end

  @doc """
  Verifies a registration response and extracts credential data.

  Returns `{:ok, credential_data}` on success.
  """
  @spec verify_registration(map(), challenge()) ::
          {:ok, credential_data()} | {:error, atom() | String.t()}
  def verify_registration(attestation_response, challenge) do
    client_data_json = decode_base64(attestation_response["clientDataJSON"])
    attestation_object = decode_base64(attestation_response["attestationObject"])

    case Wax.register(attestation_object, client_data_json, challenge) do
      {:ok, {authenticator_data, _attestation_result}} ->
        credential_id = authenticator_data.attested_credential_data.credential_id
        cose_key = authenticator_data.attested_credential_data.credential_public_key
        sign_count = authenticator_data.sign_count

        {:ok,
         %{
           credential_id: credential_id,
           cose_key: cose_key,
           sign_count: sign_count
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ----------------------------------------------------------------------------
  # Authentication
  # ----------------------------------------------------------------------------

  @doc """
  Generates an authentication challenge for a user.

  Returns `{challenge, options}` where options includes the user's credentials.
  """
  @spec authentication_challenge(User.t()) :: {challenge(), map()}
  def authentication_challenge(%User{} = user) do
    credentials = Accounts.list_credentials_for_auth(user.id)

    allow_credentials =
      Enum.map(credentials, fn {cred_id, _cose_key} ->
        %{
          type: "public-key",
          id: Base.url_encode64(cred_id, padding: false)
        }
      end)

    challenge =
      Wax.new_authentication_challenge(
        origin: origin(),
        rp_id: rp_id(),
        allow_credentials: credentials
      )

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: rp_id(),
      allowCredentials: allow_credentials,
      userVerification: "preferred",
      timeout: 60_000
    }

    {challenge, options}
  end

  @doc """
  Generates an authentication challenge without user context (discoverable credentials).

  Returns `{challenge, options}` for passkey autofill / conditional UI.
  """
  @spec authentication_challenge() :: {challenge(), map()}
  def authentication_challenge do
    challenge =
      Wax.new_authentication_challenge(
        origin: origin(),
        rp_id: rp_id(),
        allow_credentials: []
      )

    options = %{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: rp_id(),
      allowCredentials: [],
      userVerification: "preferred",
      timeout: 60_000
    }

    {challenge, options}
  end

  @doc """
  Verifies an authentication response.

  Returns `{:ok, credential, new_sign_count}` on success.
  """
  @spec verify_authentication(map(), challenge()) ::
          {:ok, Burrow.Schemas.WebAuthnCredential.t(), non_neg_integer()}
          | {:error, atom() | String.t()}
  def verify_authentication(assertion_response, challenge) do
    credential_id = decode_base64(assertion_response["id"])

    case Accounts.get_credential_by_credential_id(credential_id) do
      nil ->
        {:error, :credential_not_found}

      credential ->
        client_data_json = decode_base64(assertion_response["clientDataJSON"])
        authenticator_data = decode_base64(assertion_response["authenticatorData"])
        signature = decode_base64(assertion_response["signature"])

        case Wax.authenticate(
               credential_id,
               authenticator_data,
               signature,
               client_data_json,
               challenge
             ) do
          {:ok, auth_data} ->
            {:ok, credential, auth_data.sign_count}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ----------------------------------------------------------------------------
  # Private
  # ----------------------------------------------------------------------------

  defp decode_base64(data) when is_binary(data) do
    case Base.url_decode64(data, padding: false) do
      {:ok, decoded} -> decoded
      :error -> Base.decode64!(data)
    end
  end

  defp origin do
    Application.get_env(:burrow, :webauthn)[:origin] || "http://localhost:4000"
  end

  defp rp_id do
    Application.get_env(:burrow, :webauthn)[:rp_id] || "localhost"
  end

  defp rp_name do
    Application.get_env(:burrow, :webauthn)[:rp_name] || "Burrow"
  end
end
