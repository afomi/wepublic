defmodule Wepublic.Interactions do
  @moduledoc """
  Context module for user interactions: chat, conversations, and collaborations.

  Interaction Types:
  - Chat: 1:1 private DM between connected users
  - Conversation: N-player open chat, can be location-based
  - Collaborate: Topic-focused conversation with shared context
  """

  import Ecto.Query
  alias Wepublic.Repo
  alias Wepublic.Accounts
  alias Wepublic.Interactions.{Conversation, Participant, Message, Capability}

  # ============================================================================
  # Capabilities
  # ============================================================================

  @doc """
  Gets or creates capabilities for a user based on their verification level.
  """
  def ensure_capabilities(user) do
    verification_level = Accounts.User.verification_level(user)

    Capability.capabilities()
    |> Enum.each(fn cap_type ->
      required_level = Capability.required_verification_level(cap_type)

      case get_capability(user.id, cap_type) do
        nil ->
          # Create capability, unlock if requirements met
          attrs = %{
            user_id: user.id,
            capability: cap_type,
            enabled: verification_level >= required_level
          }
          attrs = if verification_level >= required_level do
            Map.put(attrs, :unlocked_at, DateTime.utc_now(:second))
          else
            attrs
          end

          %Capability{}
          |> Capability.changeset(attrs)
          |> Repo.insert()

        cap ->
          # Check if should be unlocked now
          if !Capability.unlocked?(cap) && verification_level >= required_level do
            cap
            |> Capability.unlock_changeset()
            |> Repo.update()
          end
      end
    end)

    list_capabilities(user.id)
  end

  def get_capability(user_id, capability_type) do
    Repo.get_by(Capability, user_id: user_id, capability: capability_type)
  end

  def list_capabilities(user_id) do
    Capability
    |> where([c], c.user_id == ^user_id)
    |> Repo.all()
  end

  def has_capability?(user_id, capability_type) do
    case get_capability(user_id, capability_type) do
      nil -> false
      cap -> Capability.unlocked?(cap)
    end
  end

  @doc """
  Returns the available interaction capabilities between two users.
  """
  def available_interactions(from_user_id, to_user_id) do
    are_connected = Accounts.connected?(from_user_id, to_user_id)

    capabilities = []

    # Chat requires connection
    capabilities = if are_connected && has_capability?(from_user_id, "chat") do
      ["chat" | capabilities]
    else
      capabilities
    end

    # Conversation is always available
    capabilities = if has_capability?(from_user_id, "conversation") do
      ["conversation" | capabilities]
    else
      capabilities
    end

    # Collaborate requires at least one shared interest or topic
    capabilities = if has_capability?(from_user_id, "collaborate") do
      ["collaborate" | capabilities]
    else
      capabilities
    end

    Enum.reverse(capabilities)
  end

  # ============================================================================
  # Conversations
  # ============================================================================

  @doc """
  Starts a new chat (1:1 DM) between two connected users.
  Returns existing chat if one already exists.
  """
  def start_chat(user_id, other_user_id) do
    # Check if chat already exists between these users
    case find_existing_chat(user_id, other_user_id) do
      nil ->
        Repo.transaction(fn ->
          {:ok, conversation} = create_conversation(%{type: "chat", visibility: "private"})

          {:ok, _} = add_participant(conversation.id, user_id, "owner")
          {:ok, _} = add_participant(conversation.id, other_user_id, "participant")

          conversation |> Repo.preload([:messages, participants: :user])
        end)

      conversation ->
        {:ok, conversation |> Repo.preload([:messages, participants: :user])}
    end
  end

  defp find_existing_chat(user_id, other_user_id) do
    # Find a chat where both users are participants
    from(c in Conversation,
      join: p1 in Participant, on: p1.conversation_id == c.id,
      join: p2 in Participant, on: p2.conversation_id == c.id,
      where: c.type == "chat",
      where: is_nil(c.ended_at),
      where: p1.user_id == ^user_id and is_nil(p1.left_at),
      where: p2.user_id == ^other_user_id and is_nil(p2.left_at),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Starts a new conversation (n-player).
  """
  def start_conversation(user_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      conversation_attrs = Map.merge(%{type: "conversation", visibility: "local"}, attrs)
      {:ok, conversation} = create_conversation(conversation_attrs)
      {:ok, _} = add_participant(conversation.id, user_id, "owner")

      conversation |> Repo.preload([:messages, participants: :user])
    end)
  end

  @doc """
  Starts a new collaboration around a topic.
  """
  def start_collaboration(user_id, topic, context \\ %{}) do
    Repo.transaction(fn ->
      {:ok, conversation} = create_conversation(%{
        type: "collaborate",
        topic: topic,
        context: context,
        visibility: "public"
      })
      {:ok, _} = add_participant(conversation.id, user_id, "owner")

      conversation |> Repo.preload([:messages, participants: :user])
    end)
  end

  def create_conversation(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def get_conversation(id) do
    Conversation
    |> Repo.get(id)
    |> Repo.preload([:participants, :messages, participants: :user])
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:participants, :messages, participants: :user])
  end

  @doc """
  Lists conversations for a user.
  """
  def list_user_conversations(user_id, opts \\ []) do
    type = Keyword.get(opts, :type)
    active_only = Keyword.get(opts, :active_only, true)

    query = from(c in Conversation,
      join: p in Participant, on: p.conversation_id == c.id,
      where: p.user_id == ^user_id,
      where: is_nil(p.left_at),
      order_by: [desc: c.updated_at],
      preload: [participants: :user]
    )

    query = if type do
      where(query, [c], c.type == ^type)
    else
      query
    end

    query = if active_only do
      where(query, [c], is_nil(c.ended_at))
    else
      query
    end

    Repo.all(query)
  end

  @doc """
  Lists local conversations at a location.
  """
  def list_local_conversations(location_id) do
    from(c in Conversation,
      where: c.location_id == ^location_id,
      where: c.visibility == "local",
      where: is_nil(c.ended_at),
      order_by: [desc: c.updated_at],
      preload: [participants: :user]
    )
    |> Repo.all()
  end

  @doc """
  End a conversation.
  """
  def end_conversation(conversation) do
    conversation
    |> Conversation.end_changeset()
    |> Repo.update()
  end

  # ============================================================================
  # Participants
  # ============================================================================

  def add_participant(conversation_id, user_id, role \\ "participant") do
    Participant.join_changeset(conversation_id, user_id, role)
    |> Repo.insert()
  end

  def remove_participant(conversation_id, user_id) do
    case get_participant(conversation_id, user_id) do
      nil -> {:error, :not_found}
      participant ->
        participant
        |> Participant.leave_changeset()
        |> Repo.update()
    end
  end

  def get_participant(conversation_id, user_id) do
    Repo.get_by(Participant, conversation_id: conversation_id, user_id: user_id)
  end

  def mark_as_read(conversation_id, user_id) do
    case get_participant(conversation_id, user_id) do
      nil -> {:error, :not_found}
      participant ->
        participant
        |> Participant.mark_read_changeset()
        |> Repo.update()
    end
  end

  def participant?(conversation_id, user_id) do
    case get_participant(conversation_id, user_id) do
      nil -> false
      p -> Participant.active?(p)
    end
  end

  # ============================================================================
  # Messages
  # ============================================================================

  @doc """
  Sends a message in a conversation.
  """
  def send_message(conversation_id, sender_id, content, opts \\ []) do
    reply_to_id = Keyword.get(opts, :reply_to_id)

    attrs = %{
      conversation_id: conversation_id,
      sender_id: sender_id,
      content: content,
      reply_to_id: reply_to_id
    }

    result = %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()

    case result do
      {:ok, message} ->
        # Update conversation's updated_at
        from(c in Conversation, where: c.id == ^conversation_id)
        |> Repo.update_all(set: [updated_at: DateTime.utc_now(:second)])

        message = Repo.preload(message, [:sender, :reply_to])

        # Broadcast to all participants
        broadcast_message(conversation_id, message, sender_id)

        {:ok, message}

      error ->
        error
    end
  end

  defp broadcast_message(conversation_id, message, sender_id) do
    # Get all participant user IDs except sender
    participant_ids =
      from(p in Participant,
        where: p.conversation_id == ^conversation_id,
        where: is_nil(p.left_at),
        where: p.user_id != ^sender_id,
        select: p.user_id
      )
      |> Repo.all()

    # Broadcast to each participant's personal topic
    Enum.each(participant_ids, fn user_id ->
      Phoenix.PubSub.broadcast(
        Wepublic.PubSub,
        "user:#{user_id}:messages",
        {:new_message, conversation_id, message}
      )
    end)
  end

  @doc """
  Subscribe to message notifications for a user.
  """
  def subscribe_to_messages(user_id) do
    Phoenix.PubSub.subscribe(Wepublic.PubSub, "user:#{user_id}:messages")
  end

  @doc """
  Sends a system message (e.g., "User joined the conversation").
  """
  def send_system_message(conversation_id, content, metadata \\ %{}) do
    Message.system_message_changeset(conversation_id, content, metadata)
    |> Repo.insert()
  end

  @doc """
  Lists messages in a conversation.
  """
  def list_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query = from(m in Message,
      where: m.conversation_id == ^conversation_id,
      where: is_nil(m.deleted_at),
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      preload: [:sender, :reply_to]
    )

    query = if before_id do
      where(query, [m], m.id < ^before_id)
    else
      query
    end

    Repo.all(query) |> Enum.reverse()
  end

  def get_message(id) do
    Message
    |> Repo.get(id)
    |> Repo.preload([:sender, :reply_to])
  end

  def delete_message(message) do
    message
    |> Message.delete_changeset()
    |> Repo.update()
  end

  @doc """
  Returns the count of unread messages for a user in a conversation.
  """
  def unread_count(conversation_id, user_id) do
    case get_participant(conversation_id, user_id) do
      nil -> 0
      %{last_read_at: nil} ->
        from(m in Message,
          where: m.conversation_id == ^conversation_id,
          where: is_nil(m.deleted_at),
          select: count(m.id)
        )
        |> Repo.one()

      %{last_read_at: last_read} ->
        from(m in Message,
          where: m.conversation_id == ^conversation_id,
          where: is_nil(m.deleted_at),
          where: m.inserted_at > ^last_read,
          select: count(m.id)
        )
        |> Repo.one()
    end
  end

  @doc """
  Returns total unread count across all conversations for a user.
  """
  def total_unread_count(user_id) do
    conversations = list_user_conversations(user_id)

    Enum.reduce(conversations, 0, fn conv, acc ->
      acc + unread_count(conv.id, user_id)
    end)
  end
end
