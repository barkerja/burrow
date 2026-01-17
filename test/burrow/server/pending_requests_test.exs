defmodule Burrow.Server.PendingRequestsTest do
  use ExUnit.Case, async: false

  alias Burrow.Server.PendingRequests

  setup do
    start_supervised!({PendingRequests, name: PendingRequests})
    :ok
  end

  describe "register/3" do
    test "registers a pending request" do
      assert :ok = PendingRequests.register("req-1", "tunnel-1", self())
    end

    test "allows multiple requests for same tunnel" do
      assert :ok = PendingRequests.register("req-1", "tunnel-1", self())
      assert :ok = PendingRequests.register("req-2", "tunnel-1", self())
      assert :ok = PendingRequests.register("req-3", "tunnel-1", self())
    end
  end

  describe "complete/2" do
    test "sends response to caller and returns :ok" do
      :ok = PendingRequests.register("req-1", "tunnel-1", self())

      response = %{status: 200, headers: [], body: "OK"}
      assert :ok = PendingRequests.complete("req-1", response)

      assert_receive {:tunnel_response, "req-1", ^response}
    end

    test "returns error for non-existent request" do
      assert {:error, :not_found} = PendingRequests.complete("nonexistent", %{})
    end

    test "removes request after completion" do
      :ok = PendingRequests.register("req-1", "tunnel-1", self())

      PendingRequests.complete("req-1", %{status: 200})
      assert_receive {:tunnel_response, "req-1", _}

      # Second complete should fail
      assert {:error, :not_found} = PendingRequests.complete("req-1", %{})
    end
  end

  describe "cancel/1" do
    test "cancels a pending request" do
      :ok = PendingRequests.register("req-1", "tunnel-1", self())
      :ok = PendingRequests.cancel("req-1")

      # Should no longer be findable
      assert {:error, :not_found} = PendingRequests.complete("req-1", %{})
    end

    test "handles cancelling non-existent request" do
      assert :ok = PendingRequests.cancel("nonexistent")
    end
  end

  describe "cancel_for_tunnel/1" do
    test "cancels all requests for a tunnel" do
      :ok = PendingRequests.register("req-1", "tunnel-1", self())
      :ok = PendingRequests.register("req-2", "tunnel-1", self())
      :ok = PendingRequests.register("req-3", "tunnel-2", self())

      :ok = PendingRequests.cancel_for_tunnel("tunnel-1")

      # tunnel-1 requests should be gone
      assert {:error, :not_found} = PendingRequests.complete("req-1", %{})
      assert {:error, :not_found} = PendingRequests.complete("req-2", %{})

      # tunnel-2 request should still exist
      assert :ok = PendingRequests.complete("req-3", %{status: 200})
      assert_receive {:tunnel_response, "req-3", _}
    end
  end

  describe "count/0" do
    test "returns number of pending requests" do
      assert PendingRequests.count() == 0

      :ok = PendingRequests.register("req-1", "tunnel-1", self())
      assert PendingRequests.count() == 1

      :ok = PendingRequests.register("req-2", "tunnel-1", self())
      assert PendingRequests.count() == 2

      PendingRequests.complete("req-1", %{})
      assert_receive {:tunnel_response, _, _}
      assert PendingRequests.count() == 1
    end
  end

  describe "caller process monitoring" do
    test "removes request when caller dies" do
      test_pid = self()

      spawned =
        spawn(fn ->
          :ok = PendingRequests.register("req-caller", "tunnel-1", self())
          send(test_pid, :registered)

          receive do
            :exit -> :ok
          end
        end)

      assert_receive :registered, 1000

      # Request should exist
      assert PendingRequests.count() >= 1

      # Kill caller
      Process.exit(spawned, :kill)
      Process.sleep(50)

      # Request should be removed
      assert {:error, :not_found} = PendingRequests.complete("req-caller", %{})
    end
  end

  describe "timeout cleanup" do
    @tag timeout: 10_000
    test "times out requests after configured duration" do
      # Start with a shorter timeout for testing
      stop_supervised!(PendingRequests)

      start_supervised!(
        {PendingRequests, name: PendingRequests, timeout_ms: 100, cleanup_interval_ms: 50}
      )

      :ok = PendingRequests.register("req-timeout", "tunnel-1", self())

      # Wait for timeout + cleanup
      Process.sleep(200)

      # Should receive timeout error
      assert_receive {:tunnel_response, "req-timeout", {:error, :timeout}}, 1000

      # Request should be removed
      assert {:error, :not_found} = PendingRequests.complete("req-timeout", %{})
    end
  end
end
