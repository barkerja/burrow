defmodule Burrow.ACME.ClientTest do
  use ExUnit.Case, async: true

  alias Burrow.ACME.Client

  describe "directory URLs" do
    test "returns production URL for :production" do
      url = Client.directory_url(:production)
      assert url == "https://acme-v02.api.letsencrypt.org/directory"
    end

    test "returns staging URL for :staging" do
      url = Client.directory_url(:staging)
      assert url == "https://acme-staging-v02.api.letsencrypt.org/directory"
    end

    test "returns custom URL as-is" do
      custom = "https://custom.acme.server/directory"
      assert Client.directory_url(custom) == custom
    end
  end

  describe "key_authorization/2" do
    test "combines token with JWK thumbprint" do
      account = create_test_account()
      token = "test-challenge-token"

      key_auth = Client.key_authorization(account, token)

      # Should be token.thumbprint format
      assert String.contains?(key_auth, ".")
      [returned_token, thumbprint] = String.split(key_auth, ".", parts: 2)
      assert returned_token == token
      assert byte_size(thumbprint) > 0
    end

    test "produces consistent thumbprint for same key" do
      account = create_test_account()

      auth1 = Client.key_authorization(account, "token1")
      auth2 = Client.key_authorization(account, "token2")

      [_, thumbprint1] = String.split(auth1, ".", parts: 2)
      [_, thumbprint2] = String.split(auth2, ".", parts: 2)

      assert thumbprint1 == thumbprint2
    end
  end

  describe "dns_challenge_value/2" do
    test "returns base64url encoded SHA256 of key authorization" do
      account = create_test_account()
      token = "dns-challenge-token"

      value = Client.dns_challenge_value(account, token)

      # Should be URL-safe base64 without padding
      refute String.contains?(value, "+")
      refute String.contains?(value, "/")
      refute String.ends_with?(value, "=")
    end

    test "produces consistent value for same inputs" do
      account = create_test_account()
      token = "consistent-token"

      value1 = Client.dns_challenge_value(account, token)
      value2 = Client.dns_challenge_value(account, token)

      assert value1 == value2
    end
  end

  describe "generate_account_key/0" do
    test "generates EC P-256 key" do
      key = Client.generate_account_key()

      assert is_map(key)
      assert key["kty"] == "EC"
      assert key["crv"] == "P-256"
      assert key["x"]
      assert key["y"]
      assert key["d"]  # Private key component
    end

    test "generates unique keys" do
      key1 = Client.generate_account_key()
      key2 = Client.generate_account_key()

      assert key1["d"] != key2["d"]
    end
  end

  # Helper to create a test account with a key
  defp create_test_account do
    key = Client.generate_account_key()

    %{
      key: key,
      kid: "https://acme.example.com/acct/test",
      directory: %{
        "newNonce" => "https://acme.example.com/acme/new-nonce",
        "newAccount" => "https://acme.example.com/acme/new-account",
        "newOrder" => "https://acme.example.com/acme/new-order"
      }
    }
  end
end
