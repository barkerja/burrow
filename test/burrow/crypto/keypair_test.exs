defmodule Burrow.Crypto.KeypairTest do
  use ExUnit.Case, async: true

  alias Burrow.Crypto.Keypair

  describe "generate/0" do
    test "creates keypair with correct key sizes" do
      keypair = Keypair.generate()
      # Ed25519: 32-byte public key, 32-byte secret key (seed)
      assert byte_size(keypair.public_key) == 32
      assert byte_size(keypair.secret_key) == 32
    end

    test "generates unique keypairs" do
      k1 = Keypair.generate()
      k2 = Keypair.generate()
      refute k1.public_key == k2.public_key
      refute k1.secret_key == k2.secret_key
    end
  end

  describe "sign/2 and verify/3" do
    test "verifies valid signature" do
      keypair = Keypair.generate()
      message = "test message"
      signature = Keypair.sign(message, keypair)

      assert Keypair.verify(message, signature, keypair.public_key)
    end

    test "signature is 64 bytes" do
      keypair = Keypair.generate()
      signature = Keypair.sign("test", keypair)
      assert byte_size(signature) == 64
    end

    test "rejects tampered message" do
      keypair = Keypair.generate()
      signature = Keypair.sign("original", keypair)

      refute Keypair.verify("tampered", signature, keypair.public_key)
    end

    test "rejects wrong public key" do
      keypair1 = Keypair.generate()
      keypair2 = Keypair.generate()
      signature = Keypair.sign("message", keypair1)

      refute Keypair.verify("message", signature, keypair2.public_key)
    end

    test "rejects tampered signature" do
      keypair = Keypair.generate()
      signature = Keypair.sign("message", keypair)
      # Flip a bit in the signature
      <<first, rest::binary>> = signature
      tampered = <<Bitwise.bxor(first, 1), rest::binary>>

      refute Keypair.verify("message", tampered, keypair.public_key)
    end
  end

  describe "to_json/1 and from_json/1" do
    test "round-trip serialization" do
      keypair = Keypair.generate()
      json = Keypair.to_json(keypair)

      assert is_binary(json)
      assert {:ok, restored} = Keypair.from_json(json)
      assert restored.public_key == keypair.public_key
      assert restored.secret_key == keypair.secret_key
    end

    test "from_json returns error for invalid json" do
      assert {:error, _} = Keypair.from_json("not json")
    end

    test "from_json returns error for missing keys" do
      assert {:error, _} = Keypair.from_json("{}")
    end
  end
end
