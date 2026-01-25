defmodule Burrow.Protocol.Fields do
  @moduledoc """
  Helpers for accessing protocol message fields with atom/string key flexibility.

  Protocol messages decoded from JSON have string keys, while internal code
  often uses atom keys. These helpers provide consistent access patterns.
  """

  @doc """
  Gets a value from a map using either an atom or string key.

  Tries the atom key first, then falls back to the string version.

  ## Examples

      iex> Fields.get(%{status: 200}, :status)
      200

      iex> Fields.get(%{"status" => 200}, :status)
      200

      iex> Fields.get(%{}, :status, 500)
      500
  """
  @spec get(map(), atom(), term()) :: term()
  def get(map, key, default \\ nil) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  @doc """
  Decodes a base64-encoded body if the encoding is "base64".

  Returns the original data unchanged for any other encoding or nil.

  ## Examples

      iex> Fields.decode_body("SGVsbG8=", "base64")
      "Hello"

      iex> Fields.decode_body("plain text", nil)
      "plain text"
  """
  @spec decode_body(binary() | nil, String.t() | nil) :: binary() | nil
  def decode_body(body, "base64") when is_binary(body) do
    case Base.decode64(body) do
      {:ok, decoded} -> decoded
      :error -> body
    end
  end

  def decode_body(body, _encoding), do: body
end
