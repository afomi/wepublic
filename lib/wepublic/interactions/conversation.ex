defmodule Wepublic.Interactions.Conversation do
  @moduledoc """
  Schema for conversations between users.

  Conversation types:
  - "chat": 1:1 private DM between two connected users
  - "conversation": n-player open chat, anyone nearby can join
  - "collaborate": topic-focused conversation with shared context/interests
  """

  use Ecto.Schema
  import Ecto.Changeset

  @conversation_types ~w(chat conversation collaborate)
  @visibility_options ~w(private local public)

  schema "conversations" do
    field :type, :string, default: "chat"
    field :title, :string
    field :topic, :string
    field :context, :map, default: %{}
    field :visibility, :string, default: "private"
    field :position_x, :float
    field :position_z, :float
    field :ended_at, :utc_datetime

    belongs_to :location, Wepublic.Geo.Location
    has_many :participants, Wepublic.Interactions.Participant
    has_many :messages, Wepublic.Interactions.Message
    has_many :users, through: [:participants, :user]

    timestamps(type: :utc_datetime)
  end

  @required_fields [:type]
  @optional_fields [:title, :topic, :context, :visibility, :position_x, :position_z, :location_id, :ended_at]

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @conversation_types)
    |> validate_inclusion(:visibility, @visibility_options)
    |> validate_type_constraints()
  end

  defp validate_type_constraints(changeset) do
    case get_field(changeset, :type) do
      "collaborate" ->
        validate_required(changeset, [:topic])

      _ ->
        changeset
    end
  end

  def end_changeset(conversation) do
    change(conversation, ended_at: DateTime.utc_now(:second))
  end

  def active?(%__MODULE__{ended_at: nil}), do: true
  def active?(_), do: false

  def conversation_types, do: @conversation_types
  def visibility_options, do: @visibility_options
end
