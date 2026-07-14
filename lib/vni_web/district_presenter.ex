defmodule VNIWeb.DistrictPresenter do
  @moduledoc """
  Turns current district records into the small, geometry-safe maps consumed
  by the public LiveViews.

  The presenter deliberately exposes only sourced shape data. Political
  fields join this contract after their own ingestion pipeline exists.
  """

  alias VNI.Atlas.District

  @state_names %{
    "AL" => "Alabama",
    "AK" => "Alaska",
    "AZ" => "Arizona",
    "AR" => "Arkansas",
    "CA" => "California",
    "CO" => "Colorado",
    "CT" => "Connecticut",
    "DE" => "Delaware",
    "FL" => "Florida",
    "GA" => "Georgia",
    "HI" => "Hawaii",
    "ID" => "Idaho",
    "IL" => "Illinois",
    "IN" => "Indiana",
    "IA" => "Iowa",
    "KS" => "Kansas",
    "KY" => "Kentucky",
    "LA" => "Louisiana",
    "ME" => "Maine",
    "MD" => "Maryland",
    "MA" => "Massachusetts",
    "MI" => "Michigan",
    "MN" => "Minnesota",
    "MS" => "Mississippi",
    "MO" => "Missouri",
    "MT" => "Montana",
    "NE" => "Nebraska",
    "NV" => "Nevada",
    "NH" => "New Hampshire",
    "NJ" => "New Jersey",
    "NM" => "New Mexico",
    "NY" => "New York",
    "NC" => "North Carolina",
    "ND" => "North Dakota",
    "OH" => "Ohio",
    "OK" => "Oklahoma",
    "OR" => "Oregon",
    "PA" => "Pennsylvania",
    "RI" => "Rhode Island",
    "SC" => "South Carolina",
    "SD" => "South Dakota",
    "TN" => "Tennessee",
    "TX" => "Texas",
    "UT" => "Utah",
    "VT" => "Vermont",
    "VA" => "Virginia",
    "WA" => "Washington",
    "WV" => "West Virginia",
    "WI" => "Wisconsin",
    "WY" => "Wyoming"
  }

  def present(%District{score: score, map_version: map_version} = district)
      when not is_nil(score) and not is_nil(map_version) do
    %{
      id: district.id,
      slug: district.slug,
      label: label(district.state, district.number),
      state: Map.get(@state_names, district.state, district.state),
      state_code: district.state,
      congress: map_version.congress,
      source_url: map_version.source_url,
      shape_path: svg_path(district.geom_simplified || district.geom),
      land_area: number(district.land_area_sqkm),
      perimeter: number(district.perimeter_km),
      composite: percent(score.composite),
      polsby_popper: percent(score.polsby_popper),
      reock: percent(score.reock),
      convex_hull: percent(score.convex_hull),
      schwartzberg: percent(score.schwartzberg),
      national_rank: score.national_rank,
      methodology_version: score.methodology_version,
      tone: compactness_tone(score.composite)
    }
  end

  def percent(nil), do: 0
  def percent(value), do: value |> Kernel.*(100) |> round()

  defp compactness_tone(value) when value < 0.25, do: :red
  defp compactness_tone(value) when value < 0.50, do: :yellow
  defp compactness_tone(value) when value < 0.75, do: :green
  defp compactness_tone(_value), do: :blue

  defp label(state, 0), do: "#{state}-AL"

  defp label(state, number),
    do: "#{state}-#{number |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp number(nil), do: "—"

  defp number(value) do
    value
    |> round()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp svg_path(nil), do: "M10 10H90V90H10Z"

  defp svg_path(%Geo.MultiPolygon{coordinates: polygons}) do
    polygons
    |> Enum.flat_map(& &1)
    |> normalized_path()
  end

  defp svg_path(%Geo.Polygon{coordinates: rings}), do: normalized_path(rings)

  defp normalized_path(rings) do
    points = List.flatten(rings)
    {min_x, max_x, min_y, max_y} = bounds(points)
    width = max(max_x - min_x, 0.000_001)
    height = max(max_y - min_y, 0.000_001)
    scale = min(88 / width, 88 / height)
    offset_x = 6 + (88 - width * scale) / 2
    offset_y = 6 + (88 - height * scale) / 2

    Enum.map_join(rings, "", fn ring ->
      ring
      |> Enum.with_index()
      |> Enum.map_join("", fn {{x, y}, index} ->
        command = if index == 0, do: "M", else: "L"
        px = offset_x + (x - min_x) * scale
        py = offset_y + (max_y - y) * scale
        command <> coordinate(px) <> " " <> coordinate(py)
      end)
      |> Kernel.<>("Z")
    end)
  end

  defp bounds([{x, y} | points]) do
    Enum.reduce(points, {x, x, y, y}, fn {px, py}, {min_x, max_x, min_y, max_y} ->
      {min(min_x, px), max(max_x, px), min(min_y, py), max(max_y, py)}
    end)
  end

  defp coordinate(value), do: :erlang.float_to_binary(value, decimals: 2)
end
