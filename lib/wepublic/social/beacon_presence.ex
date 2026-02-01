defmodule Wepublic.Social.BeaconPresence do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.Beacon

  schema "beacon_presences" do
    field :entered_at, :utc_datetime
    field :exited_at, :utc_datetime
    field :duration_seconds, :integer, default: 0
    field :energy_contributed, :float, default: 0.0

    belongs_to :user, User
    belongs_to :beacon, Beacon

    timestamps(type: :utc_datetime)
  end

  def changeset(presence, attrs) do
    presence
    |> cast(attrs, [
      :entered_at,
      :exited_at,
      :duration_seconds,
      :energy_contributed,
      :user_id,
      :beacon_id
    ])
    |> validate_required([:entered_at, :user_id, :beacon_id])
    |> validate_number(:duration_seconds, greater_than_or_equal_to: 0)
    |> validate_number(:energy_contributed, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:beacon_id)
  end

  @doc """
  Calculates the duration from entered_at to now (or exited_at).
  """
  def calculate_duration(%__MODULE__{entered_at: entered, exited_at: nil}) do
    DateTime.diff(DateTime.utc_now(), entered, :second)
  end

  def calculate_duration(%__MODULE__{entered_at: entered, exited_at: exited}) do
    DateTime.diff(exited, entered, :second)
  end

  @doc """
  Converts presence duration to energy contribution.
  1 minute of presence = 1 energy unit.
  """
  def calculate_energy_contribution(duration_seconds) do
    duration_seconds / 60.0
  end
end
