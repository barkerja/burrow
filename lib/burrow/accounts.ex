defmodule Burrow.Accounts do
  @moduledoc """
  Context module for user accounts, WebAuthn credentials, API tokens,
  and subdomain reservations.
  """

  import Ecto.Query

  alias Burrow.Repo
  alias Burrow.Schemas.{ApiToken, SubdomainReservation, User, WebAuthnCredential}

  # ----------------------------------------------------------------------------
  # Users
  # ----------------------------------------------------------------------------

  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs) do
    attrs
    |> User.registration_changeset()
    |> Repo.insert()
  end

  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id) do
    Repo.get(User, id)
  end

  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(id) do
    Repo.get!(User, id)
  end

  @spec get_user_by_username(String.t()) :: User.t() | nil
  def get_user_by_username(username) do
    Repo.get_by(User, username: String.downcase(username))
  end

  @spec user_exists?(String.t()) :: boolean()
  def user_exists?(username) do
    User
    |> where(username: ^String.downcase(username))
    |> Repo.exists?()
  end

  @spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user(user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  # ----------------------------------------------------------------------------
  # WebAuthn Credentials
  # ----------------------------------------------------------------------------

  @spec create_credential(Ecto.UUID.t(), map()) ::
          {:ok, WebAuthnCredential.t()} | {:error, Ecto.Changeset.t()}
  def create_credential(user_id, attrs) do
    user_id
    |> WebAuthnCredential.create_changeset(attrs)
    |> Repo.insert()
  end

  @spec get_credential(Ecto.UUID.t()) :: WebAuthnCredential.t() | nil
  def get_credential(id) do
    Repo.get(WebAuthnCredential, id)
  end

  @spec get_credential_by_credential_id(binary()) :: WebAuthnCredential.t() | nil
  def get_credential_by_credential_id(credential_id) do
    WebAuthnCredential
    |> where(credential_id: ^credential_id)
    |> preload(:user)
    |> Repo.one()
  end

  @spec list_credentials(Ecto.UUID.t()) :: [WebAuthnCredential.t()]
  def list_credentials(user_id) do
    WebAuthnCredential
    |> where(user_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @spec list_credential_ids(Ecto.UUID.t()) :: [binary()]
  def list_credential_ids(user_id) do
    WebAuthnCredential
    |> where(user_id: ^user_id)
    |> select([c], c.credential_id)
    |> Repo.all()
  end

  @doc """
  Lists credentials in the format required by Wax for authentication.

  Returns a list of `{credential_id, cose_key}` tuples.
  """
  @spec list_credentials_for_auth(Ecto.UUID.t()) :: [{binary(), map()}]
  def list_credentials_for_auth(user_id) do
    user_id
    |> list_credentials()
    |> Enum.map(fn cred ->
      {cred.credential_id, WebAuthnCredential.get_cose_key(cred)}
    end)
  end

  @spec update_credential_sign_count(WebAuthnCredential.t(), integer()) ::
          {:ok, WebAuthnCredential.t()} | {:error, Ecto.Changeset.t()}
  def update_credential_sign_count(credential, new_sign_count) do
    credential
    |> WebAuthnCredential.update_sign_count_changeset(new_sign_count)
    |> Repo.update()
  end

  @spec delete_credential(WebAuthnCredential.t()) ::
          {:ok, WebAuthnCredential.t()} | {:error, Ecto.Changeset.t()}
  def delete_credential(credential) do
    Repo.delete(credential)
  end

  @spec credential_count(Ecto.UUID.t()) :: non_neg_integer()
  def credential_count(user_id) do
    WebAuthnCredential
    |> where(user_id: ^user_id)
    |> Repo.aggregate(:count)
  end

  # ----------------------------------------------------------------------------
  # API Tokens
  # ----------------------------------------------------------------------------

  @spec create_api_token(Ecto.UUID.t(), map()) ::
          {:ok, ApiToken.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create_api_token(user_id, attrs) do
    {token_string, token_hash} = ApiToken.generate_token()

    attrs_with_hash = Map.put(attrs, :token_hash, token_hash)

    case user_id |> ApiToken.create_changeset(attrs_with_hash) |> Repo.insert() do
      {:ok, token} -> {:ok, token, token_string}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec verify_api_token(String.t()) ::
          {:ok, ApiToken.t()} | {:error, :invalid_token | :expired_token}
  def verify_api_token(token_string) do
    unless ApiToken.valid_format?(token_string) do
      {:error, :invalid_token}
    else
      token_hash = ApiToken.hash_token(token_string)

      case Repo.get_by(ApiToken, token_hash: token_hash) |> Repo.preload(:user) do
        nil ->
          {:error, :invalid_token}

        token ->
          if ApiToken.expired?(token) do
            {:error, :expired_token}
          else
            touch_token_last_used(token)
            {:ok, token}
          end
      end
    end
  end

  defp touch_token_last_used(token) do
    token
    |> ApiToken.touch_changeset()
    |> Repo.update()
  end

  @spec get_api_token(Ecto.UUID.t()) :: ApiToken.t() | nil
  def get_api_token(id) do
    Repo.get(ApiToken, id)
  end

  @spec list_api_tokens(Ecto.UUID.t()) :: [ApiToken.t()]
  def list_api_tokens(user_id) do
    ApiToken
    |> where(user_id: ^user_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @spec delete_api_token(ApiToken.t()) :: {:ok, ApiToken.t()} | {:error, Ecto.Changeset.t()}
  def delete_api_token(token) do
    Repo.delete(token)
  end

  @spec delete_api_token_by_id(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ApiToken.t()} | {:error, :not_found}
  def delete_api_token_by_id(user_id, token_id) do
    case Repo.get_by(ApiToken, id: token_id, user_id: user_id) do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  # ----------------------------------------------------------------------------
  # Subdomain Reservations
  # ----------------------------------------------------------------------------

  @spec reserve_subdomain(Ecto.UUID.t(), String.t()) ::
          {:ok, SubdomainReservation.t()} | {:error, Ecto.Changeset.t()}
  def reserve_subdomain(user_id, subdomain) do
    user_id
    |> SubdomainReservation.create_changeset(String.downcase(subdomain))
    |> Repo.insert()
  end

  @spec get_reservation_by_subdomain(String.t()) :: SubdomainReservation.t() | nil
  def get_reservation_by_subdomain(subdomain) do
    SubdomainReservation
    |> where(subdomain: ^String.downcase(subdomain))
    |> preload(:user)
    |> Repo.one()
  end

  @spec check_subdomain_ownership(String.t(), Ecto.UUID.t()) ::
          :owned | :available | :reserved_by_other
  def check_subdomain_ownership(subdomain, user_id) do
    case get_reservation_by_subdomain(subdomain) do
      nil -> :available
      %{user_id: ^user_id} -> :owned
      _ -> :reserved_by_other
    end
  end

  @spec ensure_subdomain_access(String.t(), Ecto.UUID.t()) ::
          {:ok, SubdomainReservation.t()} | {:error, :reserved_by_other | Ecto.Changeset.t()}
  def ensure_subdomain_access(subdomain, user_id) do
    case check_subdomain_ownership(subdomain, user_id) do
      :owned ->
        {:ok, get_reservation_by_subdomain(subdomain)}

      :available ->
        reserve_subdomain(user_id, subdomain)

      :reserved_by_other ->
        {:error, :reserved_by_other}
    end
  end

  @spec list_reservations(Ecto.UUID.t()) :: [SubdomainReservation.t()]
  def list_reservations(user_id) do
    SubdomainReservation
    |> where(user_id: ^user_id)
    |> order_by(asc: :subdomain)
    |> Repo.all()
  end

  @spec list_subdomain_names(Ecto.UUID.t()) :: [String.t()]
  def list_subdomain_names(user_id) do
    SubdomainReservation
    |> where(user_id: ^user_id)
    |> select([r], r.subdomain)
    |> Repo.all()
  end

  @spec release_subdomain(Ecto.UUID.t(), String.t()) ::
          {:ok, SubdomainReservation.t()} | {:error, :not_found | :not_owner}
  def release_subdomain(user_id, subdomain) do
    case get_reservation_by_subdomain(subdomain) do
      nil ->
        {:error, :not_found}

      %{user_id: ^user_id} = reservation ->
        Repo.delete(reservation)

      _ ->
        {:error, :not_owner}
    end
  end

  @spec reservation_count(Ecto.UUID.t()) :: non_neg_integer()
  def reservation_count(user_id) do
    SubdomainReservation
    |> where(user_id: ^user_id)
    |> Repo.aggregate(:count)
  end

  @spec generate_default_subdomain(Ecto.UUID.t()) :: String.t()
  def generate_default_subdomain(user_id) do
    user_id
    |> :erlang.md5()
    |> binary_part(0, 8)
    |> Base.encode16(case: :lower)
  end
end
