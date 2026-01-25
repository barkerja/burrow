defmodule Burrow.Server.WSRegistry do
  @moduledoc """
  Registry for active WebSocket proxy connections.

  Maps ws_id to the WSProxy process handling that connection,
  allowing frame forwarding from tunnel clients to browser connections.

  Handles race conditions by buffering frames that arrive before
  the WSProxy is registered, then delivering them once registered.
  """

  use GenServer

  require Logger

  @table_name :burrow_ws_registry
  @buffer_table :burrow_ws_buffer
  @buffer_ttl_ms 30_000
  @cleanup_interval_ms 10_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a WebSocket proxy process for a ws_id.
  Also delivers any buffered frames that arrived before registration.
  """
  @spec register(String.t(), pid()) :: :ok
  def register(ws_id, pid) do
    GenServer.call(__MODULE__, {:register, ws_id, pid})
  end

  @doc """
  Unregisters a WebSocket proxy.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(ws_id) do
    GenServer.cast(__MODULE__, {:unregister, ws_id})
  end

  @doc """
  Looks up the proxy process for a ws_id.
  """
  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(ws_id) do
    case :ets.lookup(@table_name, ws_id) do
      [{^ws_id, pid}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Forwards a frame to the WSProxy, or buffers it if not yet registered.
  """
  @spec forward_frame(String.t(), atom(), binary()) :: :ok
  def forward_frame(ws_id, opcode, data) do
    case lookup(ws_id) do
      {:ok, proxy_pid} ->
        send(proxy_pid, {:ws_frame, opcode, data})
        :ok

      {:error, :not_found} ->
        # Buffer the frame for later delivery
        GenServer.cast(__MODULE__, {:buffer_frame, ws_id, opcode, data})
        :ok
    end
  end

  @doc """
  Registers a pending WebSocket upgrade request.
  Used to complete the upgrade handshake when client responds.
  """
  @spec register_pending(String.t(), pid()) :: :ok
  def register_pending(ws_id, caller_pid) do
    GenServer.call(__MODULE__, {:register_pending, ws_id, caller_pid})
  end

  @doc """
  Completes a pending WebSocket upgrade with success or error.
  """
  @spec complete_pending(String.t(), {:ok, list()} | {:error, term()}) ::
          :ok | {:error, :not_found}
  def complete_pending(ws_id, result) do
    GenServer.call(__MODULE__, {:complete_pending, ws_id, result})
  end

  # Server callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set])
    pending_table = :ets.new(:burrow_ws_pending, [:named_table, :public, :set])
    # Changed to :ordered_set with {ws_id, timestamp} as key for efficient cleanup
    buffer_table = :ets.new(@buffer_table, [:named_table, :public, :bag])

    # Schedule periodic cleanup of orphaned buffered frames
    Process.send_after(self(), :cleanup_orphaned_buffers, @cleanup_interval_ms)

    {:ok, %{table: table, pending: pending_table, buffer: buffer_table}}
  end

  @impl GenServer
  def handle_call({:register, ws_id, pid}, _from, state) do
    :ets.insert(@table_name, {ws_id, pid})

    # Deliver any buffered frames (new format includes timestamp)
    buffered = :ets.lookup(@buffer_table, ws_id)

    for {^ws_id, opcode, data, _timestamp} <- buffered do
      send(pid, {:ws_frame, opcode, data})
    end

    :ets.delete(@buffer_table, ws_id)

    {:reply, :ok, state}
  end

  def handle_call({:register_pending, ws_id, caller_pid}, _from, state) do
    :ets.insert(:burrow_ws_pending, {ws_id, caller_pid})
    {:reply, :ok, state}
  end

  def handle_call({:complete_pending, ws_id, result}, _from, state) do
    case :ets.lookup(:burrow_ws_pending, ws_id) do
      [{^ws_id, caller_pid}] ->
        send(caller_pid, {:ws_upgrade_result, ws_id, result})
        :ets.delete(:burrow_ws_pending, ws_id)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_cast({:buffer_frame, ws_id, opcode, data}, state) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(@buffer_table, {ws_id, opcode, data, timestamp})
    {:noreply, state}
  end

  def handle_cast({:unregister, ws_id}, state) do
    :ets.delete(@table_name, ws_id)
    :ets.delete(@buffer_table, ws_id)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:cleanup_orphaned_buffers, state) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - @buffer_ttl_ms

    # Phase 1: Collect ws_ids with expired frames
    orphaned_ws_ids =
      :ets.foldl(
        fn {ws_id, _opcode, _data, timestamp}, acc ->
          if timestamp < cutoff, do: MapSet.put(acc, ws_id), else: acc
        end,
        MapSet.new(),
        @buffer_table
      )

    # Phase 2: Delete all frames for collected ws_ids
    Enum.each(orphaned_ws_ids, fn ws_id ->
      :ets.match_delete(@buffer_table, {ws_id, :_, :_, :_})
    end)

    orphaned_count = MapSet.size(orphaned_ws_ids)

    if orphaned_count > 0 do
      Logger.warning("[WSRegistry] Cleaned up #{orphaned_count} orphaned buffered frames")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_orphaned_buffers, @cleanup_interval_ms)

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
