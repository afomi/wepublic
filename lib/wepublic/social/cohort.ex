defmodule Wepublic.Social.Cohort do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Social.{Nation, Membership}

  schema "cohorts" do
    field :name, :string
    field :enrollment_starts, :utc_datetime
    field :enrollment_ends, :utc_datetime
    field :max_members, :integer
    field :status, :string, default: "upcoming"

    belongs_to :nation, Nation
    has_many :memberships, Membership

    timestamps(type: :utc_datetime)
  end

  def changeset(cohort, attrs) do
    cohort
    |> cast(attrs, [
      :name,
      :enrollment_starts,
      :enrollment_ends,
      :max_members,
      :status,
      :nation_id
    ])
    |> validate_required([:name, :nation_id])
    |> validate_inclusion(:status, ["upcoming", "open", "closed", "active"])
    |> validate_number(:max_members, greater_than: 0)
    |> validate_enrollment_window()
    |> foreign_key_constraint(:nation_id)
  end

  defp validate_enrollment_window(changeset) do
    starts = get_field(changeset, :enrollment_starts)
    ends = get_field(changeset, :enrollment_ends)

    if starts && ends && DateTime.compare(starts, ends) != :lt do
      add_error(changeset, :enrollment_ends, "must be after enrollment starts")
    else
      changeset
    end
  end

  @doc """
  Checks if enrollment is currently open.
  """
  def enrollment_open?(%__MODULE__{status: "open"} = cohort) do
    now = DateTime.utc_now()

    cond do
      cohort.enrollment_starts && DateTime.compare(now, cohort.enrollment_starts) == :lt ->
        false

      cohort.enrollment_ends && DateTime.compare(now, cohort.enrollment_ends) == :gt ->
        false

      true ->
        true
    end
  end

  def enrollment_open?(_), do: false
end
