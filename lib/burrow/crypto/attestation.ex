defmodule Burrow.Crypto.Attestation do
  @moduledoc """
  Attestation creation and verification for tunnel authentication.

  An attestation proves the client controls a specific Ed25519 keypair
  at a specific point in time. This prevents replay attacks while
  avoiding the need for server-side session storage.

  ## Attestation Format

  The signed message format is: `"burrow:register:<timestamp>:<subdomain_or_empty>"`

  ## Validity

  Attestations are valid for 5 minutes (300 seconds). Future timestamps
  are allowed up to 60 seconds to handle clock skew.
  """

  alias Burrow.Crypto.Keypair

  @type t :: %__MODULE__{
          public_key: binary(),
          timestamp: integer(),
          signature: binary(),
          requested_subdomain: String.t() | nil
        }

  @enforce_keys [:public_key, :timestamp, :signature]
  defstruct [:public_key, :timestamp, :signature, :requested_subdomain]

  @attestation_validity_seconds 300
  @max_future_seconds 60

  @doc """
  Creates an attestation proving control of a keypair.

  ## Examples

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> attestation = Burrow.Crypto.Attestation.create(keypair)
      iex> attestation.public_key == keypair.public_key
      true

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> attestation = Burrow.Crypto.Attestation.create(keypair, "myapp")
      iex> attestation.requested_subdomain
      "myapp"
  """
  @spec create(Keypair.t(), String.t() | nil) :: t()
  def create(%Keypair{} = keypair, requested_subdomain \\ nil) do
    timestamp = System.system_time(:second)
    message = build_message(timestamp, requested_subdomain)
    signature = Keypair.sign(message, keypair)

    %__MODULE__{
      public_key: keypair.public_key,
      timestamp: timestamp,
      signature: signature,
      requested_subdomain: requested_subdomain
    }
  end

  @doc """
  Verifies an attestation is valid and not expired.

  ## Examples

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> attestation = Burrow.Crypto.Attestation.create(keypair)
      iex> Burrow.Crypto.Attestation.verify(attestation)
      :ok
  """
  @spec verify(t()) :: :ok | {:error, :invalid_signature | :expired}
  def verify(%__MODULE__{} = attestation) do
    message = build_message(attestation.timestamp, attestation.requested_subdomain)
    now = System.system_time(:second)

    cond do
      # Too old (more than 5 minutes)
      now - attestation.timestamp > @attestation_validity_seconds ->
        {:error, :expired}

      # Too far in the future (more than 60 seconds)
      attestation.timestamp - now > @max_future_seconds ->
        {:error, :expired}

      # Invalid signature
      not Keypair.verify(message, attestation.signature, attestation.public_key) ->
        {:error, :invalid_signature}

      true ->
        :ok
    end
  end

  @doc """
  Serializes attestation to a map for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = att) do
    %{
      public_key: Base.encode64(att.public_key),
      timestamp: att.timestamp,
      signature: Base.encode64(att.signature),
      requested_subdomain: att.requested_subdomain
    }
  end

  @doc """
  Deserializes attestation from a map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    with {:ok, public_key} <- decode_base64(map, :public_key),
         {:ok, signature} <- decode_base64(map, :signature) do
      {:ok,
       %__MODULE__{
         public_key: public_key,
         timestamp: get_value(map, :timestamp),
         signature: signature,
         requested_subdomain: get_value(map, :requested_subdomain)
       }}
    end
  end

  defp build_message(timestamp, nil), do: "burrow:register:#{timestamp}:"
  defp build_message(timestamp, subdomain), do: "burrow:register:#{timestamp}:#{subdomain}"

  defp decode_base64(map, key) do
    value = get_value(map, key)

    case value do
      nil -> {:error, {:missing_key, key}}
      str when is_binary(str) -> Base.decode64(str)
    end
  end

  # Handle both atom and string keys
  defp get_value(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
