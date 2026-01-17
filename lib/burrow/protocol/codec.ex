defmodule Burrow.Protocol.Codec do
  @moduledoc """
  JSON encoding/decoding for tunnel protocol messages.

  Encodes maps to JSON strings and decodes JSON strings to maps.
  When decoding, known atom keys are converted to atoms, while
  unknown keys remain as strings to prevent atom table exhaustion.
  """

  @known_keys ~w(
    type timestamp tunnel_id subdomain full_url request_id
    method path query_string headers body body_encoding status
    attestation public_key signature requested_subdomain
    local_host local_port code message
    ws_id opcode data data_encoding reason
  )a

  @doc """
  Encodes a message map to JSON.

  ## Examples

      iex> Burrow.Protocol.Codec.encode(%{type: "heartbeat", timestamp: 123})
      {:ok, ~s({"timestamp":123,"type":"heartbeat"})}
  """
  @spec encode(map()) :: {:ok, String.t()} | {:error, term()}
  def encode(message) when is_map(message) do
    Jason.encode(message)
  end

  @doc """
  Encodes a message map to JSON, raising on error.
  """
  @spec encode!(map()) :: String.t()
  def encode!(message) when is_map(message) do
    Jason.encode!(message)
  end

  @doc """
  Decodes JSON to a message map.

  Known protocol keys are converted to atoms. Unknown keys remain as strings.

  ## Examples

      iex> Burrow.Protocol.Codec.decode(~s({"type":"heartbeat","timestamp":123}))
      {:ok, %{type: "heartbeat", timestamp: 123}}
  """
  @spec decode(String.t()) :: {:ok, map()} | {:error, term()}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> {:ok, atomize_keys(data)}
      error -> error
    end
  end

  @doc """
  Decodes JSON to a message map, raising on error.
  """
  @spec decode!(String.t()) :: map()
  def decode!(json) when is_binary(json) do
    json |> Jason.decode!() |> atomize_keys()
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {atomize_key(k), atomize_keys(v)} end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(other), do: other

  defp atomize_key(key) when is_binary(key) do
    atom = String.to_atom(key)

    if atom in @known_keys do
      atom
    else
      key
    end
  end

  defp atomize_key(key), do: key
end
