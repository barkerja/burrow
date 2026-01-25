defmodule Burrow.Repo.Migrations.CreateUnknownRequestsTable do
  use Ecto.Migration

  def change do
    create table(:unknown_requests, primary_key: false) do
      add :id, :string, size: 26, primary_key: true
      add :subdomain, :string, size: 255, null: false
      add :method, :string, size: 10, null: false
      add :path, :text, null: false
      add :query_string, :text
      add :headers, :jsonb, default: "[]"
      add :client_ip, :string, size: 45
      add :user_agent, :text
      add :referer, :text
      add :ip_info, :jsonb
      add :requested_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:unknown_requests, [:requested_at])
    create index(:unknown_requests, [:subdomain])
    create index(:unknown_requests, [:subdomain, :requested_at])
  end
end
