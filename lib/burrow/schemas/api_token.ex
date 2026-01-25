defmodule Burrow.Schemas.ApiToken do
  @moduledoc """
  Ecto schema for API tokens used for tunnel authentication.

  Tokens are stored as hashes and can optionally expire.
  The actual token value is only shown once at creation time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Burrow.Schemas.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @token_prefix "brw_"
  @token_bytes 32

  schema "api_tokens" do
    field(:token_hash, :binary)
    field(:name, :string)
    field(:last_used_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)

    belongs_to(:user, User)

    timestamps()
  end

  @doc """
  Creates a changeset for a new API token.
  """
  @spec create_changeset(Ecto.UUID.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(user_id, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :expires_at, :token_hash])
    |> put_change(:user_id, user_id)
    |> validate_required([:user_id, :name, :token_hash])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Generates a new token string and its hash.

  Returns `{token_string, token_hash}` where the string should be shown
  to the user once, and the hash should be stored in the database.
  """
  @spec generate_token() :: {String.t(), binary()}
  def generate_token do
    raw_token = :crypto.strong_rand_bytes(@token_bytes)
    token_string = @token_prefix <> Base.url_encode64(raw_token, padding: false)
    token_hash = hash_token(token_string)
    {token_string, token_hash}
  end

  @doc """
  Hashes a token string for storage or lookup.
  """
  @spec hash_token(String.t()) :: binary()
  def hash_token(token_string) do
    :crypto.hash(:sha256, token_string)
  end

  @doc """
  Returns the token prefix used for identification.
  """
  @spec token_prefix() :: String.t()
  def token_prefix, do: @token_prefix

  @doc """
  Checks if a token string has the correct format.
  """
  @spec valid_format?(String.t()) :: boolean()
  def valid_format?(token_string) do
    String.starts_with?(token_string, @token_prefix) and
      byte_size(token_string) == byte_size(@token_prefix) + 43
  end

  @doc """
  Updates the last_used_at timestamp.
  """
  @spec touch_changeset(t()) :: Ecto.Changeset.t()
  def touch_changeset(token) do
    change(token, last_used_at: DateTime.utc_now())
  end

  @doc """
  Checks if the token has expired.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          token_hash: binary() | nil,
          name: String.t() | nil,
          last_used_at: DateTime.t() | nil,
          expires_at: DateTime.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }
end
