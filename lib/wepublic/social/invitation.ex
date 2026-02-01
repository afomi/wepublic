defmodule Wepublic.Social.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.{Nation, Cohort}

  @token_length 32

  schema "invitations" do
    field :token, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :message, :string

    belongs_to :inviter, User
    belongs_to :invitee, User
    belongs_to :nation, Nation
    belongs_to :cohort, Cohort

    timestamps(type: :utc_datetime)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [
      :status,
      :expires_at,
      :message,
      :inviter_id,
      :invitee_id,
      :nation_id,
      :cohort_id
    ])
    |> validate_required([:inviter_id, :nation_id])
    |> validate_inclusion(:status, ["pending", "accepted", "expired"])
    |> put_token()
    |> put_default_expiry()
    |> unique_constraint(:token)
    |> foreign_key_constraint(:inviter_id)
    |> foreign_key_constraint(:invitee_id)
    |> foreign_key_constraint(:nation_id)
    |> foreign_key_constraint(:cohort_id)
  end

  defp put_token(changeset) do
    if get_field(changeset, :token) do
      changeset
    else
      put_change(changeset, :token, generate_token())
    end
  end

  defp put_default_expiry(changeset) do
    if get_field(changeset, :expires_at) do
      changeset
    else
      # Default: 7 days from now
      expires = DateTime.utc_now() |> DateTime.add(7, :day)
      put_change(changeset, :expires_at, expires)
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(@token_length)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Checks if the invitation is still valid.
  """
  def valid?(%__MODULE__{status: "pending", expires_at: expires}) do
    DateTime.compare(DateTime.utc_now(), expires) == :lt
  end

  def valid?(_), do: false
end
