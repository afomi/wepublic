defmodule Wepublic.Repo.Migrations.AddKeypairToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Public key for cryptographic identity (Ed25519, 32 bytes)
      # This enables did:key identifiers and signature verification
      add :public_key, :binary

      # did:key derived from public key (e.g., did:key:z6Mk...)
      # Indexed for lookups, unique constraint ensures one user per key
      add :did_key, :string
    end

    # Unique index on did_key - one keypair per user
    create unique_index(:users, [:did_key])

    # Index on public_key for signature verification lookups
    create index(:users, [:public_key])
  end
end
