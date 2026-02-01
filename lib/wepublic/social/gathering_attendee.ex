defmodule Wepublic.Social.GatheringAttendee do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.Gathering

  @statuses ["interested", "confirmed", "attended", "no_show"]

  schema "gathering_attendees" do
    field :status, :string, default: "interested"
    field :checked_in_at, :utc_datetime
    field :safety_confirmed_at, :utc_datetime

    belongs_to :user, User
    belongs_to :gathering, Gathering

    timestamps(type: :utc_datetime)
  end

  def changeset(attendee, attrs) do
    attendee
    |> cast(attrs, [
      :status,
      :checked_in_at,
      :safety_confirmed_at,
      :user_id,
      :gathering_id
    ])
    |> validate_required([:user_id, :gathering_id])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:user_id, :gathering_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:gathering_id)
  end

  @doc """
  Checks if the attendee has confirmed their safety after the gathering.
  """
  def safety_confirmed?(%__MODULE__{safety_confirmed_at: confirmed}), do: not is_nil(confirmed)

  def statuses, do: @statuses
end
