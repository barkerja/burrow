defmodule Burrow.Server.PendingRequests do
  @moduledoc """
  Tracks in-flight requests waiting for responses from tunnels.

  Provides:
  - Registration of pending requests with caller tracking
  - Completion of requests with response delivery
  - Automatic timeout and cleanup of stale requests
  - Cancellation support for individual requests or all requests for a tunnel
  """

  use GenServer

  @default_timeout_ms 30_000
  @default_cleanup_interval_ms 5_000

  @type pending_request :: %{
          request_id: String.t(),
          caller_pid: pid(),
          caller_ref: reference(),
          tunnel_id: String.t(),
          started_at: integer()
        }

  @type state :: %{
          requests: %{String.t() => pending_request()},
          by_tunnel: %{String.t() => MapSet.t(String.t())},
          timeout_ms: pos_integer()
        }

  # Client API

  @doc """
  Starts the pending requests tracker.

  ## Options

  - `:timeout_ms` - Request timeout in milliseconds (default: 30000)
  - `:cleanup_interval_ms` - How often to check for timeouts (default: 5000)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a new pending request.

  The caller process will be monitored. If it dies, the request is automatically removed.
  """
  @spec register(String.t(), String.t(), pid()) :: :ok
  def register(request_id, tunnel_id, caller_pid) do
    GenServer.call(__MODULE__, {:register, request_id, tunnel_id, caller_pid})
  end

  @doc """
  Completes a pending request by sending the response to the caller.

  ## Returns

  - `:ok` - Response sent successfully
  - `{:error, :not_found}` - Request not found (already completed, cancelled, or timed out)
  """
  @spec complete(String.t(), map() | {:error, atom()}) :: :ok | {:error, :not_found}
  def complete(request_id, response) do
    GenServer.call(__MODULE__, {:complete, request_id, response})
  end

  @doc """
  Cancels a pending request without sending a response.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(request_id) do
    GenServer.cast(__MODULE__, {:cancel, request_id})
  end

  @doc """
  Cancels all pending requests for a specific tunnel.

  Used when a tunnel disconnects.
  """
  @spec cancel_for_tunnel(String.t()) :: :ok
  def cancel_for_tunnel(tunnel_id) do
    GenServer.cast(__MODULE__, {:cancel_for_tunnel, tunnel_id})
  end

  @doc """
  Returns the number of pending requests.
  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    # Schedule periodic cleanup of timed-out requests
    :timer.send_interval(cleanup_interval_ms, :cleanup_timeouts)

    {:ok, %{requests: %{}, by_tunnel: %{}, timeout_ms: timeout_ms}}
  end

  @impl true
  def handle_call({:register, request_id, tunnel_id, caller_pid}, _from, state) do
    caller_ref = Process.monitor(caller_pid)

    pending = %{
      request_id: request_id,
      caller_pid: caller_pid,
      caller_ref: caller_ref,
      tunnel_id: tunnel_id,
      started_at: System.monotonic_time(:millisecond)
    }

    requests = Map.put(state.requests, request_id, pending)

    by_tunnel =
      Map.update(
        state.by_tunnel,
        tunnel_id,
        MapSet.new([request_id]),
        &MapSet.put(&1, request_id)
      )

    {:reply, :ok, %{state | requests: requests, by_tunnel: by_tunnel}}
  end

  @impl true
  def handle_call({:complete, request_id, response}, _from, state) do
    case Map.pop(state.requests, request_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {pending, requests} ->
        Process.demonitor(pending.caller_ref, [:flush])
        send(pending.caller_pid, {:tunnel_response, request_id, response})

        by_tunnel =
          Map.update(
            state.by_tunnel,
            pending.tunnel_id,
            MapSet.new(),
            &MapSet.delete(&1, request_id)
          )

        {:reply, :ok, %{state | requests: requests, by_tunnel: by_tunnel}}
    end
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, map_size(state.requests), state}
  end

  @impl true
  def handle_cast({:cancel, request_id}, state) do
    {:noreply, remove_request(state, request_id)}
  end

  @impl true
  def handle_cast({:cancel_for_tunnel, tunnel_id}, state) do
    request_ids = Map.get(state.by_tunnel, tunnel_id, MapSet.new())
    state = Enum.reduce(request_ids, state, &remove_request(&2, &1))
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_timeouts, state) do
    now = System.monotonic_time(:millisecond)

    {timed_out, remaining} =
      state.requests
      |> Enum.split_with(fn {_, req} ->
        now - req.started_at > state.timeout_ms
      end)

    # Send timeout errors to waiting callers
    Enum.each(timed_out, fn {request_id, pending} ->
      Process.demonitor(pending.caller_ref, [:flush])
      send(pending.caller_pid, {:tunnel_response, request_id, {:error, :timeout}})
    end)

    # Update by_tunnel index
    by_tunnel = remove_request_ids_from_tunnel_index(state.by_tunnel, timed_out)

    {:noreply, %{state | requests: Map.new(remaining), by_tunnel: by_tunnel}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Caller process died, remove their pending request
    {to_remove, remaining} =
      state.requests
      |> Enum.split_with(fn {_, req} -> req.caller_pid == pid end)

    by_tunnel = remove_request_ids_from_tunnel_index(state.by_tunnel, to_remove)

    {:noreply, %{state | requests: Map.new(remaining), by_tunnel: by_tunnel}}
  end

  # Private functions

  defp remove_request(state, request_id) do
    case Map.pop(state.requests, request_id) do
      {nil, _} ->
        state

      {pending, requests} ->
        Process.demonitor(pending.caller_ref, [:flush])

        by_tunnel =
          Map.update(
            state.by_tunnel,
            pending.tunnel_id,
            MapSet.new(),
            &MapSet.delete(&1, request_id)
          )

        %{state | requests: requests, by_tunnel: by_tunnel}
    end
  end

  defp remove_request_ids_from_tunnel_index(by_tunnel, requests_to_remove) do
    Enum.reduce(requests_to_remove, by_tunnel, fn {request_id, pending}, acc ->
      Map.update(acc, pending.tunnel_id, MapSet.new(), &MapSet.delete(&1, request_id))
    end)
  end
end
