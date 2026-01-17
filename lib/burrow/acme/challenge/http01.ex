defmodule Burrow.ACME.Challenge.HTTP01 do
  @moduledoc """
  HTTP-01 ACME challenge handler.

  Responds to Let's Encrypt HTTP-01 challenges at:
  `GET /.well-known/acme-challenge/{token}`

  ## Usage

  Add to your Plug pipeline before other routes:

      plug Burrow.ACME.Challenge.HTTP01

  Register pending challenges before starting validation:

      HTTP01.register_challenge("token123", "token123.thumbprint")

  After validation:

      HTTP01.remove_challenge("token123")
  """

  @behaviour Plug

  use Agent

  @doc """
  Starts the challenge store agent.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Registers a pending challenge.
  """
  @spec register_challenge(String.t(), String.t()) :: :ok
  def register_challenge(token, key_authorization) do
    Agent.update(__MODULE__, &Map.put(&1, token, key_authorization))
  end

  @doc """
  Removes a challenge after validation.
  """
  @spec remove_challenge(String.t()) :: :ok
  def remove_challenge(token) do
    Agent.update(__MODULE__, &Map.delete(&1, token))
  end

  @doc """
  Gets the key authorization for a token.
  """
  @spec get_challenge(String.t()) :: String.t() | nil
  def get_challenge(token) do
    Agent.get(__MODULE__, &Map.get(&1, token))
  end

  @doc """
  Clears all pending challenges.
  """
  @spec clear_challenges() :: :ok
  def clear_challenges do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  # Plug Implementation

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_info: [".well-known", "acme-challenge", token]} = conn, _opts) do
    case get_challenge(token) do
      nil ->
        conn
        |> Plug.Conn.send_resp(404, "Challenge not found")
        |> Plug.Conn.halt()

      key_authorization ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, key_authorization)
        |> Plug.Conn.halt()
    end
  end

  def call(conn, _opts), do: conn
end
