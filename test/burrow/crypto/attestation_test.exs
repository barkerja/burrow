defmodule Burrow.Crypto.AttestationTest do
  use ExUnit.Case, async: true

  alias Burrow.Crypto.{Keypair, Attestation}

  describe "create/2" do
    test "creates attestation with current timestamp" do
      keypair = Keypair.generate()
      before = System.system_time(:second)
      attestation = Attestation.create(keypair)
      after_time = System.system_time(:second)

      assert attestation.public_key == keypair.public_key
      assert attestation.timestamp >= before
      assert attestation.timestamp <= after_time
      assert byte_size(attestation.signature) == 64
      assert attestation.requested_subdomain == nil
    end

    test "includes requested subdomain when provided" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair, "myapp")
      assert attestation.requested_subdomain == "myapp"
    end
  end

  describe "verify/1" do
    test "returns :ok for valid attestation" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair)
      assert :ok = Attestation.verify(attestation)
    end

    test "returns :ok for attestation with subdomain" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair, "myapp")
      assert :ok = Attestation.verify(attestation)
    end

    test "returns error for expired attestation" do
      keypair = Keypair.generate()
      # Create attestation with old timestamp (more than 5 minutes ago)
      old_timestamp = System.system_time(:second) - 400
      message = "burrow:register:#{old_timestamp}:"
      signature = Keypair.sign(message, keypair)

      old_attestation = %Attestation{
        public_key: keypair.public_key,
        timestamp: old_timestamp,
        signature: signature,
        requested_subdomain: nil
      }

      assert {:error, :expired} = Attestation.verify(old_attestation)
    end

    test "returns error for future timestamp" do
      keypair = Keypair.generate()
      # Create attestation with future timestamp (more than 60s ahead)
      future_timestamp = System.system_time(:second) + 120
      message = "burrow:register:#{future_timestamp}:"
      signature = Keypair.sign(message, keypair)

      future_attestation = %Attestation{
        public_key: keypair.public_key,
        timestamp: future_timestamp,
        signature: signature,
        requested_subdomain: nil
      }

      assert {:error, :expired} = Attestation.verify(future_attestation)
    end

    test "returns error for invalid signature (tampered timestamp)" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair)
      # Tamper with timestamp without re-signing
      tampered = %{attestation | timestamp: attestation.timestamp - 1}

      assert {:error, :invalid_signature} = Attestation.verify(tampered)
    end

    test "returns error for invalid signature (wrong key)" do
      keypair1 = Keypair.generate()
      keypair2 = Keypair.generate()
      attestation = Attestation.create(keypair1)
      # Use different public key
      wrong_key = %{attestation | public_key: keypair2.public_key}

      assert {:error, :invalid_signature} = Attestation.verify(wrong_key)
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trip serialization without subdomain" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair)
      map = Attestation.to_map(attestation)

      assert is_binary(map.public_key)
      assert is_binary(map.signature)
      assert is_integer(map.timestamp)

      assert {:ok, restored} = Attestation.from_map(map)
      assert restored.public_key == attestation.public_key
      assert restored.timestamp == attestation.timestamp
      assert restored.signature == attestation.signature
      assert restored.requested_subdomain == nil
    end

    test "round-trip serialization with subdomain" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair, "test")
      map = Attestation.to_map(attestation)

      assert {:ok, restored} = Attestation.from_map(map)
      assert restored.requested_subdomain == "test"
    end

    test "restored attestation still verifies" do
      keypair = Keypair.generate()
      attestation = Attestation.create(keypair, "myapp")
      map = Attestation.to_map(attestation)
      {:ok, restored} = Attestation.from_map(map)

      assert :ok = Attestation.verify(restored)
    end
  end
end
