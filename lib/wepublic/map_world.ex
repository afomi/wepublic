defmodule Wepublic.MapWorld do
  @moduledoc """
  GenServer that manages the canonical state of the 3D map world.

  Responsibilities:
  - Track all entity positions (users, NPCs, beacons)
  - Assign spawn positions for new users
  - Process movement intents
  - Broadcast state updates to subscribers

  Clients send intents, server owns state.
  """

  use GenServer

  alias Phoenix.PubSub

  @pubsub Wepublic.PubSub
  @topic "map_world"

  # Spawn positions spread around the map
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

  # State structure
  defstruct entities: %{},
            spawn_index: 0,
            movement_targets: %{}

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

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize with demo NPCs at fixed positions
    npcs = %{
      "npc_alice" => %{
        id: "npc_alice",
        type: :npc,
        name: "Alice",
        display_name: "Alice",
        color: "#d94a8a",
        position: %{x: 8.0, z: 5.0},
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
        verification_level: 0,
        has_products: false
      }
    }

    # Start the movement tick
    schedule_tick()

    {:ok, %__MODULE__{entities: npcs, spawn_index: 0, movement_targets: %{}}}
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
      # Assign spawn position
      {spawn_x, spawn_z} = Enum.at(@spawn_positions, rem(state.spawn_index, length(@spawn_positions)))

      entity = %{
        id: user_id,
        type: :user,
        name: meta[:name] || meta[:display_name] || "Anonymous",
        display_name: meta[:display_name] || meta[:name] || "Anonymous",
        color: meta[:color] || meta[:avatar_color] || random_color(),
        position: %{x: spawn_x * 1.0, z: spawn_z * 1.0},
        verification_level: meta[:verification_level] || 0,
        has_products: meta[:has_products] || false,
        connections: meta[:connections] || []
      }

      new_entities = Map.put(state.entities, user_id, entity)
      new_state = %{state | entities: new_entities, spawn_index: state.spawn_index + 1}

      Logger.warning("JOIN: #{user_id} at position #{inspect(entity.position)}, total entities: #{map_size(new_entities)}")

      broadcast_update(new_entities)

      {:reply, {:ok, entity}, new_state}
    end
  end

  @impl true
  def handle_call(:get_entities, _from, state) do
    {:reply, state.entities, state}
  end

  @impl true
  def handle_call({:get_entity, user_id}, _from, state) do
    {:reply, Map.get(state.entities, user_id), state}
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
        case direction do
          {:to, target_x, target_z} ->
            # Set movement target - will be processed by tick
            Logger.warning("MOVE_TO: #{user_id} targeting #{target_x}, #{target_z}")
            new_targets = Map.put(state.movement_targets, user_id, %{x: target_x, z: target_z})
            {:noreply, %{state | movement_targets: new_targets}}

          dir when dir in [:up, :down, :left, :right] ->
            # Immediate directional movement - clear any target
            new_position = calculate_new_position(entity.position, direction)
            updated_entity = %{entity | position: new_position}
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
                updated_entity = %{entity | position: new_position}
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

  defp random_color do
    colors = ["#4a90d9", "#d94a8a", "#8ad94a", "#d9a84a", "#9a4ad9", "#4ad9d9"]
    Enum.random(colors)
  end
end
