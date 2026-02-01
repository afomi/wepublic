defmodule Wepublic.Interactions.Message do
  @moduledoc """
  Schema for messages within conversations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @message_types ~w(text system action)

  schema "messages" do
    field :content, :string
    field :message_type, :string, default: "text"
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime

    belongs_to :conversation, Wepublic.Interactions.Conversation
    belongs_to :sender, Wepublic.Accounts.User
    belongs_to :reply_to, __MODULE__

    has_many :replies, __MODULE__, foreign_key: :reply_to_id

    timestamps(type: :utc_datetime)
  end

  @required_fields [:conversation_id, :content]
  @optional_fields [:sender_id, :message_type, :metadata, :reply_to_id, :deleted_at]

  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:message_type, @message_types)
    |> validate_length(:content, min: 1, max: 4000)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:sender_id)
  end

  def system_message_changeset(conversation_id, content, metadata \\ %{}) do
    %__MODULE__{}
    |> changeset(%{
      conversation_id: conversation_id,
      content: content,
      message_type: "system",
      metadata: metadata
    })
  end

  def delete_changeset(message) do
    change(message, deleted_at: DateTime.utc_now(:second))
  end

  def deleted?(%__MODULE__{deleted_at: nil}), do: false
  def deleted?(_), do: true

  def message_types, do: @message_types
end
