defmodule Burrow.Server.SubdomainTest do
  use ExUnit.Case, async: true

  alias Burrow.Server.Subdomain

  describe "generate/0" do
    test "generates 8-character string by default" do
      subdomain = Subdomain.generate()
      assert String.length(subdomain) == 8
    end

    test "generates lowercase alphanumeric characters only" do
      subdomain = Subdomain.generate()
      assert String.match?(subdomain, ~r/^[a-z0-9]+$/)
    end

    test "generates unique values" do
      subdomains = for _ <- 1..100, do: Subdomain.generate()
      assert length(Enum.uniq(subdomains)) == 100
    end
  end

  describe "generate/1" do
    test "generates subdomain with custom length" do
      assert String.length(Subdomain.generate(4)) == 4
      assert String.length(Subdomain.generate(12)) == 12
      assert String.length(Subdomain.generate(32)) == 32
    end
  end

  describe "from_public_key/1" do
    test "derives deterministic subdomain from public key" do
      pk = :crypto.strong_rand_bytes(32)
      sub1 = Subdomain.from_public_key(pk)
      sub2 = Subdomain.from_public_key(pk)

      assert sub1 == sub2
    end

    test "generates 8-character hex string" do
      pk = :crypto.strong_rand_bytes(32)
      subdomain = Subdomain.from_public_key(pk)

      assert String.length(subdomain) == 8
      assert String.match?(subdomain, ~r/^[a-f0-9]+$/)
    end

    test "different keys produce different subdomains" do
      pk1 = :crypto.strong_rand_bytes(32)
      pk2 = :crypto.strong_rand_bytes(32)

      refute Subdomain.from_public_key(pk1) == Subdomain.from_public_key(pk2)
    end
  end

  describe "valid?/1" do
    test "accepts valid subdomains" do
      assert Subdomain.valid?("myapp")
      assert Subdomain.valid?("my-app")
      assert Subdomain.valid?("app123")
      assert Subdomain.valid?("a1b2c3d4")
      assert Subdomain.valid?("my-cool-app")
      assert Subdomain.valid?("test-123-dev")
    end

    test "accepts minimum length (4 chars)" do
      assert Subdomain.valid?("abcd")
    end

    test "accepts maximum length (32 chars)" do
      assert Subdomain.valid?(String.duplicate("a", 32))
    end

    test "rejects too short subdomains" do
      refute Subdomain.valid?("abc")
      refute Subdomain.valid?("ab")
      refute Subdomain.valid?("a")
      refute Subdomain.valid?("")
    end

    test "rejects too long subdomains" do
      refute Subdomain.valid?(String.duplicate("a", 33))
    end

    test "rejects subdomains starting with hyphen" do
      refute Subdomain.valid?("-invalid")
      refute Subdomain.valid?("-abc")
    end

    test "rejects subdomains ending with hyphen" do
      refute Subdomain.valid?("invalid-")
      refute Subdomain.valid?("abc-")
    end

    test "rejects uppercase characters" do
      refute Subdomain.valid?("UPPERCASE")
      refute Subdomain.valid?("MixedCase")
    end

    test "rejects spaces" do
      refute Subdomain.valid?("has spaces")
      refute Subdomain.valid?("has space")
    end

    test "rejects special characters" do
      refute Subdomain.valid?("has_underscore")
      refute Subdomain.valid?("has.dot")
      refute Subdomain.valid?("has@at")
    end

    test "rejects reserved subdomains" do
      refute Subdomain.valid?("www")
      refute Subdomain.valid?("api")
      refute Subdomain.valid?("admin")
      refute Subdomain.valid?("app")
      refute Subdomain.valid?("dashboard")
      refute Subdomain.valid?("status")
      refute Subdomain.valid?("health")
      refute Subdomain.valid?("metrics")
    end
  end

  describe "reserved/0" do
    test "returns list of reserved subdomains" do
      reserved = Subdomain.reserved()

      assert is_list(reserved)
      assert "www" in reserved
      assert "api" in reserved
      assert "admin" in reserved
    end
  end

  describe "extract_from_host/2" do
    test "extracts subdomain from host with base domain" do
      assert Subdomain.extract_from_host("myapp.burrow.example.com", "burrow.example.com") ==
               {:ok, "myapp"}
    end

    test "extracts subdomain with hyphens" do
      assert Subdomain.extract_from_host("my-cool-app.burrow.io", "burrow.io") ==
               {:ok, "my-cool-app"}
    end

    test "returns error for base domain without subdomain" do
      assert Subdomain.extract_from_host("burrow.example.com", "burrow.example.com") ==
               {:error, :no_subdomain}
    end

    test "returns error for non-matching domain" do
      assert Subdomain.extract_from_host("myapp.other.com", "burrow.example.com") ==
               {:error, :invalid_domain}
    end

    test "handles port in host" do
      assert Subdomain.extract_from_host("myapp.burrow.example.com:443", "burrow.example.com") ==
               {:ok, "myapp"}
    end
  end
end
