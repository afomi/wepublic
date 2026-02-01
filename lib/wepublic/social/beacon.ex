defmodule Wepublic.Social.Beacon do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.{Nation, BeaconPresence, FloatingObject}

  schema "beacons" do
    field :name, :string
    field :description, :string
    field :cause, :string
    field :position_x, :float
    field :position_z, :float
    field :energy, :float, default: 0.0
    field :intensity, :float, default: 0.1
    field :radius, :float, default: 10.0

    belongs_to :nation, Nation
    belongs_to :creator, User
    has_many :presences, BeaconPresence
    has_many :floating_objects, FloatingObject

    timestamps(type: :utc_datetime)
  end

  def changeset(beacon, attrs) do
    beacon
    |> cast(attrs, [
      :name,
      :description,
      :cause,
      :position_x,
      :position_z,
      :energy,
      :intensity,
      :radius,
      :nation_id,
      :creator_id
    ])
    |> validate_required([:name, :position_x, :position_z])
    |> validate_number(:energy, greater_than_or_equal_to: 0)
    |> validate_number(:intensity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:radius, greater_than: 0)
    |> foreign_key_constraint(:nation_id)
    |> foreign_key_constraint(:creator_id)
  end

  @doc """
  Checks if a position is within the beacon's activation radius.
  """
  def in_range?(%__MODULE__{position_x: bx, position_z: bz, radius: r}, x, z) do
    distance = :math.sqrt(:math.pow(x - bx, 2) + :math.pow(z - bz, 2))
    distance <= r
  end

  @doc """
  Adds energy to the beacon and recalculates intensity.
  """
  def add_energy(%__MODULE__{energy: current} = beacon, amount) do
    new_energy = current + amount
    new_intensity = calculate_intensity(new_energy)

    %{beacon | energy: new_energy, intensity: new_intensity}
  end

  # Intensity grows logarithmically with energy, capped at 1.0
  defp calculate_intensity(energy) when energy <= 0, do: 0.1
  defp calculate_intensity(energy) do
    min(1.0, 0.1 + :math.log10(energy + 1) * 0.3)
  end
end
