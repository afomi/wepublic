defmodule Wepublic.Geo.BoundaryService do
  @moduledoc """
  Service for fetching city/county boundaries from OpenStreetMap's Overpass API.

  Boundaries are cached in the location record as GeoJSON.
  """

  alias Wepublic.Geo
  alias Wepublic.Geo.Location

  @overpass_url "https://overpass-api.de/api/interpreter"

  # Cache duration: 30 days
  @cache_duration_days 30

  @doc """
  Fetches the boundary for a location if not cached or cache is stale.
  Returns {:ok, geojson} or {:error, reason}.
  """
  def fetch_boundary(%Location{} = location) do
    if should_refetch?(location) do
      fetch_and_cache_boundary(location)
    else
      {:ok, location.bounds_geojson}
    end
  end

  @doc """
  Forces a refresh of the boundary from OSM.
  """
  def refresh_boundary(%Location{} = location) do
    fetch_and_cache_boundary(location)
  end

  defp should_refetch?(%Location{bounds_geojson: nil}), do: true
  defp should_refetch?(%Location{bounds_fetched_at: nil}), do: true
  defp should_refetch?(%Location{bounds_fetched_at: fetched_at}) do
    cache_expires = DateTime.add(fetched_at, @cache_duration_days * 24 * 60 * 60, :second)
    DateTime.compare(DateTime.utc_now(), cache_expires) == :gt
  end

  defp fetch_and_cache_boundary(%Location{} = location) do
    case query_overpass(location) do
      {:ok, geojson} ->
        case Geo.update_location_bounds(location, geojson) do
          {:ok, _updated} -> {:ok, geojson}
          {:error, reason} -> {:error, {:cache_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_overpass(%Location{name: name, center_lat: lat, center_long: long}) do
    # Build Overpass query to find city boundary
    # Search for administrative boundary near the location
    query = build_overpass_query(name, lat, long)

    body = "data=#{URI.encode_www_form(query)}"

    request = Finch.build(
      :post,
      @overpass_url,
      [{"Content-Type", "application/x-www-form-urlencoded"}],
      body
    )

    case Finch.request(request, Wepublic.Finch, receive_timeout: 30_000) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        parse_overpass_response(response_body)

      {:ok, %Finch.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp build_overpass_query(name, lat, long) do
    # Extract city name (before any comma)
    city_name = name |> String.split(",") |> hd() |> String.trim()

    """
    [out:json][timeout:25];
    (
      relation["boundary"="administrative"]["admin_level"~"[678]"]["name"="#{city_name}"](around:10000,#{lat},#{long});
    );
    out geom;
    """
  end

  defp parse_overpass_response(body) do
    case Jason.decode(body) do
      {:ok, %{"elements" => elements}} when is_list(elements) and length(elements) > 0 ->
        geojson = convert_to_geojson(elements)
        {:ok, Jason.encode!(geojson)}

      {:ok, %{"elements" => []}} ->
        {:error, :no_boundary_found}

      {:ok, _} ->
        {:error, :unexpected_response}

      {:error, reason} ->
        {:error, {:json_parse_error, reason}}
    end
  end

  defp convert_to_geojson(elements) do
    features = Enum.flat_map(elements, fn element ->
      case element do
        %{"type" => "relation", "members" => members} = rel ->
          # Extract outer ways from the relation
          outer_coords = extract_outer_coordinates(members)
          if outer_coords != [] do
            [%{
              "type" => "Feature",
              "properties" => %{
                "name" => rel["tags"]["name"],
                "admin_level" => rel["tags"]["admin_level"]
              },
              "geometry" => %{
                "type" => "Polygon",
                "coordinates" => [outer_coords]
              }
            }]
          else
            []
          end

        %{"type" => "way", "geometry" => geometry} = way when is_list(geometry) ->
          coords = Enum.map(geometry, fn %{"lat" => lat, "lon" => lon} -> [lon, lat] end)
          [%{
            "type" => "Feature",
            "properties" => %{
              "name" => way["tags"]["name"]
            },
            "geometry" => %{
              "type" => "LineString",
              "coordinates" => coords
            }
          }]

        _ ->
          []
      end
    end)

    %{
      "type" => "FeatureCollection",
      "features" => features
    }
  end

  defp extract_outer_coordinates(members) do
    # Get all outer way geometries
    outer_ways = members
    |> Enum.filter(fn m -> m["role"] == "outer" && m["geometry"] end)
    |> Enum.flat_map(fn m -> m["geometry"] end)

    # Convert to coordinate pairs
    Enum.map(outer_ways, fn
      %{"lat" => lat, "lon" => lon} -> [lon, lat]
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
