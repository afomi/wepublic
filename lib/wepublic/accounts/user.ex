defmodule Wepublic.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    # Identity fields
    field :did, :string
    field :website, :string
    field :display_name, :string
    field :avatar_color, :string, default: "#4a90d9"

    # GitHub OAuth fields
    field :github_id, :integer
    field :github_username, :string
    field :github_avatar_url, :string

    # DID verification
    field :did_verified_at, :utc_datetime
    field :did_verification_token, :string
    field :did_document_url, :string

    # Feed verification
    field :feed_url, :string
    field :feed_verified_at, :utc_datetime
    field :feed_title, :string
    field :feed_last_fetched_at, :utc_datetime

    # Onboarding
    field :onboarding_completed_at, :utc_datetime

    # Cryptographic identity (Ed25519 keypair)
    # Enables self-sovereign identity via did:key
    field :public_key, :binary
    field :did_key, :string

    # Global position (lat/long)
    field :position_lat, :float
    field :position_long, :float
    belongs_to :last_location, Wepublic.Geo.Location

    timestamps(type: :utc_datetime)
  end

  @verification_token_length 32

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Wepublic.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # If using Bcrypt, then further validate it is at most 72 bytes long
      |> validate_length(:password, max: 72, count: :bytes)
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  A user changeset for updating identity fields.
  """
  def identity_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:did, :website, :display_name, :avatar_color])
    |> validate_format(:did, ~r/^did:[a-z]+:.+$/, message: "must be a valid DID format")
    |> validate_format(:website, ~r/^https?:\/\/.+/, message: "must be a valid URL")
    |> validate_format(:avatar_color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color")
    |> maybe_validate_unique_did(opts)
  end

  defp maybe_validate_unique_did(changeset, opts) do
    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:did, Wepublic.Repo)
      |> unique_constraint(:did)
    else
      changeset
    end
  end

  @doc """
  A user changeset for OAuth registration/login.
  """
  def github_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :github_id, :github_username, :github_avatar_url, :display_name])
    |> validate_required([:email, :github_id])
    |> unique_constraint(:email)
    |> unique_constraint(:github_id)
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Wepublic.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  Changeset for starting DID verification.
  Generates a verification token the user must add to their DID document.
  """
  def did_verification_changeset(user, attrs) do
    user
    |> cast(attrs, [:did, :did_document_url])
    |> validate_required([:did])
    |> validate_format(:did, ~r/^did:web:.+$/, message: "must be a did:web identifier")
    |> put_verification_token()
    |> unique_constraint(:did)
  end

  defp put_verification_token(changeset) do
    if get_field(changeset, :did_verification_token) do
      changeset
    else
      token = :crypto.strong_rand_bytes(@verification_token_length) |> Base.url_encode64(padding: false)
      put_change(changeset, :did_verification_token, token)
    end
  end

  @doc """
  Marks DID as verified.
  """
  def did_verified_changeset(user) do
    change(user, did_verified_at: DateTime.utc_now(:second))
  end

  @doc """
  Changeset for feed verification.
  """
  def feed_changeset(user, attrs) do
    user
    |> cast(attrs, [:feed_url, :feed_title])
    |> validate_required([:feed_url])
    |> validate_format(:feed_url, ~r/^https?:\/\/.+/, message: "must be a valid URL")
  end

  @doc """
  Marks feed as verified.
  """
  def feed_verified_changeset(user, feed_title) do
    now = DateTime.utc_now(:second)

    change(user,
      feed_verified_at: now,
      feed_last_fetched_at: now,
      feed_title: feed_title
    )
  end

  @doc """
  Marks onboarding as complete.
  """
  def onboarding_complete_changeset(user) do
    change(user, onboarding_completed_at: DateTime.utc_now(:second))
  end

  @doc """
  Checks if the user has verified their DID.
  """
  def did_verified?(%__MODULE__{did_verified_at: verified}), do: not is_nil(verified)

  @doc """
  Checks if the user has verified their feed.
  """
  def feed_verified?(%__MODULE__{feed_verified_at: verified}), do: not is_nil(verified)

  @doc """
  Checks if onboarding is complete.
  """
  def onboarding_complete?(%__MODULE__{onboarding_completed_at: completed}), do: not is_nil(completed)

  @doc """
  Returns the verification level (0-2):
  - 0: Not verified
  - 1: DID or Feed verified
  - 2: Both verified
  """
  def verification_level(%__MODULE__{} = user) do
    did = if did_verified?(user), do: 1, else: 0
    feed = if feed_verified?(user), do: 1, else: 0
    did + feed
  end

  @doc """
  Changeset for registering a cryptographic keypair.
  The public key is stored, and did:key is derived from it.
  """
  def keypair_changeset(user, public_key) when is_binary(public_key) do
    did_key = Wepublic.Identity.public_key_to_did(public_key)

    user
    |> change(%{public_key: public_key, did_key: did_key})
    |> validate_required([:public_key, :did_key])
    |> unique_constraint(:did_key)
  end

  @doc """
  Checks if the user has a registered keypair.
  """
  def has_keypair?(%__MODULE__{public_key: pk}), do: not is_nil(pk)

  @doc """
  Returns the user's sovereign DID (did:key if available, otherwise did:web).
  did:key is preferred as it's fully self-sovereign.
  """
  def sovereign_did(%__MODULE__{did_key: did_key}) when not is_nil(did_key), do: did_key
  def sovereign_did(%__MODULE__{did: did}) when not is_nil(did), do: did
  def sovereign_did(_), do: nil
end
