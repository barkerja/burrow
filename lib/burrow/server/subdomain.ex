defmodule Burrow.Server.Subdomain do
  @moduledoc """
  Subdomain generation and validation.

  Provides utilities for:
  - Generating random subdomains
  - Deriving deterministic subdomains from public keys
  - Validating subdomain format
  - Extracting subdomains from HTTP host headers
  """

  @alphabet ~c"abcdefghijklmnopqrstuvwxyz0123456789"
  @default_length 8
  @reserved_subdomains ~w(www api admin app dashboard status health metrics)

  @doc """
  Generates a random subdomain.

  ## Examples

      iex> subdomain = Burrow.Server.Subdomain.generate()
      iex> String.length(subdomain)
      8
      iex> String.match?(subdomain, ~r/^[a-z0-9]+$/)
      true
  """
  @spec generate(pos_integer()) :: String.t()
  def generate(length \\ @default_length) do
    for _ <- 1..length, into: "" do
      <<Enum.random(@alphabet)>>
    end
  end

  @doc """
  Derives a deterministic subdomain from a public key.

  Uses first 8 characters of hex-encoded SHA256 hash.
  Same public key always produces the same subdomain.

  ## Examples

      iex> pk = :crypto.strong_rand_bytes(32)
      iex> sub1 = Burrow.Server.Subdomain.from_public_key(pk)
      iex> sub2 = Burrow.Server.Subdomain.from_public_key(pk)
      iex> sub1 == sub2
      true
  """
  @spec from_public_key(binary()) :: String.t()
  def from_public_key(public_key) when is_binary(public_key) do
    :crypto.hash(:sha256, public_key)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  @doc """
  Validates a subdomain string.

  Rules:
  - 2-32 characters
  - Lowercase alphanumeric and hyphens only
  - Must start and end with alphanumeric character
  - Cannot be a reserved subdomain

  ## Examples

      iex> Burrow.Server.Subdomain.valid?("myapp")
      true
      iex> Burrow.Server.Subdomain.valid?("my-app-123")
      true
      iex> Burrow.Server.Subdomain.valid?("www")
      false
      iex> Burrow.Server.Subdomain.valid?("-invalid")
      false
      iex> Burrow.Server.Subdomain.valid?("web")
      true
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(subdomain) when is_binary(subdomain) do
    len = String.length(subdomain)

    len >= 2 and len <= 32 and
      String.match?(subdomain, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) and
      subdomain not in @reserved_subdomains
  end

  def valid?(_), do: false

  @doc """
  Returns list of reserved subdomains.
  """
  @spec reserved() :: [String.t()]
  def reserved, do: @reserved_subdomains

  @doc """
  Extracts subdomain from an HTTP host header.

  ## Examples

      iex> Burrow.Server.Subdomain.extract_from_host("myapp.burrow.io", "burrow.io")
      {:ok, "myapp"}

      iex> Burrow.Server.Subdomain.extract_from_host("burrow.io", "burrow.io")
      {:error, :no_subdomain}

      iex> Burrow.Server.Subdomain.extract_from_host("myapp.other.io", "burrow.io")
      {:error, :invalid_domain}
  """
  @spec extract_from_host(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :no_subdomain | :invalid_domain}
  def extract_from_host(host, base_domain) when is_binary(host) and is_binary(base_domain) do
    # Strip port if present
    host = host |> String.split(":") |> hd()

    suffix = "." <> base_domain

    cond do
      host == base_domain ->
        {:error, :no_subdomain}

      String.ends_with?(host, suffix) ->
        subdomain = String.replace_suffix(host, suffix, "")
        {:ok, subdomain}

      true ->
        {:error, :invalid_domain}
    end
  end
end
