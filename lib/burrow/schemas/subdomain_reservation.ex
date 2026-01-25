defmodule Burrow.Schemas.SubdomainReservation do
  @moduledoc """
  Ecto schema for subdomain reservations.

  Each subdomain can only be reserved by one user. Reservations
  are automatically created when a user first uses a subdomain.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Burrow.Schemas.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @subdomain_format ~r/^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$|^[a-z0-9]$/

  schema "subdomain_reservations" do
    field(:subdomain, :string)

    belongs_to(:user, User)

    timestamps()
  end

  @doc """
  Creates a changeset for reserving a new subdomain.
  """
  @spec create_changeset(Ecto.UUID.t(), String.t()) :: Ecto.Changeset.t()
  def create_changeset(user_id, subdomain) do
    %__MODULE__{}
    |> cast(%{subdomain: subdomain}, [:subdomain])
    |> put_change(:user_id, user_id)
    |> validate_required([:user_id, :subdomain])
    |> validate_length(:subdomain, min: 1, max: 63)
    |> validate_format(:subdomain, @subdomain_format,
      message: "must be lowercase alphanumeric with optional hyphens"
    )
    |> validate_not_reserved_keyword()
    |> unique_constraint(:subdomain)
    |> foreign_key_constraint(:user_id)
  end

  @reserved_subdomains ~w(
    www api app admin dashboard auth login logout register
    account settings profile help support docs documentation
    blog mail email ftp ssh ssl ws wss cdn static assets
    inspector tunnel tunnels control status health metrics
  )

  defp validate_not_reserved_keyword(changeset) do
    validate_change(changeset, :subdomain, fn :subdomain, subdomain ->
      if String.downcase(subdomain) in @reserved_subdomains do
        [subdomain: "is a reserved keyword"]
      else
        []
      end
    end)
  end

  @doc """
  Checks if a subdomain string is valid.
  """
  @spec valid_subdomain?(String.t()) :: boolean()
  def valid_subdomain?(subdomain) when is_binary(subdomain) do
    byte_size(subdomain) >= 1 and
      byte_size(subdomain) <= 63 and
      Regex.match?(@subdomain_format, subdomain) and
      String.downcase(subdomain) not in @reserved_subdomains
  end

  def valid_subdomain?(_), do: false

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          subdomain: String.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
