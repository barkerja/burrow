defmodule Burrow.Repo.Migrations.CreateSubdomainReservationsTable do
  use Ecto.Migration

  def change do
    create table(:subdomain_reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :subdomain, :string, size: 63, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:subdomain_reservations, [:subdomain])
    create index(:subdomain_reservations, [:user_id])
  end
end
