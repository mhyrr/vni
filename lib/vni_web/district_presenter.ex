defmodule VNIWeb.DistrictPresenter do
  @moduledoc """
  Turns current district records into the small, geometry-safe maps consumed
  by the public LiveViews.

  Every exposed fact is sourced: shape data cites the Census map version,
  incumbent facts cite the legislators dataset, population cites its ACS
  request. Profile fields are nil until their ingest has run — templates
  render only what the record supports.
  """

  alias VNI.Atlas.District
  alias VNI.Politics.DistrictProfile

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

  @doc """
  Present a whole current field at once: the ranked denominator is counted
  from the set itself, so "of N" always matches the published ranking.
  """
  def present_field(districts) do
    ranked_total = Enum.count(districts, & &1.score.national_rank)
    Enum.map(districts, &present(&1, ranked_total))
  end

  def present(district, ranked_total \\ nil)

  def present(%District{score: score, map_version: map_version} = district, ranked_total)
      when not is_nil(score) and not is_nil(map_version) do
    %{
      id: district.id,
      slug: district.slug,
      label: label(district.state, district.number),
      at_large: district.number == 0,
      state: Map.get(@state_names, district.state, district.state),
      state_code: district.state,
      congress: map_version.congress,
      source_url: map_version.source_url,
      shape_path: svg_path(district.geom_simplified || district.geom),
      land_area: number(district.land_area_sqkm),
      perimeter: number(district.perimeter_km),
      composite: score.composite && percent(score.composite),
      polsby_popper: percent(score.polsby_popper),
      reock: percent(score.reock),
      convex_hull: percent(score.convex_hull),
      schwartzberg: percent(score.schwartzberg),
      national_rank: score.national_rank,
      ranked_total: ranked_total,
      methodology_version: score.methodology_version,
      tone: compactness_tone(score.composite)
    }
    |> Map.merge(authorship_fields(map_version))
    |> Map.merge(profile_fields(district.profile))
  end

  # Map authorship, exactly as curated: the institution that drew the
  # current map and the party in control of that process at adoption.
  defp authorship_fields(map_version) do
    %{
      map_authority: authority_label(map_version.authority),
      map_authority_short: authority_short(map_version.authority),
      map_controlling_party: controlling_party_label(map_version.controlling_party),
      map_controlling_party_key: map_version.controlling_party,
      map_controlling_party_short: controlling_party_short(map_version.controlling_party),
      authorship_source_url: map_version.authorship_source_url
    }
  end

  defp authority_label(:legislature), do: "the state legislature"
  defp authority_label(:independent_commission), do: "an independent commission"
  defp authority_label(:politician_commission), do: "a politician commission"
  defp authority_label(:court), do: "the state court"
  defp authority_label(:special_master), do: "a court-appointed special master"
  defp authority_label(nil), do: nil

  defp authority_short(:legislature), do: "Legislature"
  defp authority_short(:independent_commission), do: "Ind. commission"
  defp authority_short(:politician_commission), do: "Pol. commission"
  defp authority_short(:court), do: "Court"
  defp authority_short(:special_master), do: "Special master"
  defp authority_short(nil), do: nil

  defp controlling_party_label(:dem), do: "Democrats in control at adoption"
  defp controlling_party_label(:rep), do: "Republicans in control at adoption"
  defp controlling_party_label(:split), do: "control split between the parties"
  defp controlling_party_label(:nonpartisan), do: "no party in control"
  defp controlling_party_label(nil), do: nil

  # The hover strip carries the party letter only where a party held the
  # pen; commissions and courts speak through the authority label alone.
  defp controlling_party_short(:dem), do: "D"
  defp controlling_party_short(:rep), do: "R"
  defp controlling_party_short(_other), do: nil

  # Published facts only, exactly as ingested: party stays the raw letter,
  # tenure is arithmetic (current year minus first year in office).
  defp profile_fields(%DistrictProfile{} = profile) do
    %{
      incumbent_name: profile.incumbent_name,
      incumbent_party: party_letter(profile.incumbent_party),
      incumbent_party_key: profile.incumbent_party,
      incumbent_since: profile.incumbent_since,
      incumbent_tenure: tenure(profile.incumbent_since),
      incumbent_source_url: profile.incumbent_source_url,
      population: profile.population && number(profile.population),
      voting_age_population:
        profile.voting_age_population && number(profile.voting_age_population),
      acs_vintage: profile.acs_vintage,
      population_source_url: profile.population_source_url,
      last_margin: margin(profile.last_margin_pct),
      last_margin_cycle: profile.last_margin_cycle,
      last_margin_party: party_letter(profile.last_margin_party),
      last_margin_party_key: profile.last_margin_party,
      unopposed: profile.last_margin_pct == 100.0,
      margin_source_url: profile.margin_source_url,
      partisan_lean: lean_label(profile.partisan_lean),
      partisan_lean_party_key: lean_party(profile.partisan_lean),
      lean_tone: lean_tone(profile.partisan_lean),
      lean_intensity: lean_intensity(profile.partisan_lean),
      lean_source_url: profile.lean_source_url,
      county_line: geography_line(profile.counties, 3),
      place_line: geography_line(profile.places, 4),
      geography_source_url: profile.geography_source_url
    }
  end

  defp profile_fields(_missing_or_not_loaded) do
    %{
      incumbent_name: nil,
      incumbent_party: nil,
      incumbent_party_key: nil,
      incumbent_since: nil,
      incumbent_tenure: nil,
      incumbent_source_url: nil,
      population: nil,
      voting_age_population: nil,
      acs_vintage: nil,
      population_source_url: nil,
      last_margin: nil,
      last_margin_cycle: nil,
      last_margin_party: nil,
      last_margin_party_key: nil,
      unopposed: false,
      margin_source_url: nil,
      partisan_lean: nil,
      partisan_lean_party_key: nil,
      lean_tone: :neutral,
      lean_intensity: nil,
      lean_source_url: nil,
      county_line: nil,
      place_line: nil,
      geography_source_url: nil
    }
  end

  # Winning margin in display form: one decimal, in points.
  defp margin(nil), do: nil
  defp margin(pct), do: :erlang.float_to_binary(pct / 1, decimals: 1)

  # Lean reads R+n / D+n — our formula's sign convention (positive = more
  # Republican than the nation). A district on the national number is EVEN.
  defp lean_label(nil), do: nil

  defp lean_label(lean) do
    case round(lean) do
      0 -> "EVEN"
      n when n > 0 -> "R+#{n}"
      n -> "D+#{-n}"
    end
  end

  defp lean_party(nil), do: nil

  defp lean_party(lean) do
    case round(lean) do
      0 -> nil
      n when n > 0 -> :rep
      _n -> :dem
    end
  end

  # Lean color grammar: party hue carries the direction of the evidence,
  # depth of color carries its size. Unknown and EVEN districts stay paper.
  defp lean_tone(nil), do: :neutral

  defp lean_tone(lean) do
    case round(lean) do
      0 -> :neutral
      n when n > 0 -> :red
      _n -> :blue
    end
  end

  # Fill opacity in [0.2, 1.0]; the scale saturates at ±30 points so a
  # handful of extreme districts don't flatten everything else to pastel.
  defp lean_intensity(nil), do: nil

  defp lean_intensity(lean) do
    magnitude = min(abs(lean / 1), 30.0)
    Float.round(0.2 + 0.8 * magnitude / 30.0, 2)
  end

  # "Cook County (part) · Lake County" — ingested order, trimmed for the
  # location line, with the overflow counted instead of dropped silently.
  defp geography_line(nil, _keep), do: nil
  defp geography_line([], _keep), do: nil

  defp geography_line(entries, keep) do
    {shown, rest} = Enum.split(entries, keep)

    line =
      Enum.map_join(shown, " · ", fn entry ->
        if entry["partial"], do: "#{entry["name"]} (part)", else: entry["name"]
      end)

    case rest do
      [] -> line
      more -> line <> " · +#{length(more)} more"
    end
  end

  defp party_letter(:dem), do: "D"
  defp party_letter(:rep), do: "R"
  defp party_letter(:ind), do: "I"
  defp party_letter(nil), do: nil

  defp tenure(nil), do: nil
  defp tenure(since), do: Date.utc_today().year - since

  def percent(nil), do: 0
  def percent(value), do: value |> Kernel.*(100) |> round()

  defp compactness_tone(nil), do: :neutral
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
