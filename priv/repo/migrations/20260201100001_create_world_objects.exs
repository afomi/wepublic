defmodule Wepublic.Repo.Migrations.CreateWorldObjects do
  use Ecto.Migration

  def change do
    create table(:world_objects) do
      add :location_id, references(:locations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :object_type, :string, null: false
      add :position_x, :float, null: false
      add :position_y, :float, default: 0.0
      add :position_z, :float, null: false
      add :label, :string
      add :color, :string, default: "#4a90d9"
      add :model_url, :string
      add :metadata, :map, default: %{}
      add :version, :integer, default: 1
      add :parent_id, references(:world_objects, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:world_objects, [:location_id])
    create index(:world_objects, [:user_id])
    create index(:world_objects, [:parent_id])
    create index(:world_objects, [:object_type])
  end
end
