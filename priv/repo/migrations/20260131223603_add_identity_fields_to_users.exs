defmodule Wepublic.Repo.Migrations.AddIdentityFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :did, :string
      add :website, :string
      add :display_name, :string
      add :avatar_color, :string, default: "#4a90d9"
    end

    create unique_index(:users, [:did])
  end
end
