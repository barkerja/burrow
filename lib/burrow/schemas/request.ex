defmodule Burrow.Schemas.Request do
  @moduledoc """
  Ecto schema for persisted HTTP requests.

  This schema mirrors the data stored in ETS by RequestStore,
  enabling PostgreSQL persistence for historical request data.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "requests" do
    field(:tunnel_id, :string)
    field(:subdomain, :string)
    field(:method, :string)
    field(:path, :string)
    field(:query_string, :string)
    field(:headers, {:array, :map}, default: [])
    field(:body, :string)
    field(:started_at, :utc_datetime_usec)
    field(:status, :integer)
    field(:response_headers, {:array, :map}, default: [])
    field(:response_body, :string)
    field(:duration_ms, :integer)
    field(:completed_at, :utc_datetime_usec)
    field(:request_size, :integer, default: 0)
    field(:response_size, :integer)
    field(:client_ip, :string)
    field(:user_agent, :string)
    field(:content_type, :string)
    field(:response_content_type, :string)
    field(:referer, :string)
    field(:ip_info, :map)

    timestamps()
  end

  @required_fields ~w(id subdomain method path started_at)a
  @optional_fields ~w(
    tunnel_id query_string headers body status response_headers response_body
    duration_ms completed_at request_size response_size client_ip user_agent
    content_type response_content_type referer ip_info
  )a

  @doc """
  Creates a changeset for inserting a new request.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:method, max: 10)
    |> validate_length(:subdomain, max: 255)
    |> validate_length(:client_ip, max: 45)
    |> validate_length(:content_type, max: 255)
    |> validate_length(:response_content_type, max: 255)
  end

  @doc """
  Creates a changeset for updating a request with response data.
  """
  def update_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :status,
      :response_headers,
      :response_body,
      :duration_ms,
      :completed_at,
      :response_size,
      :response_content_type,
      :ip_info
    ])
  end

  @doc """
  Converts an ETS request map to schema-compatible attrs.
  """
  def from_ets_map(request_map) when is_map(request_map) do
    %{
      id: request_map.id,
      tunnel_id: Map.get(request_map, :tunnel_id),
      subdomain: request_map.subdomain,
      method: request_map.method,
      path: request_map.path,
      query_string: Map.get(request_map, :query_string),
      headers: headers_to_maps(Map.get(request_map, :headers, [])),
      body: Map.get(request_map, :body),
      started_at: request_map.started_at,
      status: Map.get(request_map, :status),
      response_headers: headers_to_maps(Map.get(request_map, :response_headers, [])),
      response_body: Map.get(request_map, :response_body),
      duration_ms: Map.get(request_map, :duration_ms),
      completed_at: Map.get(request_map, :completed_at),
      request_size: Map.get(request_map, :request_size, 0),
      response_size: Map.get(request_map, :response_size),
      client_ip: Map.get(request_map, :client_ip),
      user_agent: Map.get(request_map, :user_agent),
      content_type: Map.get(request_map, :content_type),
      response_content_type: Map.get(request_map, :response_content_type),
      referer: Map.get(request_map, :referer),
      ip_info: Map.get(request_map, :ip_info)
    }
  end

  defp headers_to_maps(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, value} -> %{"name" => name, "value" => value}
      %{} = map -> map
    end)
  end

  defp headers_to_maps(_), do: []

  @doc """
  Converts a schema struct to the ETS-compatible map format used by LiveView.
  """
  def to_ets_map(%__MODULE__{} = request) do
    %{
      id: request.id,
      tunnel_id: request.tunnel_id,
      subdomain: request.subdomain,
      method: request.method,
      path: request.path,
      query_string: request.query_string,
      headers: maps_to_headers(request.headers),
      body: request.body,
      started_at: request.started_at,
      status: request.status,
      response_headers: maps_to_headers(request.response_headers),
      response_body: request.response_body,
      duration_ms: request.duration_ms,
      completed_at: request.completed_at,
      request_size: request.request_size || 0,
      response_size: request.response_size,
      client_ip: request.client_ip,
      user_agent: request.user_agent,
      content_type: request.content_type,
      response_content_type: request.response_content_type,
      referer: request.referer,
      ip_info: request.ip_info
    }
  end

  defp maps_to_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      %{"name" => name, "value" => value} -> {name, value}
      {_, _} = tuple -> tuple
    end)
  end

  defp maps_to_headers(_), do: []
end
