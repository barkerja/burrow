defmodule Burrow.ACME.StoreTest do
  use ExUnit.Case, async: true

  alias Burrow.ACME.Store

  setup do
    # Use a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "burrow_test_#{:rand.uniform(1_000_000)}")
    Application.put_env(:burrow, :acme, storage_dir: tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
      Application.delete_env(:burrow, :acme)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "base_dir/0" do
    test "returns configured directory", %{tmp_dir: tmp_dir} do
      assert Store.base_dir() == tmp_dir
    end

    test "returns default when not configured" do
      Application.delete_env(:burrow, :acme)
      assert Store.base_dir() == "/var/lib/burrow/acme"
    end
  end

  describe "ensure_dirs/0" do
    test "creates base directory and certs subdirectory", %{tmp_dir: tmp_dir} do
      refute File.exists?(tmp_dir)
      assert :ok = Store.ensure_dirs()
      assert File.dir?(tmp_dir)
      assert File.dir?(Path.join(tmp_dir, "certs"))
    end
  end

  describe "account storage" do
    test "save and load account" do
      account = %{
        key: %{"kty" => "EC", "crv" => "P-256", "x" => "abc", "y" => "def"},
        kid: "https://acme.example.com/acct/123",
        directory_url: "https://acme.example.com/directory"
      }

      assert :ok = Store.save_account(account)
      assert {:ok, loaded} = Store.load_account()

      assert loaded.key == account.key
      assert loaded.kid == account.kid
      assert loaded.directory_url == account.directory_url
    end

    test "load_account returns error when not found" do
      assert {:error, :not_found} = Store.load_account()
    end
  end

  describe "certificate storage" do
    test "save and load certificate paths" do
      domain = "test.example.com"
      cert_pem = test_certificate()
      key_pem = test_private_key()
      chain_pem = cert_pem
      domains = [domain, "www.test.example.com"]

      assert :ok = Store.save_certificate(domain, cert_pem, key_pem, chain_pem, domains)
      assert {:ok, paths} = Store.load_certificate_paths(domain)

      assert File.exists?(paths.cert)
      assert File.exists?(paths.key)
      assert File.exists?(paths.chain)
      assert paths.certfile == paths.chain
      assert paths.keyfile == paths.key
    end

    test "load_certificate_paths returns error when not found" do
      assert {:error, :not_found} = Store.load_certificate_paths("nonexistent.example.com")
    end

    test "save_certificate stores metadata" do
      domain = "meta.example.com"
      cert_pem = test_certificate()
      key_pem = test_private_key()

      assert :ok = Store.save_certificate(domain, cert_pem, key_pem, cert_pem, [domain])
      assert {:ok, meta} = Store.load_certificate_meta(domain)

      assert meta["domains"] == [domain]
      assert meta["not_before"]
      assert meta["not_after"]
      assert meta["created_at"]
    end

    test "certificate_valid? returns false when no certificate" do
      refute Store.certificate_valid?("missing.example.com")
    end

    test "certificate_valid? returns true for valid certificate" do
      domain = "valid.example.com"
      cert_pem = test_certificate()
      key_pem = test_private_key()

      assert :ok = Store.save_certificate(domain, cert_pem, key_pem, cert_pem, [domain])
      # The test cert is valid for ~90 days
      assert Store.certificate_valid?(domain, 30)
    end
  end

  describe "list_certificates/0" do
    test "returns empty list when no certificates" do
      Store.ensure_dirs()
      assert Store.list_certificates() == []
    end

    test "lists all certificates" do
      cert_pem = test_certificate()
      key_pem = test_private_key()

      Store.save_certificate("domain1.example.com", cert_pem, key_pem, cert_pem, [
        "domain1.example.com"
      ])

      Store.save_certificate("domain2.example.com", cert_pem, key_pem, cert_pem, [
        "domain2.example.com"
      ])

      certs = Store.list_certificates()
      domains = Enum.map(certs, fn {domain, _meta} -> domain end)

      assert "domain1.example.com" in domains
      assert "domain2.example.com" in domains
    end
  end

  describe "wildcard domain handling" do
    test "sanitizes wildcard domains for filesystem" do
      domain = "*.example.com"
      cert_pem = test_certificate()
      key_pem = test_private_key()

      assert :ok = Store.save_certificate(domain, cert_pem, key_pem, cert_pem, [domain])
      assert {:ok, _paths} = Store.load_certificate_paths(domain)
    end
  end

  describe "generate_cert_key/0" do
    test "generates RSA key pair" do
      {key, pem} = Store.generate_cert_key()
      assert key
      assert String.starts_with?(pem, "-----BEGIN RSA PRIVATE KEY-----")
    end
  end

  describe "generate_csr/2" do
    test "generates CSR for domains" do
      {key, _pem} = Store.generate_cert_key()
      domains = ["example.com", "www.example.com"]

      {der, pem} = Store.generate_csr(key, domains)

      assert is_binary(der)
      assert String.starts_with?(pem, "-----BEGIN CERTIFICATE REQUEST-----")
    end
  end

  # Helper to generate a self-signed test certificate
  defp test_certificate do
    key = X509.PrivateKey.new_rsa(2048)

    cert =
      X509.Certificate.self_signed(
        key,
        "/CN=test.example.com",
        template: :server,
        validity: 90
      )

    X509.Certificate.to_pem(cert)
  end

  defp test_private_key do
    key = X509.PrivateKey.new_rsa(2048)
    X509.PrivateKey.to_pem(key)
  end
end
