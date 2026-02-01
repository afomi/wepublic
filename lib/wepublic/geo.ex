defmodule Wepublic.Geo do
  @moduledoc """
  Context module for geographic operations.

  Handles locations (named viewports) and world objects.
  """

  import Ecto.Query
  alias Wepublic.Repo
  alias Wepublic.Geo.{Location, WorldObject}

  # ============================================================================
  # Locations
  # ============================================================================

  @doc """
  Returns all locations.
  """
  def list_locations do
    Repo.all(Location)
  end

  @doc """
  Returns locations of a specific type.
  """
  def list_locations_by_type(type) do
    Location
    |> where([l], l.location_type == ^type)
    |> Repo.all()
  end

  @doc """
  Gets a location by ID.
  """
  def get_location(id), do: Repo.get(Location, id)

  @doc """
  Gets a location by ID, raising if not found.
  """
  def get_location!(id), do: Repo.get!(Location, id)

  @doc """
  Gets a location by slug.
  """
  def get_location_by_slug(slug) do
    Repo.get_by(Location, slug: slug)
  end

  @doc """
  Creates a new location.
  """
  def create_location(attrs) do
    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a location.
  """
  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the cached boundary data for a location.
  """
  def update_location_bounds(%Location{} = location, geojson) do
    location
    |> Location.bounds_changeset(geojson)
    |> Repo.update()
  end

  @doc """
  Deletes a location.
  """
  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  @doc """
  Searches locations by name (case-insensitive partial match).
  """
  def search_locations(query) when is_binary(query) do
    pattern = "%#{query}%"

    Location
    |> where([l], ilike(l.name, ^pattern))
    |> order_by([l], asc: l.name)
    |> limit(10)
    |> Repo.all()
  end

  # ============================================================================
  # World Objects
  # ============================================================================

  @doc """
  Returns all objects at a location (latest versions only).
  """
  def list_objects_at_location(location_id) do
    # Get the latest version of each object chain
    # Objects without a parent_id are the root, objects with parent_id are versions
    latest_versions =
      from(wo in WorldObject,
        where: wo.location_id == ^location_id,
        group_by: fragment("COALESCE(?, ?)", wo.parent_id, wo.id),
        select: max(wo.id)
      )

    from(wo in WorldObject,
      where: wo.id in subquery(latest_versions),
      order_by: [desc: wo.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a world object by ID.
  """
  def get_object(id), do: Repo.get(WorldObject, id)

  @doc """
  Gets a world object by ID, raising if not found.
  """
  def get_object!(id), do: Repo.get!(WorldObject, id)

  @doc """
  Creates a new world object.
  """
  def create_object(attrs) do
    %WorldObject{}
    |> WorldObject.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a world object by creating a new version.
  Returns the new version.
  """
  def update_object(%WorldObject{} = object, attrs) do
    object
    |> WorldObject.new_version(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a world object and all its versions.
  """
  def delete_object(%WorldObject{} = object) do
    # Find the root object ID
    root_id = object.parent_id || object.id

    # Delete all versions including the root
    from(wo in WorldObject,
      where: wo.id == ^root_id or wo.parent_id == ^root_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Gets the version history of an object.
  """
  def get_object_history(object_id) do
    object = get_object!(object_id)
    root_id = object.parent_id || object.id

    from(wo in WorldObject,
      where: wo.id == ^root_id or wo.parent_id == ^root_id,
      order_by: [asc: wo.version]
    )
    |> Repo.all()
  end

  @doc """
  Gets objects within a radius (in meters) of a point.
  Uses simple Euclidean distance on local coordinates.
  """
  def get_objects_near(location_id, x, z, radius_meters) do
    # For local coordinates, we can use simple distance
    from(wo in WorldObject,
      where: wo.location_id == ^location_id,
      where: fragment(
        "SQRT(POW(? - ?, 2) + POW(? - ?, 2)) <= ?",
        wo.position_x, ^x, wo.position_z, ^z, ^radius_meters
      )
    )
    |> Repo.all()
  end

  # ============================================================================
  # User Position
  # ============================================================================

  @doc """
  Updates a user's global position.
  """
  def update_user_position(user, lat, long, location_id \\ nil) do
    attrs = %{position_lat: lat, position_long: long}
    attrs = if location_id, do: Map.put(attrs, :last_location_id, location_id), else: attrs

    user
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end
end
