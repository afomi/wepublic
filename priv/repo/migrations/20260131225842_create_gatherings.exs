defmodule Wepublic.Repo.Migrations.CreateGatherings do
  use Ecto.Migration

  def change do
    create table(:venues) do
      add :name, :string, null: false
      add :address, :string
      add :position_x, :float
      add :position_z, :float
      add :venue_type, :string
      add :safety_rating, :float, default: 3.0
      add :accessibility_notes, :text
      add :verified, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:venues, [:venue_type])
    create index(:venues, [:verified])

    create table(:venue_ratings) do
      add :rating, :integer, null: false
      add :comment, :text
      add :safety_factors, {:array, :string}

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :venue_id, references(:venues, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:venue_ratings, [:venue_id])
    create unique_index(:venue_ratings, [:user_id, :venue_id])

    create table(:gatherings) do
      add :title, :string, null: false
      add :description, :text
      add :scheduled_at, :utc_datetime
      add :max_attendees, :integer
      add :status, :string, default: "proposed"
      add :trust_level_required, :integer, default: 5

      add :venue_id, references(:venues, on_delete: :nilify_all)
      add :organizer_id, references(:users, on_delete: :delete_all), null: false
      add :nation_id, references(:nations, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:gatherings, [:organizer_id])
    create index(:gatherings, [:nation_id])
    create index(:gatherings, [:status])
    create index(:gatherings, [:scheduled_at])

    create table(:gathering_attendees) do
      add :status, :string, default: "interested"
      add :checked_in_at, :utc_datetime
      add :safety_confirmed_at, :utc_datetime

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :gathering_id, references(:gatherings, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:gathering_attendees, [:gathering_id])
    create unique_index(:gathering_attendees, [:user_id, :gathering_id])
  end
end
