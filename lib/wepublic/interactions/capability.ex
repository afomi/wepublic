defmodule Wepublic.Interactions.Capability do
  @moduledoc """
  Schema for user capabilities - what interactions a user can initiate/receive.

  Capabilities:
  - "chat": Can send/receive 1:1 DMs (requires connection)
  - "conversation": Can join/start group conversations
  - "collaborate": Can participate in topic-focused collaborations

  Capabilities can be unlocked based on verification level, account age, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @capabilities ~w(chat conversation collaborate)

  schema "user_capabilities" do
    field :capability, :string
    field :enabled, :boolean, default: true
    field :unlocked_at, :utc_datetime
    field :settings, :map, default: %{}

    belongs_to :user, Wepublic.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @required_fields [:user_id, :capability]
  @optional_fields [:enabled, :unlocked_at, :settings]

  def changeset(cap, attrs) do
    cap
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:capability, @capabilities)
    |> unique_constraint([:user_id, :capability])
    |> foreign_key_constraint(:user_id)
  end

  def unlock_changeset(cap) do
    change(cap, unlocked_at: DateTime.utc_now(:second), enabled: true)
  end

  def toggle_changeset(cap, enabled) do
    change(cap, enabled: enabled)
  end

  def update_settings_changeset(cap, settings) do
    change(cap, settings: Map.merge(cap.settings || %{}, settings))
  end

  def unlocked?(%__MODULE__{unlocked_at: nil}), do: false
  def unlocked?(%__MODULE__{enabled: false}), do: false
  def unlocked?(_), do: true

  def capabilities, do: @capabilities

  @doc """
  Returns the minimum verification level required for each capability.
  """
  def required_verification_level("chat"), do: 0      # Anyone can chat with connections
  def required_verification_level("conversation"), do: 0  # Anyone can join conversations
  def required_verification_level("collaborate"), do: 1   # Need at least 1 verification for collaborate
  def required_verification_level(_), do: 0
end
