defmodule Wepublic.Social.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Social.{Gathering, VenueRating}

  @venue_types ["cafe", "park", "library", "coworking", "community_center", "other"]

  schema "venues" do
    field :name, :string
    field :address, :string
    field :position_x, :float
    field :position_z, :float
    field :venue_type, :string
    field :safety_rating, :float, default: 3.0
    field :accessibility_notes, :string
    field :verified, :boolean, default: false

    has_many :gatherings, Gathering
    has_many :ratings, VenueRating

    timestamps(type: :utc_datetime)
  end

  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [
      :name,
      :address,
      :position_x,
      :position_z,
      :venue_type,
      :safety_rating,
      :accessibility_notes,
      :verified
    ])
    |> validate_required([:name])
    |> validate_inclusion(:venue_type, @venue_types)
    |> validate_number(:safety_rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end

  @doc """
  Recalculates safety rating from all ratings.
  """
  def recalculate_safety_rating(%__MODULE__{ratings: ratings}) when is_list(ratings) do
    if Enum.empty?(ratings) do
      3.0
    else
      ratings
      |> Enum.map(& &1.rating)
      |> Enum.sum()
      |> Kernel./(length(ratings))
    end
  end

  def venue_types, do: @venue_types
end
