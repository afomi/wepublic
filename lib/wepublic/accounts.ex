defmodule Wepublic.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Wepublic.Repo

  alias Wepublic.Accounts.{User, UserToken, UserNotifier, UserConnection}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by GitHub ID.

  ## Examples

      iex> get_user_by_github_id(12345)
      %User{}

      iex> get_user_by_github_id(99999)
      nil

  """
  def get_user_by_github_id(github_id) when is_integer(github_id) do
    Repo.get_by(User, github_id: github_id)
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Wepublic.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Wepublic.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## User Connections

  @doc """
  Requests a connection from one user to another.
  """
  def request_connection(%User{} = from_user, %User{} = to_user) do
    %UserConnection{}
    |> UserConnection.changeset(%{user_id: from_user.id, connected_user_id: to_user.id})
    |> Repo.insert()
  end

  @doc """
  Accepts a pending connection request.
  """
  def accept_connection(%UserConnection{} = connection) do
    connection
    |> UserConnection.changeset(%{status: "accepted"})
    |> Repo.update()
  end

  @doc """
  Lists all accepted connections for a user.
  """
  def list_connections(%User{} = user) do
    query =
      from c in UserConnection,
        where: (c.user_id == ^user.id or c.connected_user_id == ^user.id) and c.status == "accepted",
        preload: [:user, :connected_user]

    Repo.all(query)
  end

  @doc """
  Checks if two users are connected (bidirectional).
  """
  def connected?(%User{} = user1, %User{} = user2) do
    query =
      from c in UserConnection,
        where:
          ((c.user_id == ^user1.id and c.connected_user_id == ^user2.id) or
             (c.user_id == ^user2.id and c.connected_user_id == ^user1.id)) and
            c.status == "accepted"

    Repo.exists?(query)
  end

  @doc """
  Lists connections for a user with their online status.
  Returns connections sorted with online users first.
  """
  def list_connections_with_presence(%User{} = user) do
    connections = list_connections(user)
    online_user_ids = get_online_user_ids()

    connections
    |> Enum.map(fn conn ->
      # Get the other user in the connection
      other_user =
        if conn.user_id == user.id,
          do: conn.connected_user,
          else: conn.user

      %{
        user: other_user,
        online: MapSet.member?(online_user_ids, other_user.id),
        connected_at: conn.inserted_at
      }
    end)
    |> Enum.sort_by(fn %{online: online} -> if online, do: 0, else: 1 end)
  end

  defp get_online_user_ids do
    WepublicWeb.Presence.list_users("map")
    |> Enum.map(fn meta ->
      case meta.user_id do
        "user_" <> id -> String.to_integer(id)
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  ## Verification

  @doc """
  Starts DID verification by setting the DID and generating a verification token.
  """
  def start_did_verification(%User{} = user, did) do
    user
    |> User.did_verification_changeset(%{did: did})
    |> Repo.update()
  end

  @doc """
  Updates the user's feed URL.
  """
  def update_feed_url(%User{} = user, feed_url) do
    user
    |> User.feed_changeset(%{feed_url: feed_url})
    |> Repo.update()
  end

  @doc """
  Marks onboarding as complete for the user.
  """
  def complete_onboarding(%User{} = user) do
    user
    |> User.onboarding_complete_changeset()
    |> Repo.update()
  end

  @doc """
  Gets all verified users with their verification data.
  Used for displaying verification indicators on the map.
  """
  def list_verified_users do
    from(u in User,
      where: not is_nil(u.did_verified_at) or not is_nil(u.feed_verified_at),
      select: %{
        id: u.id,
        display_name: u.display_name,
        avatar_color: u.avatar_color,
        did_verified: not is_nil(u.did_verified_at),
        feed_verified: not is_nil(u.feed_verified_at),
        has_products: false
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets user data for presence/map display including verification status.
  """
  def get_user_map_data(%User{} = user) do
    %{
      id: user.id,
      display_name: user.display_name || user.email |> String.split("@") |> hd(),
      avatar_color: user.avatar_color || "#4a90d9",
      verification_level: User.verification_level(user),
      did_verified: User.did_verified?(user),
      feed_verified: User.feed_verified?(user),
      has_products: check_has_products(user)
    }
  end

  defp check_has_products(%User{feed_verified_at: nil}), do: false

  defp check_has_products(%User{} = _user) do
    # Cache this check to avoid fetching feed on every request
    # For now, return false - would be populated by a background job
    false
  end
end
