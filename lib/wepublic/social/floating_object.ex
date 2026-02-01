defmodule Wepublic.Social.FloatingObject do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.Beacon

  @types ["issue", "cause", "space"]

  schema "floating_objects" do
    field :type, :string
    field :title, :string
    field :description, :string
    field :orbit_radius, :float, default: 5.0
    field :orbit_speed, :float, default: 0.1
    field :orbit_phase, :float, default: 0.0
    field :altitude, :float, default: 3.0
    field :health, :float, default: 1.0
    field :decay_rate, :float, default: 0.01

    belongs_to :beacon, Beacon
    belongs_to :creator, User

    timestamps(type: :utc_datetime)
  end

  def changeset(object, attrs) do
    object
    |> cast(attrs, [
      :type,
      :title,
      :description,
      :orbit_radius,
      :orbit_speed,
      :orbit_phase,
      :altitude,
      :health,
      :decay_rate,
      :beacon_id,
      :creator_id
    ])
    |> validate_required([:type, :title, :beacon_id])
    |> validate_inclusion(:type, @types)
    |> validate_number(:orbit_radius, greater_than: 0)
    |> validate_number(:altitude, greater_than: 0)
    |> validate_number(:health, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:decay_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:beacon_id)
    |> foreign_key_constraint(:creator_id)
  end

  @doc """
  Applies decay to the object's health.
  Returns the new health value.
  """
  def apply_decay(%__MODULE__{health: health, decay_rate: rate}, hours \\ 1) do
    max(0.0, health - rate * hours)
  end

  @doc """
  Restores health to the object (from user attention).
  """
  def restore_health(%__MODULE__{health: health}, amount) do
    min(1.0, health + amount)
  end

  @doc """
  Checks if the object is still alive.
  """
  def alive?(%__MODULE__{health: health}), do: health > 0

  def types, do: @types
end
