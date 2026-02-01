defmodule WepublicWeb.ConversationChannel do
  @moduledoc """
  Channel for real-time conversation messaging.

  Topics:
  - "conversation:lobby" - General presence and notifications
  - "conversation:{id}" - Specific conversation room
  """

  use WepublicWeb, :channel

  alias Wepublic.Interactions
  alias WepublicWeb.Presence

  @impl true
  def join("conversation:lobby", _params, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  def join("conversation:" <> conversation_id, _params, socket) do
    user_id = socket.assigns.user_id
    conversation_id = String.to_integer(conversation_id)

    # Check if user is a participant
    if Interactions.participant?(conversation_id, user_id) do
      send(self(), {:after_join_conversation, conversation_id})
      socket = assign(socket, :conversation_id, conversation_id)
      {:ok, socket}
    else
      {:error, %{reason: "not_a_participant"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user_id = socket.assigns.user_id

    # Track presence in lobby
    {:ok, _} = Presence.track(socket, "user:#{user_id}", %{
      user_id: user_id,
      online_at: System.system_time(:second)
    })

    # Push current presence state
    push(socket, "presence_state", Presence.list(socket))

    # Get unread counts
    unread = Interactions.total_unread_count(user_id)
    push(socket, "unread_count", %{count: unread})

    {:noreply, socket}
  end

  def handle_info({:after_join_conversation, conversation_id}, socket) do
    user_id = socket.assigns.user_id

    # Track presence in conversation
    {:ok, _} = Presence.track(socket, "user:#{user_id}", %{
      user_id: user_id,
      conversation_id: conversation_id,
      online_at: System.system_time(:second)
    })

    # Push current presence state
    push(socket, "presence_state", Presence.list(socket))

    # Load recent messages
    messages = Interactions.list_messages(conversation_id, limit: 50)
    push(socket, "message_history", %{messages: serialize_messages(messages)})

    # Mark as read
    Interactions.mark_as_read(conversation_id, user_id)

    {:noreply, socket}
  end

  @impl true
  def handle_in("send_message", %{"content" => content} = params, socket) do
    user_id = socket.assigns.user_id
    conversation_id = socket.assigns.conversation_id
    reply_to_id = params["reply_to_id"]

    opts = if reply_to_id, do: [reply_to_id: reply_to_id], else: []

    case Interactions.send_message(conversation_id, user_id, content, opts) do
      {:ok, message} ->
        broadcast!(socket, "new_message", %{message: serialize_message(message)})
        {:reply, :ok, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("typing", %{"typing" => typing}, socket) do
    user_id = socket.assigns.user_id

    broadcast_from!(socket, "user_typing", %{
      user_id: user_id,
      typing: typing
    })

    {:noreply, socket}
  end

  def handle_in("mark_read", _params, socket) do
    user_id = socket.assigns.user_id
    conversation_id = socket.assigns.conversation_id

    Interactions.mark_as_read(conversation_id, user_id)
    {:reply, :ok, socket}
  end

  def handle_in("load_more", %{"before_id" => before_id}, socket) do
    conversation_id = socket.assigns.conversation_id
    messages = Interactions.list_messages(conversation_id, limit: 50, before_id: before_id)

    {:reply, {:ok, %{messages: serialize_messages(messages)}}, socket}
  end

  # Helper functions

  defp serialize_messages(messages) do
    Enum.map(messages, &serialize_message/1)
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      content: message.content,
      message_type: message.message_type,
      sender: if(message.sender, do: serialize_user(message.sender), else: nil),
      reply_to: if(message.reply_to, do: %{id: message.reply_to.id, content: message.reply_to.content}, else: nil),
      inserted_at: message.inserted_at
    }
  end

  defp serialize_user(user) do
    %{
      id: user.id,
      display_name: user.display_name || user.email |> String.split("@") |> hd(),
      avatar_color: user.avatar_color || "#4a90d9"
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
