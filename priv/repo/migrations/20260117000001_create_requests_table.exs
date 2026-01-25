defmodule Burrow.Repo.Migrations.CreateRequestsTable do
  use Ecto.Migration

  def change do
    create table(:requests, primary_key: false) do
      add :id, :string, size: 26, primary_key: true
      add :tunnel_id, :string, size: 255
      add :subdomain, :string, size: 255, null: false
      add :method, :string, size: 10, null: false
      add :path, :text, null: false
      add :query_string, :text
      add :headers, :jsonb, default: "[]"
      add :body, :text
      add :started_at, :utc_datetime_usec, null: false
      add :status, :integer
      add :response_headers, :jsonb, default: "[]"
      add :response_body, :text
      add :duration_ms, :integer
      add :completed_at, :utc_datetime_usec
      add :request_size, :integer, default: 0
      add :response_size, :integer
      add :client_ip, :string, size: 45
      add :user_agent, :text
      add :content_type, :string, size: 255
      add :response_content_type, :string, size: 255
      add :referer, :text
      add :ip_info, :jsonb

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:requests, [:started_at])
    create index(:requests, [:subdomain])
    create index(:requests, [:method])
    create index(:requests, [:status])
    create index(:requests, [:subdomain, :started_at])
  end
end
