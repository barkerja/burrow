defmodule Burrow.Server.RequestStore do
  @moduledoc """
  Stores HTTP request/response data for the request inspector.

  Uses ETS for fast concurrent reads with a ring buffer that
  automatically removes old entries when the max size is exceeded.
  """

  use GenServer

  require Logger

  @table_name :burrow_requests
  @default_max_requests 1000
  @pubsub_topic "request_inspector"
  # Maximum body size to store (64KB) - larger bodies are truncated
  @max_body_size 64 * 1024

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Logs a new request. Call this when a request arrives.
  """
  def log_request(request_data) do
    GenServer.cast(__MODULE__, {:log_request, request_data})
  end

  @doc """
  Updates a request with response data. Call this when the response is ready.
  """
  def log_response(request_id, response_data) do
    GenServer.cast(__MODULE__, {:log_response, request_id, response_data})
  end

  @doc """
  Lists requests with optional filters.

  ## Options
  - `:limit` - Maximum number of requests to return (default: 100)
  - `:offset` - Number of requests to skip (default: 0)
  - `:method` - Filter by HTTP method (e.g., "GET", "POST")
  - `:status` - Filter by status code (e.g., 200, 404)
  - `:path_pattern` - Filter by path regex pattern
  - `:subdomain` - Filter by subdomain
  """
  def list_requests(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.take(opts, [:method, :status, :path_pattern, :subdomain])

    # Get all requests sorted by time (newest first)
    requests =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_id, data} -> data end)
      |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
      |> filter_requests(filters)
      |> Enum.drop(offset)
      |> Enum.take(limit)

    requests
  end

  @doc """
  Gets a single request by ID.
  """
  def get_request(request_id) do
    case :ets.lookup(@table_name, request_id) do
      [{^request_id, data}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns the count of stored requests.
  """
  def count do
    :ets.info(@table_name, :size)
  end

  @doc """
  Clears all stored requests.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @doc """
  Returns the PubSub topic for request updates.
  """
  def pubsub_topic, do: @pubsub_topic

  # Server Callbacks

  @impl true
  def init(opts) do
    max_requests = Keyword.get(opts, :max_requests, @default_max_requests)

    # Create ETS table for concurrent reads
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Track request order for ring buffer
    state = %{
      table: table,
      max_requests: max_requests,
      request_order: :queue.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:log_request, request_data}, state) do
    request_id = request_data.id

    # Ensure required fields with defaults
    data =
      request_data
      |> Map.put_new(:status, nil)
      |> Map.put_new(:response_headers, [])
      |> Map.put_new(:response_body, nil)
      |> Map.put_new(:duration_ms, nil)
      |> Map.put_new(:completed_at, nil)
      # New metrics fields
      |> Map.put_new(:request_size, 0)
      |> Map.put_new(:response_size, nil)
      |> Map.put_new(:client_ip, nil)
      |> Map.put_new(:user_agent, nil)
      |> Map.put_new(:content_type, nil)
      |> Map.put_new(:response_content_type, nil)
      |> Map.put_new(:referer, nil)
      # IP enrichment fields
      |> Map.put_new(:ip_info, nil)
      # Sanitize request body for JSON serialization
      |> Map.update(:body, nil, &sanitize_body/1)

    # Insert into ETS
    :ets.insert(@table_name, {request_id, data})

    # Add to order queue
    new_order = :queue.in(request_id, state.request_order)

    # Enforce ring buffer limit
    new_order = enforce_limit(new_order, state.max_requests)

    # Trigger async IP lookup if we have a client IP
    if data.client_ip do
      trigger_ip_lookup(request_id, data.client_ip)
    end

    # Broadcast update
    broadcast_update({:request_logged, data})

    {:noreply, %{state | request_order: new_order}}
  end

  def handle_cast({:log_response, request_id, response_data}, state) do
    case :ets.lookup(@table_name, request_id) do
      [{^request_id, existing}] ->
        updated =
          existing
          |> Map.put(:status, response_data.status)
          |> Map.put(:response_headers, response_data.headers)
          |> Map.put(:response_body, sanitize_body(response_data.body))
          |> Map.put(:duration_ms, response_data.duration_ms)
          |> Map.put(:completed_at, DateTime.utc_now())
          # New response metrics
          |> Map.put(:response_size, response_data[:response_size])
          |> Map.put(:response_content_type, response_data[:response_content_type])

        :ets.insert(@table_name, {request_id, updated})
        broadcast_update({:response_logged, updated})

      [] ->
        Logger.warning("[RequestStore] Tried to log response for unknown request: #{request_id}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    broadcast_update(:cleared)
    {:reply, :ok, %{state | request_order: :queue.new()}}
  end

  @impl true
  def handle_info({:ip_lookup_result, request_id, ip_info}, state) do
    case :ets.lookup(@table_name, request_id) do
      [{^request_id, existing}] ->
        updated = Map.put(existing, :ip_info, ip_info)
        :ets.insert(@table_name, {request_id, updated})
        broadcast_update({:request_updated, updated})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  # Sanitize body for JSON serialization - binary data can't be JSON encoded
  # Also truncates large bodies to prevent memory bloat
  defp sanitize_body(nil), do: nil
  defp sanitize_body(""), do: ""

  defp sanitize_body(body) when is_binary(body) do
    size = byte_size(body)

    cond do
      # Binary data - show placeholder with size
      not String.valid?(body) ->
        "[Binary data: #{format_size(size)}]"

      # Truncate large bodies
      size > @max_body_size ->
        truncated = binary_part(body, 0, @max_body_size)
        # Ensure we don't cut in the middle of a UTF-8 character
        truncated = ensure_valid_utf8(truncated)
        "#{truncated}\n\n[Truncated: showing #{format_size(@max_body_size)} of #{format_size(size)}]"

      # Valid UTF-8 string within size limit
      true ->
        body
    end
  end

  defp sanitize_body(other), do: inspect(other)

  # Ensure we don't cut in the middle of a multi-byte UTF-8 character
  defp ensure_valid_utf8(binary) do
    case String.chunk(binary, :valid) do
      [] -> ""
      [valid | _] when is_binary(valid) -> valid
      _ -> binary
    end
  rescue
    # If chunking fails, just return as much as we can
    _ -> binary
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"

  defp trigger_ip_lookup(request_id, client_ip) do
    store_pid = self()

    Task.start(fn ->
      case Burrow.Server.IPLookup.lookup_sync(client_ip) do
        {:ok, ip_info} ->
          send(store_pid, {:ip_lookup_result, request_id, ip_info})

        _ ->
          :ok
      end
    end)
  end

  defp enforce_limit(queue, max) do
    if :queue.len(queue) > max do
      {{:value, oldest_id}, new_queue} = :queue.out(queue)
      :ets.delete(@table_name, oldest_id)
      enforce_limit(new_queue, max)
    else
      queue
    end
  end

  defp filter_requests(requests, []), do: requests

  defp filter_requests(requests, filters) do
    Enum.filter(requests, fn req ->
      Enum.all?(filters, fn filter -> matches_filter?(req, filter) end)
    end)
  end

  defp matches_filter?(req, {:method, method}) do
    req.method == method
  end

  defp matches_filter?(req, {:status, status}) when is_integer(status) do
    req.status == status
  end

  defp matches_filter?(req, {:status, status_range}) when is_list(status_range) do
    req.status in status_range
  end

  defp matches_filter?(req, {:path_pattern, pattern}) when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, req.path || "")
      _ -> true
    end
  end

  defp matches_filter?(req, {:subdomain, subdomain}) do
    req.subdomain == subdomain
  end

  defp matches_filter?(_req, _filter), do: true

  defp broadcast_update(message) do
    Phoenix.PubSub.broadcast(
      Burrow.PubSub,
      @pubsub_topic,
      {:request_store, message}
    )
  rescue
    # PubSub might not be started yet
    _ -> :ok
  end
end
