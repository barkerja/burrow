defmodule Burrow.Server.TunnelRegistryTest do
  use ExUnit.Case, async: false

  alias Burrow.Server.TunnelRegistry

  setup do
    # Use start_supervised! for automatic cleanup
    start_supervised!({TunnelRegistry, name: TunnelRegistry})
    :ok
  end

  describe "register/1" do
    test "registers a new tunnel" do
      params = %{
        tunnel_id: "tid-123",
        subdomain: "myapp",
        client_public_key: <<1, 2, 3>>,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 3000
      }

      assert {:ok, "myapp"} = TunnelRegistry.register(params)
    end

    test "rejects duplicate subdomain" do
      params1 = %{
        tunnel_id: "tid-1",
        subdomain: "taken",
        client_public_key: <<1>>,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 3000
      }

      params2 = %{
        tunnel_id: "tid-2",
        subdomain: "taken",
        client_public_key: <<2>>,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 4000
      }

      assert {:ok, "taken"} = TunnelRegistry.register(params1)
      assert {:error, :subdomain_taken} = TunnelRegistry.register(params2)
    end

    test "allows same client to register multiple subdomains" do
      pk = <<1, 2, 3>>

      params1 = %{
        tunnel_id: "tid-1",
        subdomain: "app1",
        client_public_key: pk,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 3000
      }

      params2 = %{
        tunnel_id: "tid-2",
        subdomain: "app2",
        client_public_key: pk,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 4000
      }

      assert {:ok, "app1"} = TunnelRegistry.register(params1)
      assert {:ok, "app2"} = TunnelRegistry.register(params2)
    end
  end

  describe "lookup/1" do
    test "returns tunnel info for registered subdomain" do
      params = %{
        tunnel_id: "tid-123",
        subdomain: "myapp",
        client_public_key: <<1, 2, 3>>,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 3000
      }

      {:ok, _} = TunnelRegistry.register(params)
      {:ok, info} = TunnelRegistry.lookup("myapp")

      assert info.tunnel_id == "tid-123"
      assert info.subdomain == "myapp"
      assert info.client_public_key == <<1, 2, 3>>
      assert info.connection_pid == self()
      assert info.local_host == "localhost"
      assert info.local_port == 3000
      assert %DateTime{} = info.registered_at
    end

    test "returns error for unregistered subdomain" do
      assert {:error, :not_found} = TunnelRegistry.lookup("nonexistent")
    end
  end

  describe "unregister/1" do
    test "removes tunnel from registry" do
      params = %{
        tunnel_id: "tid-123",
        subdomain: "myapp",
        client_public_key: <<1, 2, 3>>,
        connection_pid: self(),
        stream_ref: make_ref(),
        local_host: "localhost",
        local_port: 3000
      }

      {:ok, _} = TunnelRegistry.register(params)
      assert {:ok, _} = TunnelRegistry.lookup("myapp")

      :ok = TunnelRegistry.unregister("myapp")
      assert {:error, :not_found} = TunnelRegistry.lookup("myapp")
    end

    test "handles unregistering non-existent subdomain" do
      assert :ok = TunnelRegistry.unregister("nonexistent")
    end
  end

  describe "list_by_client/1" do
    test "returns all tunnels for a public key" do
      pk = <<1, 2, 3>>

      for i <- 1..3 do
        params = %{
          tunnel_id: "tid-#{i}",
          subdomain: "app#{i}",
          client_public_key: pk,
          connection_pid: self(),
          stream_ref: make_ref(),
          local_host: "localhost",
          local_port: 3000 + i
        }

        TunnelRegistry.register(params)
      end

      tunnels = TunnelRegistry.list_by_client(pk)
      assert length(tunnels) == 3

      subdomains = Enum.map(tunnels, & &1.subdomain) |> Enum.sort()
      assert subdomains == ["app1", "app2", "app3"]
    end

    test "returns empty list for unknown client" do
      assert TunnelRegistry.list_by_client(<<99, 99, 99>>) == []
    end
  end

  describe "process monitoring" do
    test "removes tunnel when connection process dies" do
      # Spawn a separate process to register the tunnel
      test_pid = self()

      spawned =
        spawn(fn ->
          params = %{
            tunnel_id: "tid-123",
            subdomain: "ephemeral",
            client_public_key: <<1, 2, 3>>,
            connection_pid: self(),
            stream_ref: make_ref(),
            local_host: "localhost",
            local_port: 3000
          }

          {:ok, _} = TunnelRegistry.register(params)
          send(test_pid, :registered)

          receive do
            :exit -> :ok
          end
        end)

      # Wait for registration
      assert_receive :registered, 1000

      # Verify tunnel exists
      assert {:ok, _} = TunnelRegistry.lookup("ephemeral")

      # Kill the spawned process
      Process.exit(spawned, :kill)

      # Give time for the DOWN message to be processed
      Process.sleep(50)

      # Tunnel should be gone
      assert {:error, :not_found} = TunnelRegistry.lookup("ephemeral")
    end
  end

  describe "count/0" do
    test "returns number of registered tunnels" do
      assert TunnelRegistry.count() == 0

      for i <- 1..5 do
        params = %{
          tunnel_id: "tid-#{i}",
          subdomain: "app#{i}",
          client_public_key: <<i>>,
          connection_pid: self(),
          stream_ref: make_ref(),
          local_host: "localhost",
          local_port: 3000 + i
        }

        TunnelRegistry.register(params)
      end

      assert TunnelRegistry.count() == 5
    end
  end
end
