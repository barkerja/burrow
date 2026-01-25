defmodule Burrow.Repo.Migrations.CreateWebauthnCredentialsTable do
  use Ecto.Migration

  def change do
    create table(:webauthn_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key_spki, :binary, null: false
      add :sign_count, :integer, null: false, default: 0
      add :friendly_name, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:user_id])
  end
end
