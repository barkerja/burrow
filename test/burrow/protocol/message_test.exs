defmodule Burrow.Protocol.MessageTest do
  use ExUnit.Case, async: true

  alias Burrow.Protocol.Message

  describe "register_tunnel/3" do
    test "builds correct structure" do
      attestation = %{public_key: "pk123", timestamp: 123, signature: "sig"}
      msg = Message.register_tunnel(attestation, "localhost", 3000)

      assert msg.type == "register_tunnel"
      assert msg.attestation == attestation
      assert msg.local_host == "localhost"
      assert msg.local_port == 3000
    end
  end

  describe "tunnel_registered/3" do
    test "builds correct structure" do
      msg = Message.tunnel_registered("tid-123", "abc123", "https://abc123.example.com")

      assert msg.type == "tunnel_registered"
      assert msg.tunnel_id == "tid-123"
      assert msg.subdomain == "abc123"
      assert msg.full_url == "https://abc123.example.com"
    end
  end

  describe "tunnel_request/3" do
    test "builds correct structure" do
      request_data = %{
        method: "POST",
        path: "/api/users",
        query_string: "page=1",
        headers: [["content-type", "application/json"]],
        body: ~s({"name":"John"})
      }

      msg = Message.tunnel_request("rid-123", "tid-456", request_data)

      assert msg.type == "tunnel_request"
      assert msg.request_id == "rid-123"
      assert msg.tunnel_id == "tid-456"
      assert msg.method == "POST"
      assert msg.path == "/api/users"
      assert msg.query_string == "page=1"
      assert msg.headers == [["content-type", "application/json"]]
      assert msg.body == ~s({"name":"John"})
    end

    test "handles nil query_string" do
      request_data = %{
        method: "GET",
        path: "/api",
        query_string: nil,
        headers: [],
        body: nil
      }

      msg = Message.tunnel_request("rid", "tid", request_data)
      assert msg.query_string == ""
    end
  end

  describe "tunnel_response/4" do
    test "builds correct structure" do
      headers = [["content-type", "application/json"], ["x-request-id", "abc"]]
      msg = Message.tunnel_response("rid-123", 201, headers, ~s({"id":1}))

      assert msg.type == "tunnel_response"
      assert msg.request_id == "rid-123"
      assert msg.status == 201
      assert msg.headers == headers
      assert msg.body == ~s({"id":1})
    end

    test "handles nil body" do
      msg = Message.tunnel_response("rid", 204, [], nil)
      assert msg.body == nil
    end
  end

  describe "heartbeat/0" do
    test "builds correct structure with timestamp" do
      before = System.system_time(:second)
      msg = Message.heartbeat()
      after_time = System.system_time(:second)

      assert msg.type == "heartbeat"
      assert msg.timestamp >= before
      assert msg.timestamp <= after_time
    end
  end

  describe "error/2" do
    test "builds correct structure" do
      msg = Message.error("invalid_token", "Token has expired")

      assert msg.type == "error"
      assert msg.code == "invalid_token"
      assert msg.message == "Token has expired"
    end
  end

  describe "type/1" do
    test "detects register_tunnel" do
      assert Message.type(%{type: "register_tunnel"}) == :register_tunnel
    end

    test "detects tunnel_registered" do
      assert Message.type(%{type: "tunnel_registered"}) == :tunnel_registered
    end

    test "detects tunnel_request" do
      assert Message.type(%{type: "tunnel_request"}) == :tunnel_request
    end

    test "detects tunnel_response" do
      assert Message.type(%{type: "tunnel_response"}) == :tunnel_response
    end

    test "detects heartbeat" do
      assert Message.type(%{type: "heartbeat"}) == :heartbeat
    end

    test "detects error" do
      assert Message.type(%{type: "error"}) == :error
    end

    test "returns :unknown for unknown types" do
      assert Message.type(%{type: "something_else"}) == :unknown
    end

    test "returns :unknown for missing type" do
      assert Message.type(%{}) == :unknown
    end

    test "returns :unknown for nil" do
      assert Message.type(nil) == :unknown
    end
  end
end
