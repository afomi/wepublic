defmodule Wepublic.Social.Gathering do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User
  alias Wepublic.Social.{Nation, Venue, GatheringAttendee}

  @statuses ["proposed", "confirmed", "completed", "cancelled"]

  schema "gatherings" do
    field :title, :string
    field :description, :string
    field :scheduled_at, :utc_datetime
    field :max_attendees, :integer
    field :status, :string, default: "proposed"
    field :trust_level_required, :integer, default: 5

    belongs_to :venue, Venue
    belongs_to :organizer, User
    belongs_to :nation, Nation
    has_many :attendees, GatheringAttendee

    timestamps(type: :utc_datetime)
  end

  def changeset(gathering, attrs) do
    gathering
    |> cast(attrs, [
      :title,
      :description,
      :scheduled_at,
      :max_attendees,
      :status,
      :trust_level_required,
      :venue_id,
      :organizer_id,
      :nation_id
    ])
    |> validate_required([:title, :organizer_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:max_attendees, greater_than: 0)
    |> validate_number(:trust_level_required, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_future_date()
    |> foreign_key_constraint(:venue_id)
    |> foreign_key_constraint(:organizer_id)
    |> foreign_key_constraint(:nation_id)
  end

  defp validate_future_date(changeset) do
    scheduled = get_change(changeset, :scheduled_at)

    if scheduled && DateTime.compare(scheduled, DateTime.utc_now()) != :gt do
      add_error(changeset, :scheduled_at, "must be in the future")
    else
      changeset
    end
  end

  def statuses, do: @statuses
end
