defmodule Wepublic.Repo.Migrations.CreateUserConnections do
  use Ecto.Migration

  def change do
    create table(:user_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :connected_user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:user_connections, [:user_id])
    create index(:user_connections, [:connected_user_id])
    create unique_index(:user_connections, [:user_id, :connected_user_id])
  end
end
