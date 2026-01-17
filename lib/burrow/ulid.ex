defmodule Burrow.ULID do
  @moduledoc """
  ULID (Universally Unique Lexicographically Sortable Identifier) generation.

  ULIDs are 128-bit identifiers that are:
  - Lexicographically sortable
  - Encoded as 26 Crockford Base32 characters
  - Contain a 48-bit timestamp (milliseconds) and 80-bit randomness

  Format: `01ARZ3NDEKTSV4RRFFQ69G5FAV`
  - First 10 characters: timestamp
  - Last 16 characters: randomness

  ## Why ULID over UUID?

  - Sortable by creation time (useful for logs, debugging)
  - Shorter string representation (26 vs 36 characters)
  - No special characters (no hyphens)
  - Case insensitive
  """

  import Bitwise

  # Crockford Base32 alphabet (excludes I, L, O, U to avoid confusion)
  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @alphabet_map @alphabet |> Enum.with_index() |> Map.new()

  @doc """
  Generates a new ULID.

  ## Examples

      iex> ulid = Burrow.ULID.generate()
      iex> String.length(ulid)
      26
      iex> String.match?(ulid, ~r/^[0-9A-HJKMNP-TV-Z]{26}$/)
      true
  """
  @spec generate() :: String.t()
  def generate do
    generate(System.system_time(:millisecond))
  end

  @doc """
  Generates a ULID with a specific timestamp.

  Useful for testing or when you need to control the timestamp.
  """
  @spec generate(non_neg_integer()) :: String.t()
  def generate(timestamp_ms) when is_integer(timestamp_ms) and timestamp_ms >= 0 do
    random_bytes = :crypto.strong_rand_bytes(10)
    encode_ulid(timestamp_ms, random_bytes)
  end

  @doc """
  Extracts the timestamp from a ULID.

  Returns the Unix timestamp in milliseconds.

  ## Examples

      iex> ulid = Burrow.ULID.generate()
      iex> ts = Burrow.ULID.timestamp(ulid)
      iex> is_integer(ts) and ts > 0
      true
  """
  @spec timestamp(String.t()) :: non_neg_integer()
  def timestamp(ulid) when is_binary(ulid) and byte_size(ulid) == 26 do
    ulid
    |> String.upcase()
    |> String.slice(0, 10)
    |> decode_timestamp()
  end

  @doc """
  Checks if a string is a valid ULID format.

  ## Examples

      iex> Burrow.ULID.valid?("01ARZ3NDEKTSV4RRFFQ69G5FAV")
      true
      iex> Burrow.ULID.valid?("invalid")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(ulid) when is_binary(ulid) do
    byte_size(ulid) == 26 and
      String.match?(String.upcase(ulid), ~r/^[0-9A-HJKMNP-TV-Z]{26}$/)
  end

  def valid?(_), do: false

  # Encode timestamp (48 bits) and random (80 bits) into 26 character ULID
  defp encode_ulid(timestamp_ms, <<random::80>>) do
    # Ensure timestamp fits in 48 bits
    timestamp_ms = timestamp_ms &&& 0xFFFFFFFFFFFF

    # Encode timestamp (48 bits -> 10 characters)
    # Each character represents 5 bits, so 10 chars = 50 bits
    # First 2 bits of first char are always 0 (timestamp max is 48 bits)
    timestamp_chars = encode_base32(timestamp_ms, 10)

    # Encode random (80 bits -> 16 characters)
    random_chars = encode_base32(random, 16)

    timestamp_chars <> random_chars
  end

  # Encode an integer to Crockford Base32 with fixed length
  defp encode_base32(value, length) do
    encode_base32_acc(value, length, [])
  end

  defp encode_base32_acc(_value, 0, acc) do
    acc |> IO.iodata_to_binary()
  end

  defp encode_base32_acc(value, remaining, acc) do
    # Take lowest 5 bits
    char_index = value &&& 0x1F
    char = Enum.at(@alphabet, char_index)
    encode_base32_acc(value >>> 5, remaining - 1, [char | acc])
  end

  # Decode timestamp from first 10 characters
  defp decode_timestamp(timestamp_str) do
    timestamp_str
    |> String.graphemes()
    |> Enum.reduce(0, fn char, acc ->
      char_value = Map.fetch!(@alphabet_map, hd(String.to_charlist(char)))
      acc * 32 + char_value
    end)
  end
end
