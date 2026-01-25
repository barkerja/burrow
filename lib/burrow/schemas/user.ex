defmodule Burrow.Schemas.User do
  @moduledoc """
  Ecto schema for user accounts.

  Users are identified by username and authenticate via WebAuthn passkeys.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Burrow.Schemas.{ApiToken, SubdomainReservation, WebAuthnCredential}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "users" do
    field(:username, :string)
    field(:display_name, :string)
    field(:is_admin, :boolean, default: false)

    has_many(:webauthn_credentials, WebAuthnCredential)
    has_many(:api_tokens, ApiToken)
    has_many(:subdomain_reservations, SubdomainReservation)

    timestamps()
  end

  @username_format ~r/^[a-z0-9][a-z0-9_-]{1,30}[a-z0-9]$/

  @doc """
  Creates a changeset for registering a new user.
  """
  @spec registration_changeset(map()) :: Ecto.Changeset.t()
  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username, :display_name])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 32)
    |> validate_format(:username, @username_format,
      message: "must start and end with alphanumeric, only contain a-z, 0-9, -, _"
    )
    |> validate_length(:display_name, max: 255)
    |> unique_constraint(:username)
  end

  @doc """
  Creates a changeset for updating user profile.
  """
  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: 255)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          is_admin: boolean(),
          webauthn_credentials: [WebAuthnCredential.t()] | Ecto.Association.NotLoaded.t(),
          api_tokens: [ApiToken.t()] | Ecto.Association.NotLoaded.t(),
          subdomain_reservations: [SubdomainReservation.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
