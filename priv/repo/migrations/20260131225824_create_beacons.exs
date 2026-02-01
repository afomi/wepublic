defmodule Wepublic.Repo.Migrations.CreateBeacons do
  use Ecto.Migration

  def change do
    create table(:beacons) do
      add :name, :string, null: false
      add :description, :text
      add :cause, :text
      add :position_x, :float, null: false
      add :position_z, :float, null: false
      add :energy, :float, default: 0.0
      add :intensity, :float, default: 0.1
      add :radius, :float, default: 10.0

      add :nation_id, references(:nations, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:beacons, [:nation_id])
    create index(:beacons, [:creator_id])

    create table(:beacon_presences) do
      add :entered_at, :utc_datetime, null: false
      add :exited_at, :utc_datetime
      add :duration_seconds, :integer, default: 0
      add :energy_contributed, :float, default: 0.0

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :beacon_id, references(:beacons, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:beacon_presences, [:user_id])
    create index(:beacon_presences, [:beacon_id])

    create table(:floating_objects) do
      add :type, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :orbit_radius, :float, default: 5.0
      add :orbit_speed, :float, default: 0.1
      add :orbit_phase, :float, default: 0.0
      add :altitude, :float, default: 3.0
      add :health, :float, default: 1.0
      add :decay_rate, :float, default: 0.01

      add :beacon_id, references(:beacons, on_delete: :delete_all), null: false
      add :creator_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:floating_objects, [:beacon_id])
    create index(:floating_objects, [:type])

    create table(:energy_transactions) do
      add :type, :string, null: false
      add :amount, :float, null: false
      add :description, :string
      add :bsv_txid, :string

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :beacon_id, references(:beacons, on_delete: :nilify_all)
      add :floating_object_id, references(:floating_objects, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:energy_transactions, [:user_id])
    create index(:energy_transactions, [:beacon_id])
    create index(:energy_transactions, [:type])
  end
end
