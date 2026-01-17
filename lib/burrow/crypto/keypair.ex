defmodule Burrow.Crypto.Keypair do
  @moduledoc """
  Ed25519 keypair generation, signing, and verification.

  Uses Erlang :crypto for all operations. No external dependencies.
  """

  @type t :: %__MODULE__{
          public_key: binary(),
          secret_key: binary()
        }

  @enforce_keys [:public_key, :secret_key]
  defstruct [:public_key, :secret_key]

  @doc """
  Generates a new Ed25519 keypair.

  ## Examples

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> byte_size(keypair.public_key)
      32
      iex> byte_size(keypair.secret_key)
      64
  """
  @spec generate() :: t()
  def generate do
    {public, secret} = :crypto.generate_key(:eddsa, :ed25519)
    %__MODULE__{public_key: public, secret_key: secret}
  end

  @doc """
  Signs a message with the keypair's secret key.

  ## Examples

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> signature = Burrow.Crypto.Keypair.sign("hello", keypair)
      iex> byte_size(signature)
      64
  """
  @spec sign(binary(), t()) :: binary()
  def sign(message, %__MODULE__{secret_key: secret}) when is_binary(message) do
    :crypto.sign(:eddsa, :sha512, message, [secret, :ed25519])
  end

  @doc """
  Verifies a signature against a message and public key.

  ## Examples

      iex> keypair = Burrow.Crypto.Keypair.generate()
      iex> signature = Burrow.Crypto.Keypair.sign("hello", keypair)
      iex> Burrow.Crypto.Keypair.verify("hello", signature, keypair.public_key)
      true
      iex> Burrow.Crypto.Keypair.verify("world", signature, keypair.public_key)
      false
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(message, signature, public_key)
      when is_binary(message) and is_binary(signature) and is_binary(public_key) do
    :crypto.verify(:eddsa, :sha512, message, signature, [public_key, :ed25519])
  end

  @doc """
  Encodes keypair to JSON for file storage.
  """
  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = keypair) do
    Jason.encode!(%{
      public_key: Base.encode64(keypair.public_key),
      secret_key: Base.encode64(keypair.secret_key)
    })
  end

  @doc """
  Decodes keypair from JSON.
  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    with {:ok, data} <- Jason.decode(json),
         {:ok, public} <- decode_key(data, "public_key"),
         {:ok, secret} <- decode_key(data, "secret_key") do
      {:ok, %__MODULE__{public_key: public, secret_key: secret}}
    end
  end

  defp decode_key(data, key) do
    case data[key] do
      nil -> {:error, {:missing_key, key}}
      value -> Base.decode64(value)
    end
  end

  @doc """
  Saves keypair to a file.
  """
  @spec save_to_file(t(), Path.t()) :: :ok | {:error, term()}
  def save_to_file(%__MODULE__{} = keypair, path) do
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, to_json(keypair)) do
      :ok
    end
  end

  @doc """
  Loads keypair from a file.
  """
  @spec load_from_file(Path.t()) :: {:ok, t()} | {:error, term()}
  def load_from_file(path) do
    with {:ok, json} <- File.read(path),
         {:ok, keypair} <- from_json(json) do
      {:ok, keypair}
    end
  end
end
