defmodule Burrow.ACME.Challenge.HTTP01Test do
  use ExUnit.Case, async: false
  import Plug.Test

  alias Burrow.ACME.Challenge.HTTP01

  setup do
    # Ensure the HTTP01 agent is started
    case Process.whereis(HTTP01) do
      nil ->
        {:ok, _pid} = HTTP01.start_link([])
        :ok

      _pid ->
        # Clear any existing challenges
        :ok
    end

    on_exit(fn ->
      # Clean up by removing all challenges
      :ok
    end)

    :ok
  end

  describe "challenge registration" do
    test "register_challenge stores challenge" do
      token = "test-token-123"
      key_auth = "test-token-123.thumbprint123"

      assert :ok = HTTP01.register_challenge(token, key_auth)
      assert HTTP01.get_challenge(token) == key_auth
    end

    test "remove_challenge removes challenge" do
      token = "remove-test-token"
      key_auth = "remove-test-token.thumbprint"

      HTTP01.register_challenge(token, key_auth)
      assert HTTP01.get_challenge(token) == key_auth

      HTTP01.remove_challenge(token)
      assert HTTP01.get_challenge(token) == nil
    end

    test "get_challenge returns nil for unknown token" do
      assert HTTP01.get_challenge("unknown-token") == nil
    end
  end

  describe "Plug behavior" do
    test "init returns opts unchanged" do
      opts = [some: :option]
      assert HTTP01.init(opts) == opts
    end

    test "responds to ACME challenge requests" do
      token = "acme-challenge-token"
      key_auth = "acme-challenge-token.account-thumbprint"
      HTTP01.register_challenge(token, key_auth)

      conn =
        conn(:get, "/.well-known/acme-challenge/#{token}")
        |> HTTP01.call([])

      assert conn.status == 200
      assert conn.resp_body == key_auth
      assert conn.halted
    end

    test "returns 404 for unknown challenge token" do
      conn =
        conn(:get, "/.well-known/acme-challenge/unknown-token")
        |> HTTP01.call([])

      assert conn.status == 404
      assert conn.resp_body == "Challenge not found"
      assert conn.halted
    end

    test "passes through non-challenge requests" do
      conn =
        conn(:get, "/health")
        |> HTTP01.call([])

      refute conn.halted
      assert conn.status == nil
    end

    test "passes through other .well-known requests" do
      conn =
        conn(:get, "/.well-known/other-endpoint")
        |> HTTP01.call([])

      refute conn.halted
      assert conn.status == nil
    end

    test "handles POST to challenge path (returns 404 for unknown)" do
      # ACME only uses GET, but plug handles all methods consistently
      conn =
        conn(:post, "/.well-known/acme-challenge/unknown-token")
        |> HTTP01.call([])

      assert conn.halted
      assert conn.status == 404
    end
  end
end
