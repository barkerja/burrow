defmodule Burrow.Queries.UnknownRequestQuery do
  @moduledoc """
  Query builder for unknown request pagination and filtering.

  Uses keyset (cursor-based) pagination for efficient infinite scroll.
  """

  import Ecto.Query

  alias Burrow.Repo
  alias Burrow.Schemas.UnknownRequest

  @default_limit 50

  def list_paginated(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cursor = Keyword.get(opts, :cursor)
    direction = Keyword.get(opts, :direction, :before)

    query =
      UnknownRequest
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

    {Enum.map(requests, &UnknownRequest.to_map/1), has_more?}
  end

  def count(opts \\ []) do
    UnknownRequest
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  def insert(request_map) do
    attrs = %{
      id: request_map.id,
      subdomain: request_map.subdomain,
      method: request_map.method,
      path: request_map.path,
      query_string: Map.get(request_map, :query_string),
      headers: convert_headers(Map.get(request_map, :headers, [])),
      client_ip: Map.get(request_map, :client_ip),
      user_agent: Map.get(request_map, :user_agent),
      referer: Map.get(request_map, :referer),
      ip_info: Map.get(request_map, :ip_info),
      requested_at: request_map.requested_at
    }

    attrs
    |> UnknownRequest.create_changeset()
    |> Repo.insert()
  end

  def update_ip_info(request_id, ip_info) do
    case Repo.get(UnknownRequest, request_id) do
      nil ->
        {:error, :not_found}

      request ->
        request
        |> UnknownRequest.update_changeset(%{ip_info: ip_info})
        |> Repo.update()
    end
  end

  def delete_all do
    Repo.delete_all(UnknownRequest)
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
    |> filter_subdomain(Keyword.get(opts, :subdomain))
  end

  defp filter_method(query, nil), do: query
  defp filter_method(query, ""), do: query
  defp filter_method(query, method), do: where(query, [r], r.method == ^method)

  defp filter_subdomain(query, nil), do: query
  defp filter_subdomain(query, ""), do: query
  defp filter_subdomain(query, subdomain), do: where(query, [r], r.subdomain == ^subdomain)

  defp apply_cursor(query, nil, _direction), do: query

  defp apply_cursor(query, cursor, :before) do
    where(query, [r], r.requested_at < ^cursor)
  end

  defp apply_cursor(query, cursor, :after) do
    where(query, [r], r.requested_at > ^cursor)
  end

  defp order_by_direction(query, :before) do
    order_by(query, [r], desc: r.requested_at)
  end

  defp order_by_direction(query, :after) do
    order_by(query, [r], asc: r.requested_at)
  end
end
