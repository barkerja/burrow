defmodule Burrow.Protocol.CodecTest do
  use ExUnit.Case, async: true

  alias Burrow.Protocol.Codec

  describe "encode/1" do
    test "encodes map to JSON string" do
      {:ok, json} = Codec.encode(%{type: "heartbeat", timestamp: 123})
      assert is_binary(json)
      assert String.contains?(json, "heartbeat")
      assert String.contains?(json, "123")
    end

    test "returns error for non-encodable values" do
      assert {:error, _} = Codec.encode(%{pid: self()})
    end
  end

  describe "encode!/1" do
    test "returns string on success" do
      json = Codec.encode!(%{type: "test"})
      assert is_binary(json)
    end

    test "raises on error" do
      assert_raise Protocol.UndefinedError, fn ->
        Codec.encode!(%{pid: self()})
      end
    end
  end

  describe "decode/1" do
    test "decodes JSON to map" do
      {:ok, map} = Codec.decode(~s({"type":"heartbeat","timestamp":123}))
      assert map.type == "heartbeat"
      assert map.timestamp == 123
    end

    test "handles nested structures with known keys" do
      json = ~s({"type":"register","attestation":{"public_key":"abc","timestamp":123}})
      {:ok, map} = Codec.decode(json)
      assert map.type == "register"
      assert map.attestation.public_key == "abc"
      assert map.attestation.timestamp == 123
    end

    test "handles arrays" do
      json = ~s({"headers":[["content-type","application/json"]]})
      {:ok, map} = Codec.decode(json)
      assert map.headers == [["content-type", "application/json"]]
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = Codec.decode("not json")
    end

    test "returns error for empty string" do
      assert {:error, _} = Codec.decode("")
    end

    test "keeps unknown keys as strings" do
      json = ~s({"unknown_key_xyz":"value"})
      {:ok, map} = Codec.decode(json)
      # Unknown atom keys stay as strings
      assert map["unknown_key_xyz"] == "value"
    end
  end

  describe "decode!/1" do
    test "returns map on success" do
      map = Codec.decode!(~s({"type":"test"}))
      assert map.type == "test"
    end

    test "raises on error" do
      assert_raise Jason.DecodeError, fn ->
        Codec.decode!("not json")
      end
    end
  end

  describe "round-trip" do
    test "encode then decode preserves data" do
      # Use lists instead of tuples for JSON compatibility
      original = %{
        type: "tunnel_request",
        request_id: "abc-123",
        method: "POST",
        path: "/api/users",
        headers: [["content-type", "application/json"]],
        body: ~s({"name":"John"})
      }

      {:ok, json} = Codec.encode(original)
      {:ok, decoded} = Codec.decode(json)

      assert decoded.type == "tunnel_request"
      assert decoded.request_id == "abc-123"
      assert decoded.method == "POST"
      assert decoded.path == "/api/users"
      assert decoded.headers == [["content-type", "application/json"]]
    end
  end
end
