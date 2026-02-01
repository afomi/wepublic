defmodule Wepublic.Social.Nation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.{Cohort, Membership, Beacon}

  schema "nations" do
    field :name, :string
    field :description, :string
    field :charter, :string
    field :membership_mode, :string, default: "cohort"
    field :center_x, :float, default: 0.0
    field :center_z, :float, default: 0.0
    field :radius, :float, default: 50.0
    field :founded_at, :utc_datetime

    belongs_to :founder, User
    has_many :cohorts, Cohort
    has_many :memberships, Membership
    has_many :beacons, Beacon

    timestamps(type: :utc_datetime)
  end

  def changeset(nation, attrs) do
    nation
    |> cast(attrs, [
      :name,
      :description,
      :charter,
      :membership_mode,
      :center_x,
      :center_z,
      :radius,
      :founded_at,
      :founder_id
    ])
    |> validate_required([:name])
    |> validate_inclusion(:membership_mode, ["cohort", "invitation", "beacon"])
    |> validate_number(:radius, greater_than: 0)
    |> unique_constraint(:name)
  end

  @doc """
  Checks if a position is within the nation's territory.
  """
  def contains_position?(%__MODULE__{center_x: cx, center_z: cz, radius: r}, x, z) do
    distance = :math.sqrt(:math.pow(x - cx, 2) + :math.pow(z - cz, 2))
    distance <= r
  end
end
