defmodule Wepublic.Accounts.UserConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wepublic.Accounts.User

  schema "user_connections" do
    field :status, :string, default: "pending"

    belongs_to :user, User
    belongs_to :connected_user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a connection request.
  """
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:user_id, :connected_user_id, :status])
    |> validate_required([:user_id, :connected_user_id])
    |> validate_inclusion(:status, ["pending", "accepted", "blocked"])
    |> validate_different_users()
    |> unique_constraint([:user_id, :connected_user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:connected_user_id)
  end

  defp validate_different_users(changeset) do
    user_id = get_field(changeset, :user_id)
    connected_user_id = get_field(changeset, :connected_user_id)

    if user_id && connected_user_id && user_id == connected_user_id do
      add_error(changeset, :connected_user_id, "cannot connect to yourself")
    else
      changeset
    end
  end
end
