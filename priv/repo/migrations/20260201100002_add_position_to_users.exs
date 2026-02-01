defmodule Wepublic.Repo.Migrations.AddPositionToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :position_lat, :float
      add :position_long, :float
      add :last_location_id, references(:locations, on_delete: :nilify_all)
    end

    create index(:users, [:last_location_id])
  end
end
