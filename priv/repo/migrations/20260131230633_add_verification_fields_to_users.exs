defmodule Wepublic.Repo.Migrations.AddVerificationFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # DID verification
      add :did_verified_at, :utc_datetime
      add :did_verification_token, :string
      add :did_document_url, :string

      # Feed verification
      add :feed_url, :string
      add :feed_verified_at, :utc_datetime
      add :feed_title, :string
      add :feed_last_fetched_at, :utc_datetime

      # Onboarding state
      add :onboarding_completed_at, :utc_datetime
    end

    create index(:users, [:did_verified_at])
    create index(:users, [:feed_verified_at])
  end
end
