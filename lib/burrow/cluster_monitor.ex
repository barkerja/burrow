defmodule Burrow.ClusterMonitor do
  @moduledoc """
  Monitors cluster node connections and logs events.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    Logger.info("[Cluster] Monitor started on #{node()}")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("[Cluster] Connected to #{node}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node, _info}, state) do
    Logger.warning("[Cluster] Disconnected from #{node}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
