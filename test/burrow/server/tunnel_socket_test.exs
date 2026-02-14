defmodule Burrow.Server.TunnelSocketTest do
  use Burrow.DataCase, async: false

  alias Burrow.Server.TunnelSocket
  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.Accounts

  setup do
    start_supervised!({Burrow.Server.TunnelRegistry, name: Burrow.Server.TunnelRegistry})
    start_supervised!({Burrow.Server.PendingRequests, name: Burrow.Server.PendingRequests})
    Application.put_env(:burrow, :server, base_domain: "burrow.test")

    {:ok, user} = Accounts.create_user(%{username: "testuser"})
    {:ok, _token_record, token_string} = Accounts.create_api_token(user.id, %{name: "test"})

    [user: user, token: token_string]
  end

  describe "init/1" do
    test "initializes with awaiting_registration state" do
      assert {:ok, state} = TunnelSocket.init([])
      assert state.status == :awaiting_registration
      assert state.tunnels == %{}
    end
  end

  describe "handle_in/2 - registration" do
    test "registers tunnel with valid token", ctx do
      {:ok, state} = TunnelSocket.init([])

      message = Message.register_tunnel(ctx.token, "localhost", 3000)

      {:reply, :ok, {:text, response_json}, new_state} =
        TunnelSocket.handle_in({Codec.encode!(message), [opcode: :text]}, state)

      response = Codec.decode!(response_json)
      assert response.type == "tunnel_registered"
      assert is_binary(response.subdomain)
      assert String.starts_with?(response.full_url, "https://")
      assert new_state.status == :connected
      assert map_size(new_state.tunnels) == 1
    end

    test "rejects missing token" do
      {:ok, state} = TunnelSocket.init([])

      message = Message.register_tunnel(nil, "localhost", 3000)

      {:reply, :ok, {:text, response_json}, new_state} =
        TunnelSocket.handle_in({Codec.encode!(message), [opcode: :text]}, state)

      response = Codec.decode!(response_json)
      assert response.type == "error"
      assert response.code == "invalid_token"
      assert new_state.status == :awaiting_registration
    end

    test "rejects invalid token format" do
      {:ok, state} = TunnelSocket.init([])

      message = Message.register_tunnel("not-a-valid-token", "localhost", 3000)

      {:reply, :ok, {:text, response_json}, new_state} =
        TunnelSocket.handle_in({Codec.encode!(message), [opcode: :text]}, state)

      response = Codec.decode!(response_json)
      assert response.type == "error"
      assert response.code == "invalid_token"
      assert new_state.status == :awaiting_registration
    end
  end

  describe "handle_in/2 - tunnel_response" do
    test "completes pending request with response", ctx do
      {:ok, state} = TunnelSocket.init([])

      # Register a tunnel first
      reg_message = Message.register_tunnel(ctx.token, "localhost", 3000)

      {:reply, :ok, {:text, _}, state} =
        TunnelSocket.handle_in({Codec.encode!(reg_message), [opcode: :text]}, state)

      # Register a pending request
      request_id = "req-123"
      Burrow.Server.PendingRequests.register(request_id, "tunnel-id", self())

      # Send tunnel_response
      response_message = Message.tunnel_response(request_id, 200, [], "OK")

      {:ok, _state} =
        TunnelSocket.handle_in({Codec.encode!(response_message), [opcode: :text]}, state)

      # Should receive the response
      assert_receive {:tunnel_response, ^request_id, response}, 1000
      assert response.status == 200
    end
  end

  describe "handle_in/2 - heartbeat" do
    test "responds to heartbeat" do
      {:ok, state} = TunnelSocket.init([])

      message = Message.heartbeat()

      {:reply, :ok, {:text, response_json}, _state} =
        TunnelSocket.handle_in({Codec.encode!(message), [opcode: :text]}, state)

      response = Codec.decode!(response_json)
      assert response.type == "heartbeat"
    end
  end

  describe "handle_info/2 - forward_request" do
    test "sends tunnel request to client", ctx do
      {:ok, state} = TunnelSocket.init([])

      # Register a tunnel
      reg_message = Message.register_tunnel(ctx.token, "localhost", 3000)

      {:reply, :ok, {:text, reg_response}, state} =
        TunnelSocket.handle_in({Codec.encode!(reg_message), [opcode: :text]}, state)

      reg = Codec.decode!(reg_response)
      tunnel_id = reg.tunnel_id

      # Simulate RequestForwarder sending a request
      request_data = %{
        method: "GET",
        path: "/api/test",
        query_string: "",
        headers: [["host", "test.burrow.test"]],
        body: nil
      }

      request_message = Message.tunnel_request("req-456", tunnel_id, request_data)
      json = Codec.encode!(request_message)

      {:push, {:text, sent_json}, _state} =
        TunnelSocket.handle_info({:forward_request, json}, state)

      sent = Codec.decode!(sent_json)
      assert sent.type == "tunnel_request"
      assert sent.request_id == "req-456"
      assert sent.method == "GET"
      assert sent.path == "/api/test"
    end
  end

  describe "terminate/2" do
    test "unregisters tunnels on disconnect", ctx do
      {:ok, state} = TunnelSocket.init([])

      # Register a tunnel
      reg_message = Message.register_tunnel(ctx.token, "localhost", 3000)

      {:reply, :ok, {:text, reg_response}, state} =
        TunnelSocket.handle_in({Codec.encode!(reg_message), [opcode: :text]}, state)

      reg = Codec.decode!(reg_response)

      # Verify tunnel is registered
      assert {:ok, _} = Burrow.Server.TunnelRegistry.lookup(reg.subdomain)

      # Terminate
      TunnelSocket.terminate(:normal, state)

      # Give time for async unregister
      Process.sleep(50)

      # Tunnel should be unregistered
      assert {:error, :not_found} = Burrow.Server.TunnelRegistry.lookup(reg.subdomain)
    end
  end
end
