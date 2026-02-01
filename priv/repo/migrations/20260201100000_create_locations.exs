defmodule Wepublic.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :center_lat, :float, null: false
      add :center_long, :float, null: false
      add :bounds_geojson, :text
      add :bounds_fetched_at, :utc_datetime
      add :location_type, :string, default: "city"
      add :parent_id, references(:locations, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:locations, [:slug])
    create index(:locations, [:parent_id])
    create index(:locations, [:location_type])
  end
end
