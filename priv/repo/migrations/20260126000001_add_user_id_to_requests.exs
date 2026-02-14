defmodule Burrow.Repo.Migrations.AddUserIdToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :user_id, :binary_id
    end

    create index(:requests, [:user_id])
  end
end
