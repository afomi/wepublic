defmodule Wepublic.Geo.WorldObject do
  @moduledoc """
  Schema for objects placed in the world.

  Objects are versioned with "latest is best" - updates create new rows
  with incremented version numbers. Query for latest using MAX(version)
  grouped by parent_id.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @object_types ~w(pin cube model)

  schema "world_objects" do
    field :object_type, :string
    field :position_x, :float
    field :position_y, :float, default: 0.0
    field :position_z, :float
    field :label, :string
    field :color, :string, default: "#4a90d9"
    field :model_url, :string
    field :metadata, :map, default: %{}
    field :version, :integer, default: 1

    belongs_to :location, Wepublic.Geo.Location
    belongs_to :user, Wepublic.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :versions, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @required_fields [:location_id, :object_type, :position_x, :position_z]
  @optional_fields [:user_id, :position_y, :label, :color, :model_url, :metadata, :version, :parent_id]

  @doc """
  Changeset for creating a new world object.
  """
  def changeset(world_object, attrs) do
    world_object
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:object_type, @object_types)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color")
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a new version of this object with updated attributes.
  Returns a changeset for a new record with incremented version.
  """
  def new_version(original, attrs) do
    parent_id = original.parent_id || original.id

    %__MODULE__{}
    |> changeset(Map.merge(%{
      location_id: original.location_id,
      user_id: original.user_id,
      object_type: original.object_type,
      position_x: original.position_x,
      position_y: original.position_y,
      position_z: original.position_z,
      label: original.label,
      color: original.color,
      model_url: original.model_url,
      metadata: original.metadata,
      version: original.version + 1,
      parent_id: parent_id
    }, attrs))
  end

  @doc """
  Returns the list of valid object types.
  """
  def object_types, do: @object_types
end
