defmodule Burrow.Server.RequestStore do
  @moduledoc """
  Stores HTTP request/response data for the request inspector.

  Uses PostgreSQL for persistent storage. Broadcasts updates via PubSub
  for real-time UI updates.
  """

  require Logger

  alias Burrow.Schemas.Request
  alias Burrow.Schemas.UnknownRequest
  alias Burrow.Queries.RequestQuery
  alias Burrow.Queries.UnknownRequestQuery

  @pubsub_topic "request_inspector"
  @max_body_size 64 * 1024

  @doc """
  Logs a new request. Call this when a request arrives.
  """
  def log_request(request_data) do
    data =
      request_data
      |> Map.put_new(:status, nil)
      |> Map.put_new(:response_headers, [])
      |> Map.put_new(:response_body, nil)
      |> Map.put_new(:duration_ms, nil)
      |> Map.put_new(:completed_at, nil)
      |> Map.put_new(:request_size, 0)
      |> Map.put_new(:response_size, nil)
      |> Map.put_new(:client_ip, nil)
      |> Map.put_new(:user_agent, nil)
      |> Map.put_new(:content_type, nil)
      |> Map.put_new(:response_content_type, nil)
      |> Map.put_new(:referer, nil)
      |> Map.put_new(:ip_info, nil)
      |> Map.update(:body, nil, &sanitize_body/1)

    Task.Supervisor.start_child(Burrow.Server.TaskSupervisor, fn ->
      case RequestQuery.insert(data) do
        {:ok, _} ->
          if data.client_ip do
            trigger_ip_lookup(data.id, data.client_ip)
          end

          broadcast_update({:request_logged, data})

        {:error, changeset} ->
          Logger.warning("[RequestStore] Failed to persist request: #{inspect(changeset)}")
      end
    end)
  end

  @doc """
  Updates a request with response data. Call this when the response is ready.
  """
  def log_response(request_id, response_data) do
    # Sanitize body in the calling process to avoid copying large binaries
    sanitized_body = sanitize_body(response_data.body)

    updated_data = %{
      status: response_data.status,
      response_headers: response_data.headers,
      response_body: sanitized_body,
      duration_ms: response_data.duration_ms,
      completed_at: DateTime.utc_now(),
      response_size: response_data[:response_size],
      response_content_type: response_data[:response_content_type]
    }

    Task.Supervisor.start_child(Burrow.Server.TaskSupervisor, fn ->
      case RequestQuery.update_response(request_id, updated_data) do
        {:ok, request} ->
          broadcast_update({:response_logged, Request.to_ets_map(request)})

        {:error, reason} ->
          Logger.warning("[RequestStore] Failed to persist response: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Lists requests with optional filters.

  ## Options
  - `:limit` - Maximum number of requests to return (default: 100)
  - `:method` - Filter by HTTP method
  - `:status` - Filter by status code or list
  - `:path_pattern` - Filter by path regex pattern
  - `:subdomain` - Filter by subdomain
  """
  def list_requests(opts \\ []) do
    {requests, _has_more?} = RequestQuery.list_paginated(opts)
    requests
  end

  @doc """
  Lists requests with cursor-based pagination for infinite scroll.

  Returns `{requests, has_more?}`.

  ## Options
  - `:limit` - Maximum number of requests (default: 50)
  - `:cursor` - DateTime cursor for keyset pagination
  - `:direction` - `:before` (older) or `:after` (newer)
  - `:method` - Filter by HTTP method
  - `:status` - Filter by status code or list
  - `:subdomain` - Filter by subdomain
  - `:path_pattern` - Filter by path regex pattern
  """
  def list_requests_paginated(opts \\ []) do
    RequestQuery.list_paginated(opts)
  end

  @doc """
  Gets a single request by ID.
  """
  def get_request(request_id) do
    RequestQuery.get(request_id)
  end

  @doc """
  Returns the count of stored requests.
  """
  def count do
    RequestQuery.count()
  end

  @doc """
  Clears all stored requests.
  """
  def clear do
    RequestQuery.delete_all()
    broadcast_update(:cleared)
    :ok
  end

  @doc """
  Returns the PubSub topic for request updates.
  """
  def pubsub_topic, do: @pubsub_topic

  @doc """
  Updates a request with IP geolocation info.
  """
  def update_ip_info(request_id, ip_info) do
    case RequestQuery.update_ip_info(request_id, ip_info) do
      {:ok, request} ->
        broadcast_update({:request_updated, Request.to_ets_map(request)})

      {:error, _reason} ->
        :ok
    end
  end

  # Unknown requests (requests to non-existent tunnels)

  @doc """
  Logs a request to a non-existent tunnel.
  """
  def log_unknown_request(request_data) do
    data =
      request_data
      |> Map.put_new(:client_ip, nil)
      |> Map.put_new(:user_agent, nil)
      |> Map.put_new(:referer, nil)
      |> Map.put_new(:ip_info, nil)

    Task.Supervisor.start_child(Burrow.Server.TaskSupervisor, fn ->
      case UnknownRequestQuery.insert(data) do
        {:ok, _} ->
          if data.client_ip do
            trigger_unknown_request_ip_lookup(data.id, data.client_ip)
          end

          broadcast_update({:unknown_request_logged, data})

        {:error, changeset} ->
          Logger.warning(
            "[RequestStore] Failed to persist unknown request: #{inspect(changeset)}"
          )
      end
    end)
  end

  @doc """
  Lists unknown requests with cursor-based pagination.
  """
  def list_unknown_requests_paginated(opts \\ []) do
    UnknownRequestQuery.list_paginated(opts)
  end

  @doc """
  Returns the count of unknown requests.
  """
  def unknown_request_count do
    UnknownRequestQuery.count()
  end

  @doc """
  Clears all unknown requests.
  """
  def clear_unknown_requests do
    UnknownRequestQuery.delete_all()
    broadcast_update(:unknown_requests_cleared)
    :ok
  end

  @doc """
  Updates an unknown request with IP geolocation info.
  """
  def update_unknown_request_ip_info(request_id, ip_info) do
    case UnknownRequestQuery.update_ip_info(request_id, ip_info) do
      {:ok, request} ->
        broadcast_update({:unknown_request_updated, UnknownRequest.to_map(request)})

      {:error, _reason} ->
        :ok
    end
  end

  defp trigger_unknown_request_ip_lookup(request_id, client_ip) do
    %{request_id: request_id, client_ip: client_ip, type: "unknown_request"}
    |> Burrow.Workers.IPLookupWorker.new()
    |> Oban.insert()
  end

  defp sanitize_body(nil), do: nil
  defp sanitize_body(""), do: ""

  defp sanitize_body(body) when is_binary(body) do
    size = byte_size(body)

    cond do
      not String.valid?(body) ->
        "[Binary data: #{format_size(size)}]"

      size > @max_body_size ->
        truncated = binary_part(body, 0, @max_body_size)
        truncated = ensure_valid_utf8(truncated)

        "#{truncated}\n\n[Truncated: showing #{format_size(@max_body_size)} of #{format_size(size)}]"

      true ->
        body
    end
  end

  defp sanitize_body(other), do: inspect(other)

  defp ensure_valid_utf8(binary) do
    case String.chunk(binary, :valid) do
      [] -> ""
      [valid | _] when is_binary(valid) -> valid
      _ -> binary
    end
  rescue
    _ -> binary
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"

  defp trigger_ip_lookup(request_id, client_ip) do
    %{request_id: request_id, client_ip: client_ip, type: "request"}
    |> Burrow.Workers.IPLookupWorker.new()
    |> Oban.insert()
  end

  defp broadcast_update(message) do
    Phoenix.PubSub.broadcast(
      Burrow.PubSub,
      @pubsub_topic,
      {:request_store, message}
    )
  rescue
    _ -> :ok
  end
end
