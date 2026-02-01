defmodule Wepublic.MapWorld do
  @moduledoc """
  GenServer that manages the canonical state of the 3D map world.

  Responsibilities:
  - Track all entity positions (users, NPCs, beacons)
  - Assign spawn positions for new users
  - Process movement intents
  - Handle travel between locations
  - Manage world objects
  - Broadcast state updates to subscribers

  Clients send intents, server owns state.
  """

  use GenServer

  alias Phoenix.PubSub
  alias Wepublic.Geo

  @pubsub Wepublic.PubSub
  @topic "map_world"

  # Spawn positions spread around the map (local coordinates)
  @spawn_positions [
    {0, 0},
    {5, 5},
    {-5, 5},
    {5, -5},
    {-5, -5},
    {10, 0},
    {-10, 0},
    {0, 10},
    {0, -10},
    {15, 15},
    {-15, 15},
    {15, -15},
    {-15, -15}
  ]

  # Movement speed in units per tick
  @move_speed 0.5

  # Tick interval for processing movement
  @tick_interval 50

  # Default location (Vacaville, CA)
  @default_location_slug "vacaville-ca"

  # Visibility radius in meters
  @visibility_radius 100.0

  # Meters per degree (approximate at mid-latitudes)
  @meters_per_degree_lat 111_320.0
  @meters_per_degree_long 85_000.0  # Approximate for ~38° latitude

  # State structure
  defstruct entities: %{},
            spawn_index: 0,
            movement_targets: %{},
            world_objects: %{},
            current_location: nil

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Join the world. Returns the assigned entity state.
  """
  def join(user_id, meta \\ %{}) do
    GenServer.call(__MODULE__, {:join, user_id, meta})
  end

  @doc """
  Leave the world.
  """
  def leave(user_id) do
    GenServer.cast(__MODULE__, {:leave, user_id})
  end

  @doc """
  Request to move in a direction. Direction is :up, :down, :left, :right, or {:to, x, z}.
  """
  def move(user_id, direction) do
    GenServer.cast(__MODULE__, {:move, user_id, direction})
  end

  @doc """
  Get all entities in the world.
  """
  def get_entities do
    GenServer.call(__MODULE__, :get_entities)
  end

  @doc """
  Get entities at a specific location.
  """
  def get_entities_at_location(location_id) do
    GenServer.call(__MODULE__, {:get_entities_at_location, location_id})
  end

  @doc """
  Get a specific entity.
  """
  def get_entity(user_id) do
    GenServer.call(__MODULE__, {:get_entity, user_id})
  end

  @doc """
  Subscribe to world updates. Receives {:world_update, entities} messages.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Unsubscribe from world updates.
  """
  def unsubscribe do
    PubSub.unsubscribe(@pubsub, @topic)
  end

  @doc """
  Travel to a location. Teleports the user to the location's center.
  Returns {:ok, location} on success.
  """
  def travel(user_id, location_id) do
    GenServer.call(__MODULE__, {:travel, user_id, location_id})
  end

  @doc """
  Get the current location for the world.
  """
  def get_current_location do
    GenServer.call(__MODULE__, :get_current_location)
  end

  @doc """
  Get entities near a position within the visibility radius.
  """
  def get_nearby_entities(x, z, radius \\ @visibility_radius) do
    GenServer.call(__MODULE__, {:get_nearby_entities, x, z, radius})
  end

  @doc """
  Place a world object at the current location.
  """
  def place_object(user_id, attrs) do
    GenServer.call(__MODULE__, {:place_object, user_id, attrs})
  end

  @doc """
  Get all world objects at the current location.
  """
  def get_objects do
    GenServer.call(__MODULE__, :get_objects)
  end

  @doc """
  Update a world object (creates new version).
  """
  def update_object(object_id, attrs) do
    GenServer.call(__MODULE__, {:update_object, object_id, attrs})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Load default location
    current_location = Geo.get_location_by_slug(@default_location_slug)

    # Base coordinates (Vacaville default or from location)
    {base_lat, base_long} = case current_location do
      nil -> {38.3566, -121.9877}
      loc -> {loc.center_lat, loc.center_long}
    end

    # Get location_id for NPCs
    vacaville_id = current_location && current_location.id

    # Initialize with demo NPCs at fixed positions (scene coords are meters from center)
    # NPCs are placed near Vacaville's center
    npcs = %{
      "npc_alice" => %{
        id: "npc_alice",
        type: :npc,
        name: "Alice",
        display_name: "Alice",
        color: "#d94a8a",
        position: %{x: 8.0, z: 5.0},
        lat: base_lat + (5.0 / @meters_per_degree_lat),
        long: base_long + (8.0 / @meters_per_degree_long),
        location_id: vacaville_id,
        verification_level: 2,
        has_products: true
      },
      "npc_bob" => %{
        id: "npc_bob",
        type: :npc,
        name: "Bob",
        display_name: "Bob",
        color: "#8ad94a",
        position: %{x: 15.0, z: -8.0},
        lat: base_lat + (-8.0 / @meters_per_degree_lat),
        long: base_long + (15.0 / @meters_per_degree_long),
        location_id: vacaville_id,
        verification_level: 1,
        has_products: false
      },
      "npc_carol" => %{
        id: "npc_carol",
        type: :npc,
        name: "Carol",
        display_name: "Carol",
        color: "#d9a84a",
        position: %{x: -12.0, z: 10.0},
        lat: base_lat + (10.0 / @meters_per_degree_lat),
        long: base_long + (-12.0 / @meters_per_degree_long),
        location_id: vacaville_id,
        verification_level: 0,
        has_products: false
      }
    }

    # Load world objects for the current location
    world_objects = load_world_objects(current_location)

    # Start the movement tick
    schedule_tick()

    {:ok, %__MODULE__{
      entities: npcs,
      spawn_index: 0,
      movement_targets: %{},
      current_location: current_location,
      world_objects: world_objects
    }}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval)
  end

  @impl true
  def handle_call({:join, user_id, meta}, _from, state) do
    require Logger

    if Map.has_key?(state.entities, user_id) do
      # Already joined, return existing entity
      Logger.warning("JOIN: #{user_id} already exists")
      {:reply, {:ok, state.entities[user_id]}, state}
    else
      Logger.warning("JOIN: #{user_id} with meta=#{inspect(meta)}")

      # Try to load user's saved location from database
      {spawn_location, saved_lat, saved_long} = load_user_saved_location(user_id, state.current_location)

      # Assign spawn position offset (meters from location center)
      {offset_x, offset_z} = Enum.at(@spawn_positions, rem(state.spawn_index, length(@spawn_positions)))

      # Use saved position or calculate from location center
      {lat, long, location_id} = case {saved_lat, saved_long, spawn_location} do
        {lat, long, loc} when not is_nil(lat) and not is_nil(long) and not is_nil(loc) ->
          # User has saved position - use it
          {lat, long, loc.id}
        _ ->
          # No saved position - spawn at default location
          {base_lat, base_long} = case spawn_location do
            nil -> {38.3566, -121.9877}  # Vacaville default
            loc -> {loc.center_lat, loc.center_long}
          end
          loc_id = spawn_location && spawn_location.id
          {
            base_lat + (offset_z / @meters_per_degree_lat),
            base_long + (offset_x / @meters_per_degree_long),
            loc_id
          }
      end

      # Calculate scene position relative to their location center
      {scene_x, scene_z} = case spawn_location do
        nil -> {offset_x * 1.0, offset_z * 1.0}
        loc ->
          {
            (long - loc.center_long) * @meters_per_degree_long,
            (lat - loc.center_lat) * @meters_per_degree_lat
          }
      end

      entity = %{
        id: user_id,
        type: :user,
        name: meta[:name] || meta[:display_name] || "Anonymous",
        display_name: meta[:display_name] || meta[:name] || "Anonymous",
        color: meta[:color] || meta[:avatar_color] || random_color(),
        position: %{x: scene_x, z: scene_z},
        lat: lat,
        long: long,
        location_id: location_id,
        verification_level: meta[:verification_level] || 0,
        has_products: meta[:has_products] || false,
        connections: meta[:connections] || []
      }

      new_entities = Map.put(state.entities, user_id, entity)
      new_state = %{state | entities: new_entities, spawn_index: state.spawn_index + 1}

      Logger.warning("JOIN: #{user_id} at lat/long #{lat}, #{long}, total entities: #{map_size(new_entities)}")

      broadcast_update(new_entities)

      {:reply, {:ok, entity}, new_state}
    end
  end

  @impl true
  def handle_call(:get_entities, _from, state) do
    {:reply, state.entities, state}
  end

  @impl true
  def handle_call({:get_entities_at_location, location_id}, _from, state) do
    entities_at_location = state.entities
    |> Enum.filter(fn {_id, ent} -> ent[:location_id] == location_id end)
    |> Map.new()
    {:reply, entities_at_location, state}
  end

  @impl true
  def handle_call({:get_entity, user_id}, _from, state) do
    {:reply, Map.get(state.entities, user_id), state}
  end

  @impl true
  def handle_call(:get_current_location, _from, state) do
    {:reply, state.current_location, state}
  end

  @impl true
  def handle_call({:get_nearby_entities, x, z, radius}, _from, state) do
    nearby = state.entities
    |> Map.values()
    |> Enum.filter(fn entity ->
      dx = entity.position.x - x
      dz = entity.position.z - z
      :math.sqrt(dx * dx + dz * dz) <= radius
    end)

    {:reply, nearby, state}
  end

  @impl true
  def handle_call({:travel, user_id, location_id}, _from, state) do
    require Logger

    case Geo.get_location(location_id) do
      nil ->
        {:reply, {:error, :location_not_found}, state}

      location ->
        Logger.warning("TRAVEL: #{user_id} traveling to #{location.name} (#{location.center_lat}, #{location.center_long})")

        # Update user's position to spawn at location center
        case Map.get(state.entities, user_id) do
          nil ->
            {:reply, {:error, :user_not_found}, state}

          entity ->
            old_location_id = entity[:location_id]

            # User moves to the destination's lat/long (with small offset for variety)
            {offset_x, offset_z} = Enum.at(@spawn_positions, rem(state.spawn_index, length(@spawn_positions)))
            new_lat = location.center_lat + (offset_z / @meters_per_degree_lat)
            new_long = location.center_long + (offset_x / @meters_per_degree_long)

            # Persist location to database for real users
            persist_user_location(user_id, new_lat, new_long, location.id)

            # Update only the traveling user's entity
            updated_entity = %{entity |
              lat: new_lat,
              long: new_long,
              position: %{x: offset_x * 1.0, z: offset_z * 1.0},
              location_id: location.id
            }
            new_entities = Map.put(state.entities, user_id, updated_entity)

            new_state = %{state |
              entities: new_entities,
              movement_targets: Map.delete(state.movement_targets, user_id),
              spawn_index: state.spawn_index + 1
            }

            # Broadcast that this user traveled (others see them disappear/appear)
            broadcast_user_traveled(user_id, old_location_id, location.id)

            {:reply, {:ok, location}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:place_object, user_id, attrs}, _from, state) do
    require Logger
    Logger.warning("PLACE_OBJECT: user=#{user_id}, current_location=#{inspect(state.current_location && state.current_location.id)}, attrs=#{inspect(attrs)}")

    case state.current_location do
      nil ->
        Logger.error("PLACE_OBJECT failed: no current location set")
        {:reply, {:error, :no_location}, state}

      location ->
        # Extract user's numeric ID if possible
        db_user_id = case user_id do
          "user_" <> id -> String.to_integer(id)
          _ -> nil
        end

        object_attrs = attrs
        |> Map.put(:location_id, location.id)
        |> Map.put(:user_id, db_user_id)

        case Geo.create_object(object_attrs) do
          {:ok, object} ->
            Logger.warning("PLACE_OBJECT: #{user_id} placed #{object.object_type} at (#{object.position_x}, #{object.position_z})")

            # Update in-memory world objects
            new_objects = Map.put(state.world_objects, object.id, object)
            new_state = %{state | world_objects: new_objects}

            # Broadcast object placement
            broadcast_object_placed(object)

            {:reply, {:ok, object}, new_state}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end
    end
  end

  @impl true
  def handle_call(:get_objects, _from, state) do
    {:reply, Map.values(state.world_objects), state}
  end

  @impl true
  def handle_call({:update_object, object_id, attrs}, _from, state) do
    case Map.get(state.world_objects, object_id) do
      nil ->
        {:reply, {:error, :object_not_found}, state}

      object ->
        case Geo.update_object(object, attrs) do
          {:ok, new_object} ->
            # Replace old version with new in memory
            new_objects = state.world_objects
            |> Map.delete(object_id)
            |> Map.put(new_object.id, new_object)

            new_state = %{state | world_objects: new_objects}
            broadcast_object_updated(new_object)

            {:reply, {:ok, new_object}, new_state}

          {:error, changeset} ->
            {:reply, {:error, changeset}, state}
        end
    end
  end

  @impl true
  def handle_cast({:leave, user_id}, state) do
    # Only remove users, not NPCs
    entity = Map.get(state.entities, user_id)

    if entity && entity.type == :user do
      new_entities = Map.delete(state.entities, user_id)
      broadcast_update(new_entities)
      {:noreply, %{state | entities: new_entities}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:move, user_id, direction}, state) do
    require Logger

    case Map.get(state.entities, user_id) do
      nil ->
        Logger.warning("MOVE: #{user_id} NOT FOUND in entities: #{inspect(Map.keys(state.entities))}")
        {:noreply, state}

      entity ->
        # Get current location center for lat/long calculations
        {center_lat, center_long} = case state.current_location do
          nil -> {38.3566, -121.9877}
          loc -> {loc.center_lat, loc.center_long}
        end

        case direction do
          {:to, target_x, target_z} ->
            # Set movement target - will be processed by tick
            Logger.warning("MOVE_TO: #{user_id} targeting #{target_x}, #{target_z}")
            new_targets = Map.put(state.movement_targets, user_id, %{x: target_x, z: target_z})
            {:noreply, %{state | movement_targets: new_targets}}

          dir when dir in [:up, :down, :left, :right] ->
            # Immediate directional movement - clear any target
            new_position = calculate_new_position(entity.position, direction)
            # Update lat/long based on new scene position
            new_lat = center_lat + (new_position.z / @meters_per_degree_lat)
            new_long = center_long + (new_position.x / @meters_per_degree_long)
            updated_entity = %{entity | position: new_position, lat: new_lat, long: new_long}
            new_entities = Map.put(state.entities, user_id, updated_entity)
            new_targets = Map.delete(state.movement_targets, user_id)

            Logger.warning("MOVE: #{user_id} #{dir} -> #{inspect(new_position)}")
            broadcast_position_update(user_id, new_position)

            {:noreply, %{state | entities: new_entities, movement_targets: new_targets}}

          _ ->
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:tick, state) do
    # Get current location center for lat/long calculations
    {center_lat, center_long} = case state.current_location do
      nil -> {38.3566, -121.9877}
      loc -> {loc.center_lat, loc.center_long}
    end

    # Process all movement targets
    {new_entities, new_targets, updates} =
      Enum.reduce(state.movement_targets, {state.entities, state.movement_targets, []}, fn
        {user_id, target}, {entities, targets, updates} ->
          case Map.get(entities, user_id) do
            nil ->
              # User left, remove target
              {entities, Map.delete(targets, user_id), updates}

            entity ->
              dx = target.x - entity.position.x
              dz = target.z - entity.position.z
              dist = :math.sqrt(dx * dx + dz * dz)

              if dist < 0.3 do
                # Arrived at target
                {entities, Map.delete(targets, user_id), updates}
              else
                # Move towards target
                ratio = min(@move_speed / dist, 1.0)
                new_position = %{
                  x: entity.position.x + dx * ratio,
                  z: entity.position.z + dz * ratio
                }
                # Update lat/long based on new scene position
                new_lat = center_lat + (new_position.z / @meters_per_degree_lat)
                new_long = center_long + (new_position.x / @meters_per_degree_long)
                updated_entity = %{entity | position: new_position, lat: new_lat, long: new_long}
                new_entities = Map.put(entities, user_id, updated_entity)

                {new_entities, targets, [{user_id, new_position} | updates]}
              end
          end
      end)

    # Broadcast all position updates
    Enum.each(updates, fn {user_id, position} ->
      broadcast_position_update(user_id, position)
    end)

    # Schedule next tick
    schedule_tick()

    {:noreply, %{state | entities: new_entities, movement_targets: new_targets}}
  end

  ## Private Functions

  defp calculate_new_position(position, direction) do
    %{x: x, z: z} = position

    case direction do
      :up ->
        %{x: x - @move_speed, z: z - @move_speed}

      :down ->
        %{x: x + @move_speed, z: z + @move_speed}

      :left ->
        %{x: x - @move_speed, z: z + @move_speed}

      :right ->
        %{x: x + @move_speed, z: z - @move_speed}

      {:to, target_x, target_z} ->
        # Move towards target
        dx = target_x - x
        dz = target_z - z
        dist = :math.sqrt(dx * dx + dz * dz)

        if dist < @move_speed do
          %{x: target_x * 1.0, z: target_z * 1.0}
        else
          ratio = @move_speed / dist
          %{x: x + dx * ratio, z: z + dz * ratio}
        end

      _ ->
        position
    end
  end

  defp broadcast_update(entities) do
    PubSub.broadcast(@pubsub, @topic, {:world_update, entities})
  end

  defp broadcast_position_update(user_id, position) do
    PubSub.broadcast(@pubsub, @topic, {:position_update, user_id, position})
  end

  defp broadcast_user_traveled(user_id, from_location_id, to_location_id) do
    PubSub.broadcast(@pubsub, @topic, {:user_traveled, user_id, from_location_id, to_location_id})
  end

  defp broadcast_object_placed(object) do
    PubSub.broadcast(@pubsub, @topic, {:object_placed, object})
  end

  defp broadcast_object_updated(object) do
    PubSub.broadcast(@pubsub, @topic, {:object_updated, object})
  end

  defp load_world_objects(nil), do: %{}
  defp load_world_objects(location) do
    location.id
    |> Geo.list_objects_at_location()
    |> Enum.map(fn obj -> {obj.id, obj} end)
    |> Map.new()
  end

  defp random_color do
    colors = ["#4a90d9", "#d94a8a", "#8ad94a", "#9a4ad9", "#4ad9d9"]
    Enum.random(colors)
  end

  # Persist user location to database (async, non-blocking)
  defp persist_user_location(user_id, lat, long, location_id) do
    case user_id do
      "user_" <> id_str ->
        Task.start(fn ->
          case Integer.parse(id_str) do
            {id, _} ->
              case Wepublic.Repo.get(Wepublic.Accounts.User, id) do
                nil -> :ok
                user -> Geo.update_user_position(user, lat, long, location_id)
              end
            :error -> :ok
          end
        end)
      _ ->
        # NPCs or anonymous users don't persist
        :ok
    end
  end

  # Load user's saved location from database
  defp load_user_saved_location(user_id, default_location) do
    case user_id do
      "user_" <> id_str ->
        case Integer.parse(id_str) do
          {id, _} ->
            case Wepublic.Repo.get(Wepublic.Accounts.User, id) do
              nil ->
                {default_location, nil, nil}
              user ->
                location = if user.last_location_id do
                  Geo.get_location(user.last_location_id)
                else
                  default_location
                end
                {location || default_location, user.position_lat, user.position_long}
            end
          :error ->
            {default_location, nil, nil}
        end
      _ ->
        # NPCs or anonymous users use default
        {default_location, nil, nil}
    end
  end
end
