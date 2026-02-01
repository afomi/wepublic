defmodule Wepublic.Repo.Migrations.CreateNations do
  use Ecto.Migration

  def change do
    create table(:nations) do
      add :name, :string, null: false
      add :description, :text
      add :charter, :text
      add :membership_mode, :string, default: "cohort"
      add :center_x, :float, default: 0.0
      add :center_z, :float, default: 0.0
      add :radius, :float, default: 50.0
      add :founded_at, :utc_datetime

      add :founder_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:nations, [:founder_id])
    create unique_index(:nations, [:name])

    create table(:cohorts) do
      add :name, :string, null: false
      add :enrollment_starts, :utc_datetime
      add :enrollment_ends, :utc_datetime
      add :max_members, :integer
      add :status, :string, default: "upcoming"

      add :nation_id, references(:nations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cohorts, [:nation_id])
    create index(:cohorts, [:status])

    create table(:memberships) do
      add :tier, :string, default: "citizen"
      add :role, :string
      add :joined_at, :utc_datetime
      add :trust_level, :integer, default: 1

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :nation_id, references(:nations, on_delete: :delete_all), null: false
      add :cohort_id, references(:cohorts, on_delete: :nilify_all)
      add :invited_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:memberships, [:user_id])
    create index(:memberships, [:nation_id])
    create unique_index(:memberships, [:user_id, :nation_id])

    create table(:invitations) do
      add :token, :string, null: false
      add :status, :string, default: "pending"
      add :expires_at, :utc_datetime
      add :message, :text

      add :inviter_id, references(:users, on_delete: :delete_all), null: false
      add :invitee_id, references(:users, on_delete: :nilify_all)
      add :nation_id, references(:nations, on_delete: :delete_all), null: false
      add :cohort_id, references(:cohorts, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invitations, [:token])
    create index(:invitations, [:inviter_id])
    create index(:invitations, [:nation_id])
  end
end
