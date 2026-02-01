defmodule Wepublic.Social.VenueRating do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.Venue

  @safety_factors [
    "public_visibility",
    "multiple_exits",
    "staff_present",
    "well_lit",
    "accessible",
    "quiet_enough",
    "comfortable_seating"
  ]

  schema "venue_ratings" do
    field :rating, :integer
    field :comment, :string
    field :safety_factors, {:array, :string}

    belongs_to :user, User
    belongs_to :venue, Venue

    timestamps(type: :utc_datetime)
  end

  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [:rating, :comment, :safety_factors, :user_id, :venue_id])
    |> validate_required([:rating, :user_id, :venue_id])
    |> validate_number(:rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_safety_factors()
    |> unique_constraint([:user_id, :venue_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:venue_id)
  end

  defp validate_safety_factors(changeset) do
    factors = get_field(changeset, :safety_factors) || []

    invalid = Enum.reject(factors, &(&1 in @safety_factors))

    if Enum.empty?(invalid) do
      changeset
    else
      add_error(changeset, :safety_factors, "contains invalid factors: #{Enum.join(invalid, ", ")}")
    end
  end

  def safety_factors, do: @safety_factors
end
