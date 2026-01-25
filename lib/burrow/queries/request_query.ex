defmodule Burrow.Queries.RequestQuery do
  @moduledoc """
  Query builder for request pagination and filtering.

  Uses keyset (cursor-based) pagination for efficient infinite scroll.
  The cursor is the `started_at` timestamp, which provides stable ordering.
  """

  import Ecto.Query

  alias Burrow.Repo
  alias Burrow.Schemas.Request

  @default_limit 50

  @doc """
  Lists requests with cursor-based pagination and optional filters.

  Returns `{requests, has_more?}` where requests are in descending order by started_at.

  ## Options
  - `:limit` - Maximum number of requests (default: 50)
  - `:cursor` - Cursor timestamp for pagination (started_at of last item)
  - `:direction` - `:before` (older) or `:after` (newer) relative to cursor
  - `:method` - Filter by HTTP method
  - `:status` - Filter by status code or list of codes
  - `:subdomain` - Filter by subdomain
  - `:path_pattern` - Filter by path regex pattern
  """
  def list_paginated(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cursor = Keyword.get(opts, :cursor)
    direction = Keyword.get(opts, :direction, :before)

    query =
      Request
      |> apply_filters(opts)
      |> apply_cursor(cursor, direction)
      |> order_by_direction(direction)
      |> limit(^(limit + 1))

    results = Repo.all(query)
    has_more? = length(results) > limit
    requests = Enum.take(results, limit)

    requests =
      if direction == :after do
        Enum.reverse(requests)
      else
        requests
      end

    {Enum.map(requests, &Request.to_ets_map/1), has_more?}
  end

  @doc """
  Gets the total count of requests matching the filters.
  """
  def count(opts \\ []) do
    Request
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets a single request by ID.
  """
  def get(id) do
    case Repo.get(Request, id) do
      nil -> {:error, :not_found}
      request -> {:ok, Request.to_ets_map(request)}
    end
  end

  @doc """
  Inserts a new request.
  """
  def insert(request_map) do
    attrs = Request.from_ets_map(request_map)

    attrs
    |> Request.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Updates a request with response data.
  """
  def update_response(request_id, response_data) do
    case Repo.get(Request, request_id) do
      nil ->
        {:error, :not_found}

      request ->
        attrs = convert_response_attrs(response_data)

        request
        |> Request.update_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates a request with IP geolocation info.
  """
  def update_ip_info(request_id, ip_info) do
    case Repo.get(Request, request_id) do
      nil ->
        {:error, :not_found}

      request ->
        request
        |> Request.update_changeset(%{ip_info: ip_info})
        |> Repo.update()
    end
  end

  @doc """
  Deletes all requests.
  """
  def delete_all do
    Repo.delete_all(Request)
  end

  defp convert_response_attrs(data) when is_map(data) do
    %{
      status: Map.get(data, :status),
      response_headers: convert_headers(Map.get(data, :response_headers, [])),
      response_body: Map.get(data, :response_body),
      duration_ms: Map.get(data, :duration_ms),
      completed_at: Map.get(data, :completed_at),
      response_size: Map.get(data, :response_size),
      response_content_type: Map.get(data, :response_content_type)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp convert_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, value} -> %{"name" => name, "value" => value}
      [name, value] -> %{"name" => name, "value" => value}
      %{"name" => _, "value" => _} = map -> map
      %{} = map -> map
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp convert_headers(_), do: []

  defp apply_filters(query, opts) do
    query
    |> filter_method(Keyword.get(opts, :method))
    |> filter_status(Keyword.get(opts, :status))
    |> filter_subdomain(Keyword.get(opts, :subdomain))
    |> filter_subdomains_in(Keyword.get(opts, :subdomains_in))
    |> filter_path_pattern(Keyword.get(opts, :path_pattern))
  end

  defp filter_method(query, nil), do: query
  defp filter_method(query, ""), do: query
  defp filter_method(query, method), do: where(query, [r], r.method == ^method)

  defp filter_status(query, nil), do: query

  defp filter_status(query, statuses) when is_list(statuses) do
    where(query, [r], r.status in ^statuses)
  end

  defp filter_status(query, status) when is_integer(status) do
    where(query, [r], r.status == ^status)
  end

  defp filter_status(query, _), do: query

  defp filter_subdomain(query, nil), do: query
  defp filter_subdomain(query, ""), do: query
  defp filter_subdomain(query, subdomain), do: where(query, [r], r.subdomain == ^subdomain)

  defp filter_subdomains_in(query, nil), do: query
  defp filter_subdomains_in(query, []), do: where(query, [r], false)
  defp filter_subdomains_in(query, subdomains), do: where(query, [r], r.subdomain in ^subdomains)

  defp filter_path_pattern(query, nil), do: query
  defp filter_path_pattern(query, ""), do: query

  defp filter_path_pattern(query, pattern) do
    where(query, [r], fragment("? ~ ?", r.path, ^pattern))
  end

  defp apply_cursor(query, nil, _direction), do: query

  defp apply_cursor(query, cursor, :before) do
    where(query, [r], r.started_at < ^cursor)
  end

  defp apply_cursor(query, cursor, :after) do
    where(query, [r], r.started_at > ^cursor)
  end

  defp order_by_direction(query, :before) do
    order_by(query, [r], desc: r.started_at)
  end

  defp order_by_direction(query, :after) do
    order_by(query, [r], asc: r.started_at)
  end
end
