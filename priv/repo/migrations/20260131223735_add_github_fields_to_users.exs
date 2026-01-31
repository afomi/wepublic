defmodule Wepublic.Repo.Migrations.AddGithubFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :github_id, :integer
      add :github_username, :string
      add :github_avatar_url, :string
    end

    create unique_index(:users, [:github_id])
  end
end
