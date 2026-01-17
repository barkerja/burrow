defmodule Burrow.Server.SupervisorTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  describe "child specs" do
    test "TunnelRegistry can be started with custom name" do
      unique_id = :erlang.unique_integer([:positive])
      registry_name = :"test_registry_#{unique_id}"

      {:ok, pid} = Burrow.Server.TunnelRegistry.start_link(name: registry_name)

      # Registry should be accessible via the name
      assert GenServer.call(registry_name, :count) == 0

      GenServer.stop(pid)
    end

    test "PendingRequests can be started with custom name" do
      unique_id = :erlang.unique_integer([:positive])
      pending_name = :"test_pending_#{unique_id}"

      {:ok, pid} = Burrow.Server.PendingRequests.start_link(name: pending_name)

      # PendingRequests should be accessible via the name
      assert GenServer.call(pending_name, :count) == 0

      GenServer.stop(pid)
    end

    test "Supervisor module has correct child_spec" do
      # Verify the supervisor module is properly defined
      Code.ensure_loaded!(Burrow.Server.Supervisor)

      functions = Burrow.Server.Supervisor.__info__(:functions)
      assert {:start_link, 0} in functions or {:start_link, 1} in functions
      assert {:init, 1} in functions
    end
  end
end
