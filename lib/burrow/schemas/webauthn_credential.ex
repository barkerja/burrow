defmodule Burrow.Schemas.WebAuthnCredential do
  @moduledoc """
  Ecto schema for WebAuthn credentials (passkeys).

  Each user can have multiple credentials for different devices.
  The public key is stored in COSE key format (serialized as binary).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Burrow.Schemas.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  schema "webauthn_credentials" do
    field(:credential_id, :binary)
    field(:public_key_spki, :binary)
    field(:sign_count, :integer, default: 0)
    field(:friendly_name, :string)

    belongs_to(:user, User)

    timestamps()
  end

  @doc """
  Creates a changeset for registering a new WebAuthn credential.

  The `cose_key` in attrs should be the raw COSE key map from Wax.
  It will be serialized to binary for storage.
  """
  @spec create_changeset(Ecto.UUID.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(user_id, attrs) do
    attrs = serialize_cose_key(attrs)

    %__MODULE__{}
    |> cast(attrs, [:credential_id, :public_key_spki, :sign_count, :friendly_name])
    |> put_change(:user_id, user_id)
    |> validate_required([:user_id, :credential_id, :public_key_spki])
    |> validate_number(:sign_count, greater_than_or_equal_to: 0)
    |> validate_length(:friendly_name, max: 255)
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:user_id)
  end

  defp serialize_cose_key(%{cose_key: cose_key} = attrs) when is_map(cose_key) do
    attrs
    |> Map.delete(:cose_key)
    |> Map.put(:public_key_spki, :erlang.term_to_binary(cose_key))
  end

  defp serialize_cose_key(attrs), do: attrs

  @doc """
  Deserializes the stored public key back to COSE key format.
  """
  @spec get_cose_key(t()) :: map() | nil
  def get_cose_key(%__MODULE__{public_key_spki: nil}), do: nil

  def get_cose_key(%__MODULE__{public_key_spki: spki}) do
    :erlang.binary_to_term(spki)
  end

  @doc """
  Creates a changeset for updating the sign count after authentication.
  """
  @spec update_sign_count_changeset(t(), integer()) :: Ecto.Changeset.t()
  def update_sign_count_changeset(credential, new_sign_count) do
    credential
    |> change(sign_count: new_sign_count)
    |> validate_number(:sign_count, greater_than: credential.sign_count)
  end

  @doc """
  Creates a changeset for updating the friendly name.
  """
  @spec update_name_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def update_name_changeset(credential, name) do
    credential
    |> change(friendly_name: name)
    |> validate_length(:friendly_name, max: 255)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          credential_id: binary() | nil,
          public_key_spki: binary() | nil,
          sign_count: integer(),
          friendly_name: String.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
