defmodule WepublicWeb.MapLive do
  use WepublicWeb, :live_view

  alias WepublicWeb.Presence
  alias Wepublic.Accounts
  alias Wepublic.Accounts.User
  alias Wepublic.MapWorld
  alias Wepublic.Geo

  @impl true
  def mount(_params, _session, socket) do
    require Logger
    current_user = get_current_user(socket)
    Logger.warning("MOUNT: current_user=#{inspect(current_user && current_user.email)}, assigns_keys=#{inspect(Map.keys(socket.assigns))}")

    # Generate a consistent user_id for this session
    my_user_id = get_my_user_id(current_user)
    connections = get_user_connections(current_user)

    world_entities =
      if connected?(socket) do
        # Subscribe to presence and world updates
        Presence.subscribe("map")
        Presence.track_user(socket, "map")
        MapWorld.subscribe()

        # Join the world - server assigns spawn position
        # join/2 is a call, so it returns after the entity is added
        user_meta = build_user_meta(current_user, connections)
        MapWorld.join(my_user_id, user_meta)

        # Now get all entities (including ourselves)
        MapWorld.get_entities()
      else
        %{}
      end

    online_users = Presence.list_users("map")

    # Get current location from MapWorld
    current_location = MapWorld.get_current_location()
    world_objects = if connected?(socket), do: MapWorld.get_objects(), else: []

    socket =
      socket
      |> assign(:online_count, Presence.count("map"))
      |> assign(:online_users, online_users)
      |> assign(:connections, connections)
      |> assign(:connections_with_presence, merge_connections_with_presence(connections, online_users))
      |> assign(:drawer_open, false)
      |> assign(:selected_user, nil)
      |> assign(:show_user_modal, false)
      |> assign(:current_user, current_user)
      |> assign(:my_user_id, my_user_id)
      |> assign(:world_entities, world_entities)
      |> assign(:show_onboarding_prompt, should_show_onboarding?(current_user))
      |> assign(:current_location, current_location)
      |> assign(:world_objects, world_objects)
      |> assign(:show_travel_modal, false)
      |> assign(:travel_search, "")
      |> assign(:travel_results, [])
      |> assign(:show_place_mode, false)
      |> assign(:place_object_type, "pin")
      |> assign(:place_object_color, "#4a90d9")

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Leave the world when disconnecting
    if socket.assigns[:my_user_id] do
      MapWorld.leave(socket.assigns.my_user_id)
    end

    :ok
  end

  defp get_my_user_id(nil), do: "anonymous_#{:erlang.unique_integer([:positive])}"
  defp get_my_user_id(%{id: id}), do: "user_#{id}"

  defp build_user_meta(nil, _connections) do
    %{name: "Anonymous", display_name: "Anonymous", color: "#4a90d9"}
  end

  defp build_user_meta(user, connections) do
    %{
      name: user.display_name || user.email |> String.split("@") |> hd(),
      display_name: user.display_name || user.email |> String.split("@") |> hd(),
      color: user.avatar_color || "#4a90d9",
      verification_level: User.verification_level(user),
      connections: Enum.map(connections, & &1.id)
    }
  end

  defp get_current_user(socket) do
    case socket.assigns do
      %{current_scope: %Wepublic.Accounts.Scope{user: user}} when not is_nil(user) -> user
      %{current_scope: %{user: user}} when not is_nil(user) -> user
      %{current_user: user} when not is_nil(user) -> user
      _ -> nil
    end
  end

  defp get_user_connections(nil), do: []

  defp get_user_connections(user) do
    Accounts.list_connections(user)
    |> Enum.map(fn conn ->
      other_user =
        if conn.user_id == user.id,
          do: conn.connected_user,
          else: conn.user

      %{
        id: other_user.id,
        display_name: other_user.display_name || other_user.email |> String.split("@") |> hd(),
        avatar_color: other_user.avatar_color || "#4a90d9",
        verification_level: User.verification_level(other_user),
        did: other_user.did,
        website: other_user.website
      }
    end)
  end

  defp merge_connections_with_presence(connections, online_users) do
    online_ids =
      online_users
      |> Enum.map(fn meta ->
        case meta.user_id do
          "user_" <> id -> String.to_integer(id)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    connections
    |> Enum.map(fn conn ->
      Map.put(conn, :online, MapSet.member?(online_ids, conn.id))
    end)
    |> Enum.sort_by(fn %{online: online} -> if online, do: 0, else: 1 end)
  end

  defp should_show_onboarding?(nil), do: false

  defp should_show_onboarding?(user) do
    not User.onboarding_complete?(user) and
      (not User.did_verified?(user) or not User.feed_verified?(user))
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_state", payload: %{count: count}}, socket) do
    online_users = Presence.list_users("map")

    {:noreply,
     socket
     |> assign(:online_count, count)
     |> assign(:online_users, online_users)
     |> assign(
       :connections_with_presence,
       merge_connections_with_presence(socket.assigns.connections, online_users)
     )}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    online_users = Presence.list_users("map")

    {:noreply,
     socket
     |> assign(:online_count, Presence.count("map"))
     |> assign(:online_users, online_users)
     |> assign(
       :connections_with_presence,
       merge_connections_with_presence(socket.assigns.connections, online_users)
     )}
  end

  # Handle world state updates from MapWorld GenServer
  def handle_info({:world_update, entities}, socket) do
    require Logger
    entity_ids = Map.keys(entities)
    Logger.warning("WORLD_UPDATE: my_user_id=#{socket.assigns.my_user_id}, entity_ids=#{inspect(entity_ids)}")

    {:noreply,
     socket
     |> assign(:world_entities, entities)
     |> push_event("world_update", %{entities: entities_to_list(entities, socket.assigns.my_user_id)})}
  end

  # Handle position updates from MapWorld GenServer
  # Send ALL position updates to client (including our own) so client stays in sync with server
  def handle_info({:position_update, user_id, position}, socket) do
    require Logger
    Logger.warning("POSITION_UPDATE: sending to client, user_id=#{user_id}, my_user_id=#{socket.assigns.my_user_id}")

    {:noreply, push_event(socket, "user_position", %{user_id: user_id, position: position})}
  end

  # Handle location change from MapWorld (when someone travels)
  def handle_info({:location_changed, location, objects}, socket) do
    require Logger
    Logger.warning("LOCATION_CHANGED: #{location.name}")

    {:noreply,
     socket
     |> assign(:current_location, location)
     |> assign(:world_objects, objects)
     |> push_event("location_changed", %{
       location: serialize_location(location),
       objects: Enum.map(objects, &serialize_object/1)
     })}
  end

  # Handle object placement
  def handle_info({:object_placed, object}, socket) do
    {:noreply,
     socket
     |> update(:world_objects, &[object | &1])
     |> push_event("object_placed", %{object: serialize_object(object)})}
  end

  # Handle object update
  def handle_info({:object_updated, object}, socket) do
    {:noreply,
     socket
     |> update(:world_objects, fn objects ->
       Enum.map(objects, fn o ->
         if o.id == object.parent_id || o.id == object.id, do: object, else: o
       end)
     end)
     |> push_event("object_updated", %{object: serialize_object(object)})}
  end

  @impl true
  def handle_event("toggle_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_open, not socket.assigns.drawer_open)}
  end

  def handle_event("close_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_open, false)}
  end

  def handle_event("user_clicked", %{"user_id" => user_id}, socket) do
    # Find the user data from the clicked user
    user_data = find_user_by_id(socket.assigns, user_id)

    {:noreply,
     socket
     |> assign(:selected_user, user_data)
     |> assign(:show_user_modal, true)}
  end

  def handle_event("close_user_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:show_user_modal, false)}
  end

  def handle_event("request_connection", %{"user_id" => user_id}, socket) do
    current_user = socket.assigns.current_user

    if current_user do
      case Integer.parse(user_id) do
        {id, _} ->
          target_user = Accounts.get_user!(id)
          Accounts.request_connection(current_user, target_user)

          {:noreply,
           socket
           |> put_flash(:info, "Connection request sent!")
           |> assign(:show_user_modal, false)}

        :error ->
          {:noreply, socket}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You must be logged in to connect")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  def handle_event("dismiss_onboarding", _, socket) do
    {:noreply, assign(socket, :show_onboarding_prompt, false)}
  end

  # Travel modal
  def handle_event("open_travel_modal", _, socket) do
    {:noreply,
     socket
     |> assign(:show_travel_modal, true)
     |> assign(:travel_search, "")
     |> assign(:travel_results, Geo.list_locations())}
  end

  def handle_event("close_travel_modal", _, socket) do
    {:noreply, assign(socket, :show_travel_modal, false)}
  end

  def handle_event("search_locations", %{"query" => query}, socket) do
    results = if String.trim(query) == "" do
      Geo.list_locations()
    else
      Geo.search_locations(query)
    end

    {:noreply,
     socket
     |> assign(:travel_search, query)
     |> assign(:travel_results, results)}
  end

  def handle_event("travel_to", %{"location_id" => location_id}, socket) do
    location_id = String.to_integer(location_id)

    case MapWorld.travel(socket.assigns.my_user_id, location_id) do
      {:ok, location} ->
        {:noreply,
         socket
         |> assign(:show_travel_modal, false)
         |> assign(:current_location, location)
         |> put_flash(:info, "Traveled to #{location.name}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not travel to that location")}
    end
  end

  # Object placement
  def handle_event("toggle_place_mode", _, socket) do
    new_mode = not socket.assigns.show_place_mode
    {:noreply,
     socket
     |> assign(:show_place_mode, new_mode)
     |> push_event("set_place_mode", %{enabled: new_mode})}
  end

  def handle_event("set_object_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, :place_object_type, type)}
  end

  def handle_event("set_object_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :place_object_color, color)}
  end

  def handle_event("place_object", %{"x" => x, "z" => z}, socket) do
    attrs = %{
      object_type: socket.assigns.place_object_type,
      position_x: x,
      position_z: z,
      color: socket.assigns.place_object_color
    }

    case MapWorld.place_object(socket.assigns.my_user_id, attrs) do
      {:ok, _object} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not place object")}
    end
  end

  def handle_event("pan_to_user", %{"user_id" => user_id}, socket) do
    # Convert numeric id to the format used in MapWorld
    map_user_id = "user_#{user_id}"

    case MapWorld.get_entity(map_user_id) do
      nil ->
        {:noreply, put_flash(socket, :info, "User is not currently on the map")}

      entity ->
        {:noreply,
         socket
         |> assign(:drawer_open, false)
         |> push_event("pan_to_position", %{x: entity.position.x, z: entity.position.z})}
    end
  end

  def handle_event("recenter", _, socket) do
    my_user_id = socket.assigns.my_user_id

    case MapWorld.get_entity(my_user_id) do
      nil ->
        {:noreply, socket}

      entity ->
        {:noreply, push_event(socket, "pan_to_position", %{x: entity.position.x, z: entity.position.z})}
    end
  end

  # Handle movement from the viewer - send to MapWorld
  def handle_event("move", %{"direction" => direction}, socket) do
    user_id = socket.assigns.my_user_id

    require Logger
    Logger.warning("MOVE EVENT: user=#{user_id} direction=#{direction}")

    dir_atom = case direction do
      "up" -> :up
      "down" -> :down
      "left" -> :left
      "right" -> :right
      _ -> nil
    end

    if dir_atom do
      MapWorld.move(user_id, dir_atom)
    end

    {:noreply, socket}
  end

  def handle_event("move_to", %{"x" => x, "z" => z}, socket) do
    user_id = socket.assigns.my_user_id

    require Logger
    Logger.warning("MOVE_TO EVENT: user=#{user_id} x=#{x} z=#{z}")

    MapWorld.move(user_id, {:to, x, z})
    {:noreply, socket}
  end

  defp find_user_by_id(assigns, user_id) do
    # Extract numeric ID if present
    numeric_id =
      case user_id do
        "user_" <> id -> String.to_integer(id)
        "demo_" <> _ -> nil
        _ -> nil
      end

    # Check online users first
    online_match =
      (assigns[:online_users] || [])
      |> Enum.find(fn meta -> meta.user_id == user_id end)

    if online_match do
      # Get full user data if we have numeric ID
      user =
        if numeric_id do
          try do
            Accounts.get_user!(numeric_id)
          rescue
            _ -> nil
          end
        end

      %{
        id: user_id,
        numeric_id: numeric_id,
        display_name: online_match.display_name,
        avatar_color: online_match.avatar_color,
        did: user && user.did,
        website: user && user.website,
        verification_level: user && Wepublic.Accounts.User.verification_level(user) || 0,
        feed_title: user && user.feed_title,
        is_online: true,
        is_demo: false
      }
    else
      # Check if it's a demo user
      demo_users = %{
        "demo_alice" => %{
          display_name: "Alice",
          avatar_color: "#d94a8a",
          website: "https://alice.example.com",
          verification_level: 2,
          is_demo: true
        },
        "demo_bob" => %{
          display_name: "Bob",
          avatar_color: "#8ad94a",
          website: "https://bob.example.com",
          verification_level: 1,
          is_demo: true
        },
        "demo_carol" => %{
          display_name: "Carol",
          avatar_color: "#d9a84a",
          website: "https://carol.example.com",
          verification_level: 0,
          is_demo: true
        }
      }

      case Map.get(demo_users, user_id) do
        nil ->
          nil

        demo ->
          Map.merge(demo, %{
            id: user_id,
            numeric_id: nil,
            did: nil,
            feed_title: nil,
            is_online: false
          })
      end
    end
  end

  defp get_map_users(assigns) do
    my_user_id = assigns[:my_user_id]
    world_entities = assigns[:world_entities] || %{}
    connections = assigns[:connections] || []
    connection_ids = Enum.map(connections, &"user_#{&1.id}")

    # Convert world entities to client format
    entities_to_list(world_entities, my_user_id, connection_ids)
  end

  defp entities_to_list(entities, my_user_id) do
    entities_to_list(entities, my_user_id, [])
  end

  defp entities_to_list(entities, my_user_id, connection_ids) do
    entities
    |> Map.values()
    |> Enum.map(fn entity ->
      is_viewer = entity.id == my_user_id

      %{
        id: entity.id,
        name: entity.name,
        display_name: entity.display_name,
        color: entity.color,
        position: entity.position,
        connections: if(is_viewer, do: connection_ids, else: entity[:connections] || []),
        isViewer: is_viewer,
        verificationLevel: entity[:verification_level] || 0,
        hasProducts: entity[:has_products] || false
      }
    end)
    |> Enum.sort_by(fn e -> if e.isViewer, do: 0, else: 1 end)
  end

  defp connection_ids_json(connections) do
    connections
    |> Enum.map(&"user_#{&1.id}")
    |> Jason.encode!()
  end

  defp serialize_location(nil), do: nil
  defp serialize_location(location) do
    %{
      id: location.id,
      name: location.name,
      slug: location.slug,
      center_lat: location.center_lat,
      center_long: location.center_long,
      bounds_geojson: location.bounds_geojson,
      location_type: location.location_type
    }
  end

  defp serialize_object(object) do
    %{
      id: object.id,
      object_type: object.object_type,
      position_x: object.position_x,
      position_y: object.position_y,
      position_z: object.position_z,
      label: object.label,
      color: object.color,
      model_url: object.model_url,
      version: object.version
    }
  end

  @impl true
  def render(assigns) do
    connections = assigns[:connections] || []

    assigns =
      assigns
      |> assign(:map_users, get_map_users(assigns))
      |> assign(:connection_ids_json, connection_ids_json(connections))

    ~H"""
    <div
      id="neighborhood-container"
      phx-hook="Neighborhood"
      phx-update="ignore"
      data-users={Jason.encode!(@map_users)}
      data-current-user-id={@my_user_id}
      data-connections={@connection_ids_json}
      class="w-full h-screen relative z-0"
    >
    </div>

    <div
      id="neighborhood-info"
      class="fixed top-12 left-2.5 z-40 text-white font-mono text-xs bg-black/70 p-3 rounded-lg max-w-60"
    >
      <div class="text-sm font-bold mb-2">
        {location_name(@current_location)}
      </div>
      <div class="text-gray-400 mb-3">
        {location_coords(@current_location)}
      </div>
      <div class="flex items-center gap-2 mb-3 text-green-400">
        <span class="w-2 h-2 rounded-full bg-green-400 animate-pulse"></span>
        <span>{@online_count} online</span>
      </div>
      <button
        phx-click="open_travel_modal"
        class="w-full text-left text-purple-400 hover:text-purple-300 text-xs py-1 mb-1"
      >
        Travel to another location →
      </button>
      <button
        phx-click="toggle_drawer"
        class="w-full text-left text-blue-400 hover:text-blue-300 text-xs py-1"
      >
        Connections ({length(@connections)}) →
      </button>
      <div
        id="figure-list"
        class="border-t border-gray-600 pt-2 mt-2"
      >
      </div>
    </div>

    <button
      phx-click="recenter"
      title="Recenter on me"
      class="fixed bottom-4 left-4 z-40 bg-black/70 hover:bg-black/90 text-white p-3 rounded-full shadow-lg transition"
    >
      <svg
        class="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm0-6v2m0 16v2m8-10h2M2 12h2m13.66-5.66l1.41-1.41M4.93 19.07l1.41-1.41m0-11.32L4.93 4.93m14.14 14.14l-1.41-1.41"
        />
      </svg>
    </button>

    <.onboarding_prompt :if={@show_onboarding_prompt} />

    <.connections_drawer
      open={@drawer_open}
      connections={@connections_with_presence}
      current_user={@current_user}
    />

    <.user_profile_modal
      :if={@show_user_modal && @selected_user}
      user={@selected_user}
      current_user={@current_user}
      connections={@connections}
    />

    <.travel_modal
      :if={@show_travel_modal}
      results={@travel_results}
      search={@travel_search}
      current_location={@current_location}
    />

    <.place_controls
      :if={@show_place_mode}
      object_type={@place_object_type}
      color={@place_object_color}
    />

    <button
      phx-click="toggle_place_mode"
      title={if @show_place_mode, do: "Exit place mode", else: "Place an object"}
      class={[
        "fixed bottom-4 left-16 z-40 p-3 rounded-full shadow-lg transition",
        if(@show_place_mode, do: "bg-green-600 hover:bg-green-700 text-white", else: "bg-black/70 hover:bg-black/90 text-white")
      ]}
    >
      <svg
        class="w-5 h-5"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M12 4v16m8-8H4"
        />
      </svg>
    </button>
    """
  end

  defp location_name(nil), do: "Unknown Location"
  defp location_name(location), do: location.name

  defp location_coords(nil), do: ""
  defp location_coords(location) do
    lat_dir = if location.center_lat >= 0, do: "N", else: "S"
    long_dir = if location.center_long >= 0, do: "E", else: "W"
    "#{abs(location.center_lat) |> Float.round(4)}°#{lat_dir}, #{abs(location.center_long) |> Float.round(4)}°#{long_dir}"
  end

  defp onboarding_prompt(assigns) do
    ~H"""
    <div class="fixed bottom-4 right-4 z-50 bg-gradient-to-r from-blue-600 to-purple-600 text-white p-4 rounded-lg shadow-xl max-w-sm">
      <div class="flex items-start gap-3">
        <div class="text-2xl">✨</div>
        <div class="flex-1">
          <h3 class="font-bold mb-1">Complete Your Profile</h3>
          <p class="text-sm text-blue-100 mb-3">
            Verify your web identity to unlock the full Wepublic experience.
          </p>
          <div class="flex gap-2">
            <.link
              navigate={~p"/onboard"}
              class="bg-white text-blue-600 px-3 py-1 rounded text-sm font-medium hover:bg-blue-50"
            >
              Get Started
            </.link>
            <button
              phx-click="dismiss_onboarding"
              class="text-blue-200 hover:text-white text-sm"
            >
              Later
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp connections_drawer(assigns) do
    ~H"""
    <div
      class={[
        "fixed top-0 right-0 h-full w-80 bg-gray-900 shadow-xl transform transition-transform duration-300 z-50",
        if(@open, do: "translate-x-0", else: "translate-x-full")
      ]}
    >
      <div class="p-4 border-b border-gray-700">
        <div class="flex items-center justify-between">
          <h2 class="text-white font-bold text-lg">Connections</h2>
          <button
            phx-click="close_drawer"
            class="text-gray-400 hover:text-white"
          >
            ✕
          </button>
        </div>
      </div>

      <div class="overflow-y-auto h-full pb-20">
        <%= if length(@connections) == 0 do %>
          <div class="p-4 text-gray-400 text-center">
            <p class="mb-2">No connections yet</p>
            <p class="text-sm">
              Connect with others to see them appear solid in the 3D view.
            </p>
          </div>
        <% else %>
          <div class="divide-y divide-gray-700">
            <%= for conn <- @connections do %>
              <.connection_item conn={conn} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <div
      :if={@open}
      phx-click="close_drawer"
      class="fixed inset-0 bg-black/50 z-40"
    >
    </div>
    """
  end

  defp connection_item(assigns) do
    ~H"""
    <div
      class="p-4 hover:bg-gray-800 cursor-pointer"
      phx-click={@conn.online && "pan_to_user"}
      phx-value-user_id={@conn.id}
    >
      <div class="flex items-center gap-3">
        <div class="relative">
          <div
            class="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold"
            style={"background-color: #{@conn.avatar_color}"}
          >
            {String.first(@conn.display_name)}
          </div>
          <div
            :if={@conn.online}
            class="absolute -bottom-0.5 -right-0.5 w-3 h-3 bg-green-400 rounded-full border-2 border-gray-900"
          >
          </div>
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-white font-medium truncate">
              {@conn.display_name}
            </span>
            <.verification_badges level={@conn.verification_level} />
          </div>
          <div class="text-xs text-gray-400 truncate">
            {@conn.did || @conn.website || ""}
          </div>
        </div>
        <div class="text-xs">
          <%= if @conn.online do %>
            <span class="text-green-400">online</span>
            <span class="text-gray-600 ml-1">→</span>
          <% else %>
            <span class="text-gray-500">offline</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp verification_badges(assigns) do
    ~H"""
    <span :if={@level == 2} class="text-green-400 text-xs">✓✓</span>
    <span :if={@level == 1} class="text-blue-400 text-xs">✓</span>
    """
  end

  defp user_profile_modal(assigns) do
    is_connected =
      Enum.any?(assigns.connections, fn conn ->
        conn.id == assigns.user.numeric_id
      end)

    assigns = assign(assigns, :is_connected, is_connected)

    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_user_modal"
      phx-key="Escape"
    >
      <div
        class="absolute inset-0 bg-black/60"
        phx-click="close_user_modal"
      >
      </div>

      <div class="relative bg-gray-800 rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
        <button
          phx-click="close_user_modal"
          class="absolute top-3 right-3 text-gray-400 hover:text-white z-10"
        >
          <svg
            class="w-6 h-6"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>

        <div class="p-6">
          <div class="flex items-start gap-4">
            <div class="relative">
              <div
                class="w-16 h-16 rounded-full flex items-center justify-center text-white text-2xl font-bold"
                style={"background-color: #{@user.avatar_color}"}
              >
                {String.first(@user.display_name || "?")}
              </div>
              <div
                :if={@user.is_online}
                class="absolute -bottom-1 -right-1 w-4 h-4 bg-green-400 rounded-full border-2 border-gray-800"
              >
              </div>
            </div>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h2 class="text-xl font-bold text-white truncate">
                  {@user.display_name}
                </h2>
                <.verification_badge_large level={@user.verification_level} />
              </div>

              <div
                :if={@user.is_online}
                class="text-green-400 text-sm"
              >
                Online now
              </div>

              <div
                :if={@user.is_demo}
                class="text-gray-500 text-sm italic"
              >
                Demo user
              </div>
            </div>
          </div>

          <div class="mt-6 space-y-3">
            <div
              :if={@user.did}
              class="flex items-center gap-2 text-sm"
            >
              <span class="text-gray-400 w-16">DID</span>
              <span class="text-blue-400 truncate">{@user.did}</span>
            </div>

            <div
              :if={@user.website}
              class="flex items-center gap-2 text-sm"
            >
              <span class="text-gray-400 w-16">Website</span>
              <a
                href={@user.website}
                target="_blank"
                rel="noopener"
                class="text-blue-400 hover:underline truncate"
              >
                {@user.website}
              </a>
            </div>

            <div
              :if={@user.feed_title}
              class="flex items-center gap-2 text-sm"
            >
              <span class="text-gray-400 w-16">Feed</span>
              <span class="text-white truncate">{@user.feed_title}</span>
            </div>
          </div>

          <div class="mt-6 pt-4 border-t border-gray-700">
            <div class="flex items-center justify-between mb-4">
              <span class="text-gray-400 text-sm">Verification Level</span>
              <.verification_level_display level={@user.verification_level} />
            </div>
          </div>

          <div class="mt-4 flex gap-3">
            <%= if @user.is_demo do %>
              <div class="flex-1 text-center text-gray-500 text-sm py-2">
                Demo users cannot be connected
              </div>
            <% else %>
              <%= if @is_connected do %>
                <div class="flex-1 bg-green-600/20 text-green-400 py-2 px-4 rounded-lg text-center">
                  Connected
                </div>
              <% else %>
                <%= if @current_user do %>
                  <button
                    phx-click="request_connection"
                    phx-value-user_id={@user.numeric_id}
                    class="flex-1 bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded-lg transition font-medium"
                  >
                    Connect
                  </button>
                <% else %>
                  <.link
                    navigate={~p"/users/log-in"}
                    class="flex-1 bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded-lg transition font-medium text-center"
                  >
                    Log in to Connect
                  </.link>
                <% end %>
              <% end %>

              <a
                :if={@user.website}
                href={@user.website}
                target="_blank"
                rel="noopener"
                class="bg-gray-700 hover:bg-gray-600 text-white py-2 px-4 rounded-lg transition"
              >
                Visit Site
              </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp verification_badge_large(assigns) do
    ~H"""
    <span
      :if={@level == 2}
      class="inline-flex items-center gap-1 bg-green-500/20 text-green-400 px-2 py-0.5 rounded-full text-xs"
    >
      <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
        <path
          fill-rule="evenodd"
          d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
          clip-rule="evenodd"
        />
      </svg>
      Verified
    </span>
    <span
      :if={@level == 1}
      class="inline-flex items-center gap-1 bg-blue-500/20 text-blue-400 px-2 py-0.5 rounded-full text-xs"
    >
      <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
        <path
          fill-rule="evenodd"
          d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
          clip-rule="evenodd"
        />
      </svg>
      Partial
    </span>
    """
  end

  defp verification_level_display(assigns) do
    ~H"""
    <div class="flex items-center gap-1">
      <div class={[
        "w-3 h-3 rounded-full",
        @level >= 1 && "bg-blue-400" || "bg-gray-600"
      ]}>
      </div>
      <div class={[
        "w-3 h-3 rounded-full",
        @level >= 2 && "bg-green-400" || "bg-gray-600"
      ]}>
      </div>
      <span class="text-white text-sm ml-1">{@level}/2</span>
    </div>
    """
  end

  defp travel_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_travel_modal"
      phx-key="Escape"
    >
      <div
        class="absolute inset-0 bg-black/60"
        phx-click="close_travel_modal"
      >
      </div>

      <div class="relative bg-gray-800 rounded-xl shadow-2xl max-w-md w-full overflow-hidden">
        <div class="p-4 border-b border-gray-700">
          <div class="flex items-center justify-between">
            <h2 class="text-white font-bold text-lg">Travel to Location</h2>
            <button
              phx-click="close_travel_modal"
              class="text-gray-400 hover:text-white"
            >
              <svg
                class="w-6 h-6"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
        </div>

        <div class="p-4">
          <input
            type="text"
            value={@search}
            phx-keyup="search_locations"
            phx-debounce="300"
            placeholder="Search locations..."
            class="w-full bg-gray-700 text-white rounded-lg px-4 py-2 mb-4 focus:outline-none focus:ring-2 focus:ring-purple-500"
          />

          <div class="max-h-64 overflow-y-auto space-y-2">
            <%= for location <- @results do %>
              <button
                phx-click="travel_to"
                phx-value-location_id={location.id}
                disabled={@current_location && @current_location.id == location.id}
                class={[
                  "w-full text-left p-3 rounded-lg transition",
                  if(@current_location && @current_location.id == location.id,
                    do: "bg-gray-600 text-gray-400 cursor-not-allowed",
                    else: "bg-gray-700 hover:bg-gray-600 text-white"
                  )
                ]}
              >
                <div class="font-medium">{location.name}</div>
                <div class="text-xs text-gray-400">
                  {Float.round(location.center_lat, 4)}°, {Float.round(location.center_long, 4)}°
                  <%= if @current_location && @current_location.id == location.id do %>
                    <span class="text-purple-400 ml-2">(current)</span>
                  <% end %>
                </div>
              </button>
            <% end %>
          </div>

          <%= if @results == [] do %>
            <div class="text-center text-gray-400 py-8">
              No locations found
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp place_controls(assigns) do
    ~H"""
    <div class="fixed bottom-20 left-4 z-40 bg-black/80 rounded-lg p-3 text-white text-sm">
      <div class="mb-2 font-medium">Place Object</div>

      <div class="flex gap-2 mb-3">
        <button
          phx-click="set_object_type"
          phx-value-type="pin"
          class={[
            "px-3 py-1 rounded",
            if(@object_type == "pin", do: "bg-purple-600", else: "bg-gray-700 hover:bg-gray-600")
          ]}
        >
          Pin
        </button>
        <button
          phx-click="set_object_type"
          phx-value-type="cube"
          class={[
            "px-3 py-1 rounded",
            if(@object_type == "cube", do: "bg-purple-600", else: "bg-gray-700 hover:bg-gray-600")
          ]}
        >
          Cube
        </button>
      </div>

      <div class="flex items-center gap-2">
        <span class="text-gray-400">Color:</span>
        <div class="flex gap-1">
          <%= for color <- ~w(#4a90d9 #d94a8a #8ad94a #d9a84a #9a4ad9 #ffffff) do %>
            <button
              phx-click="set_object_color"
              phx-value-color={color}
              class={[
                "w-6 h-6 rounded",
                if(@color == color, do: "ring-2 ring-white ring-offset-1 ring-offset-gray-800", else: "")
              ]}
              style={"background-color: #{color}"}
            >
            </button>
          <% end %>
        </div>
      </div>

      <div class="mt-3 text-xs text-gray-400">
        Click on the ground to place
      </div>
    </div>
    """
  end
end
