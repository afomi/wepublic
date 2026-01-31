# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Wepublic.Repo.insert!(%Wepublic.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Wepublic.Repo
alias Wepublic.Accounts.{User, UserConnection}

# Seed users matching the neighborhood.js figures
# These users represent the initial population of the 3D space

users_data = [
  %{
    email: "alice@example.com",
    display_name: "Alice",
    did: "did:web:alice.example.com",
    website: "https://alice.example.com",
    avatar_color: "#d94a8a",
    hashed_password: Bcrypt.hash_pwd_salt("password123456")
  },
  %{
    email: "bob@example.com",
    display_name: "Bob",
    did: "did:web:bob.example.com",
    website: "https://bob.example.com",
    avatar_color: "#8ad94a",
    hashed_password: Bcrypt.hash_pwd_salt("password123456")
  },
  %{
    email: "carol@example.com",
    display_name: "Carol",
    did: "did:web:carol.example.com",
    website: "https://carol.example.com",
    avatar_color: "#d9a84a",
    hashed_password: Bcrypt.hash_pwd_salt("password123456")
  }
]

# Insert users and collect them for connections
users =
  for user_data <- users_data do
    case Repo.get_by(User, email: user_data.email) do
      nil ->
        now = DateTime.utc_now(:second)

        %User{}
        |> Ecto.Changeset.change(Map.put(user_data, :confirmed_at, now))
        |> Repo.insert!()

      existing ->
        existing
    end
  end

IO.puts("Seeded #{length(users)} users: #{Enum.map_join(users, ", ", & &1.display_name)}")

# Create a connection between Alice and Bob (they are neighbors)
[alice, bob, _carol] = users

unless Repo.get_by(UserConnection, user_id: alice.id, connected_user_id: bob.id) do
  %UserConnection{}
  |> UserConnection.changeset(%{
    user_id: alice.id,
    connected_user_id: bob.id,
    status: "accepted"
  })
  |> Repo.insert!()

  IO.puts("Created connection: #{alice.display_name} <-> #{bob.display_name}")
end
