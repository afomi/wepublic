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
      |> assign(:show_user_modal, false)
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
      phx-update="ignore"
      data-users={Jason.encode!(@map_users)}
      data-current-user-id={if @current_user, do: "user_#{@current_user.id}", else: ""}
      data-connections={@connection_ids_json}
      class="w-full h-screen relative z-0"
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

    <.user_profile_modal
      :if={@show_user_modal && @selected_user}
      user={@selected_user}
      current_user={@current_user}
      connections={@connections}
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
end
