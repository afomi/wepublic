defmodule WepublicWeb.MapLive do
  use WepublicWeb, :live_view

  alias WepublicWeb.Presence
  alias Wepublic.Accounts
  alias Wepublic.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    current_user = get_current_user(socket)

    if connected?(socket) do
      Presence.subscribe("map")
      Presence.track_user(socket, "map")
    end

    connections = get_user_connections(current_user)
    online_users = Presence.list_users("map")

    socket =
      socket
      |> assign(:online_count, Presence.count("map"))
      |> assign(:online_users, online_users)
      |> assign(:connections, connections)
      |> assign(:connections_with_presence, merge_connections_with_presence(connections, online_users))
      |> assign(:drawer_open, false)
      |> assign(:selected_user, nil)
      |> assign(:current_user, current_user)
      |> assign(:show_onboarding_prompt, should_show_onboarding?(current_user))

    {:ok, socket}
  end

  defp get_current_user(socket) do
    case socket.assigns do
      %{current_scope: %{user: user}} -> user
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

  @impl true
  def handle_event("toggle_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_open, not socket.assigns.drawer_open)}
  end

  def handle_event("close_drawer", _, socket) do
    {:noreply, assign(socket, :drawer_open, false)}
  end

  def handle_event("user_clicked", %{"user_id" => _user_id}, socket) do
    # Handle clicking on a user in the 3D scene
    {:noreply, socket}
  end

  def handle_event("dismiss_onboarding", _, socket) do
    {:noreply, assign(socket, :show_onboarding_prompt, false)}
  end

  defp get_map_users(assigns) do
    current_user = assigns[:current_user]
    online_users = assigns[:online_users] || []
    connections = assigns[:connections] || []

    # Build user list for the 3D scene from online presence
    base_users =
      online_users
      |> Enum.with_index()
      |> Enum.map(fn {meta, index} ->
        user_id =
          case meta.user_id do
            "user_" <> id -> String.to_integer(id)
            _ -> nil
          end

        is_current = current_user && user_id == current_user.id

        %{
          id: meta.user_id,
          name: meta.display_name,
          display_name: meta.display_name,
          color: meta.avatar_color,
          position: %{x: -5 + index * 7, z: (index - 2) * 3},
          connections: if(is_current, do: Enum.map(connections, &"user_#{&1.id}"), else: []),
          isViewer: is_current,
          verificationLevel: 0,
          hasProducts: false
        }
      end)

    # Check if we have a viewer in the list
    has_viewer = Enum.any?(base_users, & &1.isViewer)

    # Build the viewer user (current user or anonymous)
    viewer_user =
      if current_user do
        %{
          id: "user_#{current_user.id}",
          name: current_user.display_name || current_user.email |> String.split("@") |> hd(),
          display_name: current_user.display_name || current_user.email |> String.split("@") |> hd(),
          color: current_user.avatar_color || "#4a90d9",
          position: %{x: 0, z: 0},
          connections: Enum.map(connections, &"user_#{&1.id}"),
          isViewer: true,
          verificationLevel: Wepublic.Accounts.User.verification_level(current_user),
          hasProducts: false
        }
      else
        %{
          id: "viewer",
          name: "You",
          display_name: "You",
          color: "#4a90d9",
          position: %{x: 0, z: 0},
          connections: [],
          isViewer: true,
          verificationLevel: 0,
          hasProducts: false
        }
      end

    # Add demo NPCs
    demo_users = [
      %{
        id: "demo_alice",
        name: "Alice",
        display_name: "Alice",
        color: "#d94a8a",
        position: %{x: 8, z: 5},
        connections: [],
        isViewer: false,
        verificationLevel: 2,
        hasProducts: true,
        website: "https://alice.example.com"
      },
      %{
        id: "demo_bob",
        name: "Bob",
        display_name: "Bob",
        color: "#8ad94a",
        position: %{x: 15, z: -8},
        connections: [],
        isViewer: false,
        verificationLevel: 1,
        hasProducts: false,
        website: "https://bob.example.com"
      },
      %{
        id: "demo_carol",
        name: "Carol",
        display_name: "Carol",
        color: "#d9a84a",
        position: %{x: -12, z: 10},
        connections: [],
        isViewer: false,
        verificationLevel: 0,
        hasProducts: false,
        website: "https://carol.example.com"
      }
    ]

    # Combine: viewer first, then online users (excluding viewer duplicate), then demos
    other_online =
      if has_viewer do
        # Remove the viewer from base_users since we're adding them separately
        Enum.reject(base_users, & &1.isViewer)
      else
        base_users
      end

    [viewer_user | other_online] ++ demo_users
  end

  defp connection_ids_json(connections) do
    connections
    |> Enum.map(&"user_#{&1.id}")
    |> Jason.encode!()
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
      data-users={Jason.encode!(@map_users)}
      data-current-user-id={if @current_user, do: "user_#{@current_user.id}", else: ""}
      data-connections={@connection_ids_json}
      class="w-full h-screen"
    >
    </div>

    <div
      id="neighborhood-info"
      class="fixed top-12 left-2.5 z-40 text-white font-mono text-xs bg-black/70 p-3 rounded-lg max-w-60"
    >
      <div class="text-sm font-bold mb-2">
        Vacaville, CA
      </div>
      <div class="text-gray-400 mb-3">
        38.3566°N, 121.9877°W
      </div>
      <div class="flex items-center gap-2 mb-3 text-green-400">
        <span class="w-2 h-2 rounded-full bg-green-400 animate-pulse"></span>
        <span>{@online_count} online</span>
      </div>
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

    <.onboarding_prompt :if={@show_onboarding_prompt} />

    <.connections_drawer
      open={@drawer_open}
      connections={@connections_with_presence}
      current_user={@current_user}
    />
    """
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
    <div class="p-4 hover:bg-gray-800 cursor-pointer">
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
end
