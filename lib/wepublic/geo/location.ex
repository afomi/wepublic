defmodule Wepublic.Geo.Location do
  @moduledoc """
  Schema for named locations (viewports) in the world.

  Locations are bookmarks to coordinates, not containers.
  They serve as named places users can travel to.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "locations" do
    field :name, :string
    field :slug, :string
    field :center_lat, :float
    field :center_long, :float
    field :bounds_geojson, :string
    field :bounds_fetched_at, :utc_datetime
    field :location_type, :string, default: "city"

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :world_objects, Wepublic.Geo.WorldObject

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :slug, :center_lat, :center_long]
  @optional_fields [:bounds_geojson, :bounds_fetched_at, :location_type, :parent_id]

  @doc """
  Changeset for creating or updating a location.
  """
  def changeset(location, attrs) do
    location
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_latitude(:center_lat)
    |> validate_longitude(:center_long)
    |> validate_inclusion(:location_type, ~w(city county state country neighborhood))
    |> unique_constraint(:slug)
    |> generate_slug()
  end

  defp validate_latitude(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
  end

  defp validate_longitude(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
  end

  defp generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name)
        if name do
          slug = name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")
          put_change(changeset, :slug, slug)
        else
          changeset
        end
      _ ->
        changeset
    end
  end

  @doc """
  Changeset for updating cached boundary data.
  """
  def bounds_changeset(location, geojson) do
    location
    |> change(%{
      bounds_geojson: geojson,
      bounds_fetched_at: DateTime.utc_now(:second)
    })
  end
end
