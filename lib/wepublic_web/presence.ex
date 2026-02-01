defmodule WepublicWeb.Presence do
  @moduledoc """
  Tracks user presence across the application.

  Users are tracked by location:
  - "map" - Users viewing the main 3D map
  - "beacon:{id}" - Users near a specific beacon
  - "nation:{id}" - Users in a specific nation
  - "gathering:{id}" - Users in a gathering view

  Usage in LiveView:
      def mount(_params, _session, socket) do
        if connected?(socket) do
          WepublicWeb.Presence.track_user(socket, "map")
        end
        {:ok, socket}
      end
  """

  use Phoenix.Presence,
    otp_app: :wepublic,
    pubsub_server: Wepublic.PubSub

  alias Phoenix.Socket.Broadcast

  @doc """
  Tracks a user in a specific location.
  Works with both Phoenix.Socket and Phoenix.LiveView.Socket.
  """
  def track_user(socket, location, meta \\ %{}) do
    user = socket.assigns[:current_user] || socket.assigns[:current_scope]

    user_meta =
      Map.merge(
        %{
          joined_at: DateTime.utc_now(),
          user_id: get_user_id(user),
          display_name: get_display_name(user),
          avatar_color: get_avatar_color(user),
          position: %{x: 0.0, z: 0.0}
        },
        meta
      )

    # For LiveView sockets, use the self() pid as the key
    key = get_user_id(user)
    track(self(), location, key, user_meta)
  end

  @doc """
  Updates user metadata (e.g., position change).
  """
  def update_user(socket, location, meta) do
    user = socket.assigns[:current_user] || socket.assigns[:current_scope]
    key = get_user_id(user)

    update(self(), location, key, fn existing ->
      Map.merge(existing, meta)
    end)
  end

  @doc """
  Gets the count of users in a location.
  """
  def count(location) do
    location
    |> list()
    |> map_size()
  end

  @doc """
  Gets all users in a location with their metadata.
  """
  def list_users(location) do
    location
    |> list()
    |> Enum.map(fn {_key, %{metas: [meta | _]}} -> meta end)
  end

  @doc """
  Subscribes to presence updates for a location.
  """
  def subscribe(location) do
    Phoenix.PubSub.subscribe(Wepublic.PubSub, "presence:#{location}")
  end

  @doc """
  Broadcasts presence state to subscribers.
  """
  def broadcast_presence(location) do
    users = list_users(location)
    count = length(users)

    Phoenix.PubSub.broadcast(
      Wepublic.PubSub,
      "presence:#{location}",
      %Broadcast{
        topic: "presence:#{location}",
        event: "presence_state",
        payload: %{users: users, count: count}
      }
    )
  end

  # Private helpers

  defp get_user_id(nil), do: "anonymous_#{:rand.uniform(10000)}"
  defp get_user_id(%{user: %{id: id}}), do: "user_#{id}"
  defp get_user_id(%{id: id}), do: "user_#{id}"
  defp get_user_id(_), do: "anonymous_#{:rand.uniform(10000)}"

  defp get_display_name(nil), do: "Anonymous"
  defp get_display_name(%{user: %{display_name: name}}) when not is_nil(name), do: name
  defp get_display_name(%{user: %{email: email}}), do: email |> String.split("@") |> hd()
  defp get_display_name(%{display_name: name}) when not is_nil(name), do: name
  defp get_display_name(%{email: email}), do: email |> String.split("@") |> hd()
  defp get_display_name(_), do: "Anonymous"

  defp get_avatar_color(nil), do: "#888888"
  defp get_avatar_color(%{user: %{avatar_color: color}}) when not is_nil(color), do: color
  defp get_avatar_color(%{avatar_color: color}) when not is_nil(color), do: color
  defp get_avatar_color(_), do: "#4a90d9"
end
