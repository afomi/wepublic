defmodule Wepublic.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    # Conversation types:
    # - "chat": 1:1 private DM between two connected users
    # - "conversation": n-player open chat, anyone nearby can join
    # - "collaborate": topic-focused conversation with shared context
    create table(:conversations) do
      add :type, :string, null: false, default: "chat"
      add :title, :string
      add :topic, :string
      add :location_id, references(:locations, on_delete: :nilify_all)

      # For collaborate type - shared interests/context
      add :context, :map, default: %{}

      # Visibility: "private" (invite only), "local" (same location), "public"
      add :visibility, :string, default: "private"

      # Position for local conversations (where the conversation is "happening")
      add :position_x, :float
      add :position_z, :float

      # Active status
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:type])
    create index(:conversations, [:location_id])
    create index(:conversations, [:visibility])

    # Participants in conversations
    create table(:conversation_participants) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Role: "owner", "moderator", "participant"
      add :role, :string, default: "participant"

      # Participant status
      add :joined_at, :utc_datetime, null: false
      add :left_at, :utc_datetime
      add :last_read_at, :utc_datetime

      # Muted/notifications
      add :muted, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversation_participants, [:conversation_id, :user_id])
    create index(:conversation_participants, [:user_id])

    # Messages
    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :sender_id, references(:users, on_delete: :nilify_all)

      # Message content
      add :content, :text, null: false
      add :message_type, :string, default: "text"  # "text", "system", "action"

      # For replies/threads
      add :reply_to_id, references(:messages, on_delete: :nilify_all)

      # Metadata for special message types
      add :metadata, :map, default: %{}

      # Soft delete
      add :deleted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:sender_id])
    create index(:messages, [:inserted_at])

    # User capabilities - what interactions a user can initiate/receive
    create table(:user_capabilities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Capability type: "chat", "conversation", "collaborate"
      add :capability, :string, null: false

      # Enabled/disabled
      add :enabled, :boolean, default: true

      # Requirements met (e.g., verification level)
      add :unlocked_at, :utc_datetime

      # Settings for this capability
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_capabilities, [:user_id, :capability])
    create index(:user_capabilities, [:capability])
  end
end
