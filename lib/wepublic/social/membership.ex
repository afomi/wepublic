defmodule Wepublic.Social.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.{Nation, Cohort}

  @tiers ["citizen", "steward", "founder"]
  @max_trust_level 5

  schema "memberships" do
    field :tier, :string, default: "citizen"
    field :role, :string
    field :joined_at, :utc_datetime
    field :trust_level, :integer, default: 1

    belongs_to :user, User
    belongs_to :nation, Nation
    belongs_to :cohort, Cohort
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [
      :tier,
      :role,
      :joined_at,
      :trust_level,
      :user_id,
      :nation_id,
      :cohort_id,
      :invited_by_id
    ])
    |> validate_required([:user_id, :nation_id])
    |> validate_inclusion(:tier, @tiers)
    |> validate_number(:trust_level, greater_than_or_equal_to: 1, less_than_or_equal_to: @max_trust_level)
    |> unique_constraint([:user_id, :nation_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:nation_id)
    |> foreign_key_constraint(:cohort_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  @doc """
  Checks if the member can invite others (trust level 3+).
  """
  def can_invite?(%__MODULE__{trust_level: level}), do: level >= 3

  @doc """
  Checks if the member can propose gatherings (trust level 4+).
  """
  def can_propose_gathering?(%__MODULE__{trust_level: level}), do: level >= 4

  @doc """
  Checks if the member can attend IRL gatherings (trust level 5).
  """
  def can_attend_irl?(%__MODULE__{trust_level: level}), do: level >= 5

  def tiers, do: @tiers
  def max_trust_level, do: @max_trust_level
end
