defmodule Burrow.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, size: 32, null: false
      add :display_name, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:username])
  end
end
