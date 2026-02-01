defmodule Wepublic.Interactions.Participant do
  @moduledoc """
  Schema for conversation participants.

  Tracks who is in a conversation, their role, and read status.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner moderator participant)

  schema "conversation_participants" do
    field :role, :string, default: "participant"
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
    field :last_read_at, :utc_datetime
    field :muted, :boolean, default: false

    belongs_to :conversation, Wepublic.Interactions.Conversation
    belongs_to :user, Wepublic.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required_fields [:conversation_id, :user_id, :joined_at]
  @optional_fields [:role, :left_at, :last_read_at, :muted]

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:conversation_id, :user_id])
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:user_id)
  end

  def join_changeset(conversation_id, user_id, role \\ "participant") do
    %__MODULE__{}
    |> changeset(%{
      conversation_id: conversation_id,
      user_id: user_id,
      role: role,
      joined_at: DateTime.utc_now(:second)
    })
  end

  def leave_changeset(participant) do
    change(participant, left_at: DateTime.utc_now(:second))
  end

  def mark_read_changeset(participant) do
    change(participant, last_read_at: DateTime.utc_now(:second))
  end

  def active?(%__MODULE__{left_at: nil}), do: true
  def active?(_), do: false

  def roles, do: @roles
end
