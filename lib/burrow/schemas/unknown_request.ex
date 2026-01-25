defmodule Burrow.Schemas.UnknownRequest do
  @moduledoc """
  Ecto schema for requests to non-existent tunnels.

  These are requests that arrived for subdomains without an active tunnel.
  Useful for monitoring access attempts and debugging.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "unknown_requests" do
    field(:subdomain, :string)
    field(:method, :string)
    field(:path, :string)
    field(:query_string, :string)
    field(:headers, {:array, :map}, default: [])
    field(:client_ip, :string)
    field(:user_agent, :string)
    field(:referer, :string)
    field(:ip_info, :map)
    field(:requested_at, :utc_datetime_usec)

    timestamps()
  end

  @required_fields ~w(id subdomain method path requested_at)a
  @optional_fields ~w(query_string headers client_ip user_agent referer ip_info)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:method, max: 10)
    |> validate_length(:subdomain, max: 255)
    |> validate_length(:client_ip, max: 45)
  end

  def update_changeset(request, attrs) do
    request
    |> cast(attrs, [:ip_info])
  end

  def to_map(%__MODULE__{} = request) do
    %{
      id: request.id,
      subdomain: request.subdomain,
      method: request.method,
      path: request.path,
      query_string: request.query_string,
      headers: maps_to_headers(request.headers),
      client_ip: request.client_ip,
      user_agent: request.user_agent,
      referer: request.referer,
      ip_info: request.ip_info,
      requested_at: request.requested_at
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
