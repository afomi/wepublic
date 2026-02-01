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
alias Wepublic.Geo.Location

# ============================================================================
# Seed Locations
# ============================================================================

IO.puts("Seeding locations...")

locations_data = [
  %{
    name: "Vacaville, CA",
    slug: "vacaville-ca",
    center_lat: 38.3566,
    center_long: -121.9877,
    location_type: "city"
  },
  %{
    name: "San Francisco, CA",
    slug: "san-francisco-ca",
    center_lat: 37.7749,
    center_long: -122.4194,
    location_type: "city"
  },
  %{
    name: "Vallejo, CA",
    slug: "vallejo-ca",
    center_lat: 38.1041,
    center_long: -122.2566,
    location_type: "city"
  },
  %{
    name: "Oakland, CA",
    slug: "oakland-ca",
    center_lat: 37.8044,
    center_long: -122.2712,
    location_type: "city"
  },
  %{
    name: "Sacramento, CA",
    slug: "sacramento-ca",
    center_lat: 38.5816,
    center_long: -121.4944,
    location_type: "city"
  }
]

locations =
  for location_data <- locations_data do
    case Repo.get_by(Location, slug: location_data.slug) do
      nil ->
        %Location{}
        |> Location.changeset(location_data)
        |> Repo.insert!()

      existing ->
        existing
    end
  end

IO.puts("Seeded #{length(locations)} locations:")
for loc <- locations do
  IO.puts("  - #{loc.name} (#{loc.center_lat}, #{loc.center_long})")
end

# ============================================================================
# Seed World Objects for each location
# ============================================================================

alias Wepublic.Geo.WorldObject

IO.puts("\nSeeding world objects...")

# Get locations by slug for reference
vacaville = Repo.get_by!(Location, slug: "vacaville-ca")
san_francisco = Repo.get_by!(Location, slug: "san-francisco-ca")
vallejo = Repo.get_by!(Location, slug: "vallejo-ca")
oakland = Repo.get_by!(Location, slug: "oakland-ca")
sacramento = Repo.get_by!(Location, slug: "sacramento-ca")

# Clear existing world objects to avoid duplicates
Repo.delete_all(WorldObject)

world_objects_data = [
  # Vacaville - Farm town theme (green pins, brown cubes)
  %{location_id: vacaville.id, object_type: "pin", position_x: 0.0, position_z: 0.0, color: "#22c55e", label: "Vacaville Center"},
  %{location_id: vacaville.id, object_type: "cube", position_x: 5.0, position_z: 3.0, color: "#92400e", label: "Barn"},
  %{location_id: vacaville.id, object_type: "cube", position_x: -4.0, position_z: 6.0, color: "#92400e", label: "Silo"},
  %{location_id: vacaville.id, object_type: "pin", position_x: 8.0, position_z: -5.0, color: "#22c55e", label: "Orchard"},
  %{location_id: vacaville.id, object_type: "pin", position_x: -10.0, position_z: -3.0, color: "#84cc16", label: "Farm Stand"},

  # San Francisco - Urban theme (blue/purple pins, gray cubes)
  %{location_id: san_francisco.id, object_type: "pin", position_x: 0.0, position_z: 0.0, color: "#f97316", label: "SF Center"},
  %{location_id: san_francisco.id, object_type: "cube", position_x: 6.0, position_z: 4.0, color: "#64748b", label: "Transamerica"},
  %{location_id: san_francisco.id, object_type: "cube", position_x: -5.0, position_z: 7.0, color: "#475569", label: "Salesforce Tower"},
  %{location_id: san_francisco.id, object_type: "cube", position_x: 3.0, position_z: -6.0, color: "#334155", label: "Coit Tower"},
  %{location_id: san_francisco.id, object_type: "pin", position_x: -8.0, position_z: -4.0, color: "#ec4899", label: "Painted Ladies"},
  %{location_id: san_francisco.id, object_type: "pin", position_x: 12.0, position_z: 0.0, color: "#f97316", label: "Ferry Building"},

  # Vallejo - Maritime theme (cyan pins, blue cubes)
  %{location_id: vallejo.id, object_type: "pin", position_x: 0.0, position_z: 0.0, color: "#06b6d4", label: "Vallejo Center"},
  %{location_id: vallejo.id, object_type: "cube", position_x: 4.0, position_z: 5.0, color: "#0284c7", label: "Mare Island"},
  %{location_id: vallejo.id, object_type: "pin", position_x: -6.0, position_z: 3.0, color: "#22d3ee", label: "Ferry Terminal"},
  %{location_id: vallejo.id, object_type: "cube", position_x: 7.0, position_z: -4.0, color: "#0369a1", label: "Shipyard"},

  # Oakland - Industrial theme (yellow pins, orange cubes)
  %{location_id: oakland.id, object_type: "pin", position_x: 0.0, position_z: 0.0, color: "#eab308", label: "Oakland Center"},
  %{location_id: oakland.id, object_type: "cube", position_x: 5.0, position_z: 6.0, color: "#ea580c", label: "Port Crane"},
  %{location_id: oakland.id, object_type: "cube", position_x: -7.0, position_z: 4.0, color: "#c2410c", label: "Container"},
  %{location_id: oakland.id, object_type: "pin", position_x: 9.0, position_z: -3.0, color: "#fbbf24", label: "Jack London Sq"},
  %{location_id: oakland.id, object_type: "pin", position_x: -4.0, position_z: -7.0, color: "#f59e0b", label: "Lake Merritt"},

  # Sacramento - Government theme (gold pins, white cubes)
  %{location_id: sacramento.id, object_type: "pin", position_x: 0.0, position_z: 0.0, color: "#fbbf24", label: "Sacramento Center"},
  %{location_id: sacramento.id, object_type: "cube", position_x: 3.0, position_z: 5.0, color: "#f5f5f4", label: "Capitol"},
  %{location_id: sacramento.id, object_type: "cube", position_x: -6.0, position_z: 3.0, color: "#e7e5e4", label: "Tower Bridge"},
  %{location_id: sacramento.id, object_type: "pin", position_x: 8.0, position_z: -2.0, color: "#d97706", label: "Old Sacramento"},
  %{location_id: sacramento.id, object_type: "pin", position_x: -3.0, position_z: -6.0, color: "#b45309", label: "Crocker Art"}
]

for obj_data <- world_objects_data do
  %WorldObject{}
  |> WorldObject.changeset(obj_data)
  |> Repo.insert!()
end

IO.puts("Seeded #{length(world_objects_data)} world objects across #{length(locations)} locations")

# ============================================================================
# Seed Users
# ============================================================================

# Seed 20 users for the neighborhood
# These users represent the initial population of the 3D space
# with varying verification levels and some with products for sale

avatar_colors = [
  "#d94a8a", "#8ad94a", "#d9a84a", "#4a90d9", "#9a4ad9",
  "#4ad9d9", "#d95a5a", "#5ad95a", "#d9d95a", "#5a5ad9",
  "#d98a4a", "#4ad98a", "#8a4ad9", "#d94a5a", "#4a5ad9",
  "#5ad94a", "#d94ad9", "#4ad94a", "#9ad94a", "#4a9ad9"
]

first_names = [
  "Alice", "Bob", "Carol", "David", "Emma",
  "Frank", "Grace", "Henry", "Ivy", "Jack",
  "Kate", "Leo", "Mia", "Noah", "Olivia",
  "Paul", "Quinn", "Ruby", "Sam", "Tara"
]

# Generate 20 users with varied verification status
users_data =
  for {name, index} <- Enum.with_index(first_names) do
    domain = String.downcase(name)
    color = Enum.at(avatar_colors, index)

    # Vary verification status:
    # - First 5 users: fully verified (DID + feed)
    # - Next 5 users: DID verified only
    # - Next 5 users: feed verified only
    # - Last 5 users: not verified
    {did_verified, feed_verified, has_products} =
      cond do
        index < 5 -> {true, true, rem(index, 2) == 0}
        index < 10 -> {true, false, false}
        index < 15 -> {false, true, rem(index, 3) == 0}
        true -> {false, false, false}
      end

    now = DateTime.utc_now(:second)

    base = %{
      email: "#{domain}@example.com",
      display_name: name,
      did: "did:web:#{domain}.example.com",
      website: "https://#{domain}.example.com",
      avatar_color: color,
      hashed_password: Bcrypt.hash_pwd_salt("password123456"),
      confirmed_at: now
    }

    # Add verification fields based on status
    base
    |> then(fn b ->
      if did_verified do
        Map.merge(b, %{
          did_verified_at: now,
          did_verification_token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
        })
      else
        b
      end
    end)
    |> then(fn b ->
      if feed_verified do
        Map.merge(b, %{
          feed_url: "https://#{domain}.example.com/feed.xml",
          feed_verified_at: now,
          feed_title: "#{name}'s Blog",
          feed_last_fetched_at: now
        })
      else
        b
      end
    end)
    |> Map.put(:_has_products, has_products)
  end

# Insert users and collect them for connections
users =
  for user_data <- users_data do
    # Remove internal flag before inserting
    {_has_products, insert_data} = Map.pop(user_data, :_has_products)

    case Repo.get_by(User, email: insert_data.email) do
      nil ->
        %User{}
        |> Ecto.Changeset.change(insert_data)
        |> Repo.insert!()

      existing ->
        existing
    end
  end

IO.puts("Seeded #{length(users)} users:")

for user <- users do
  verification =
    cond do
      user.did_verified_at && user.feed_verified_at -> "✓✓ (DID + Feed)"
      user.did_verified_at -> "✓ (DID)"
      user.feed_verified_at -> "✓ (Feed)"
      true -> "○ (unverified)"
    end

  IO.puts("  - #{user.display_name} #{verification}")
end

# Create some connections between users
# Build a small social network:
# - Alice is connected to Bob, Carol, David (neighbors)
# - Emma is connected to Frank, Grace (work colleagues)
# - Others have random connections

connection_pairs = [
  {0, 1},   # Alice <-> Bob
  {0, 2},   # Alice <-> Carol
  {0, 3},   # Alice <-> David
  {4, 5},   # Emma <-> Frank
  {4, 6},   # Emma <-> Grace
  {1, 2},   # Bob <-> Carol
  {7, 8},   # Henry <-> Ivy
  {9, 10},  # Jack <-> Kate
  {11, 12}, # Leo <-> Mia
  {13, 14}, # Noah <-> Olivia
  {3, 7},   # David <-> Henry
  {5, 9},   # Frank <-> Jack
  {6, 11},  # Grace <-> Leo
  {2, 8},   # Carol <-> Ivy
  {10, 15}  # Kate <-> Paul
]

IO.puts("\nCreating connections:")

for {from_idx, to_idx} <- connection_pairs do
  from_user = Enum.at(users, from_idx)
  to_user = Enum.at(users, to_idx)

  unless Repo.get_by(UserConnection, user_id: from_user.id, connected_user_id: to_user.id) do
    %UserConnection{}
    |> UserConnection.changeset(%{
      user_id: from_user.id,
      connected_user_id: to_user.id,
      status: "accepted"
    })
    |> Repo.insert!()

    IO.puts("  - #{from_user.display_name} <-> #{to_user.display_name}")
  end
end

IO.puts("\nSeeding complete!")
