defmodule VNI.Atlas.Geography do
  @moduledoc """
  Plain-language district location: the counties a district covers and its
  major places, from the Census 119th Congressional District relationship
  files — authoritative, block-aligned to the same geography as the CD119
  TIGER shapes, no geometry math to defend.

  Source files (under https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld/):

    * `tab20_cd11920_county20_natl.txt` — CD ↔ county overlaps
    * `tab20_cd11920_place20_natl.txt` — CD ↔ place overlaps

  Counties: every county with land in the district, ordered by land area
  within the district; `partial` marks counties the district doesn't
  fully contain (block-aligned areas, so whole = exact equality).

  Places: the district's top places ranked by population apportioned by
  land-area share (place ACS population × share of the place's land in
  the district). Populations come from the same ACS 5-year vintage as
  district population and are an ingest-internal ranking input — the
  stored rows carry names and partial flags only.
  """

  require Logger

  alias VNI.Atlas
  alias VNI.Atlas.{ACS, Census, District}
  alias VNI.Politics

  @source_root "https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld"
  @county_file "tab20_cd11920_county20_natl.txt"
  @place_file "tab20_cd11920_place20_natl.txt"

  @places_kept 8

  def source_url, do: @source_root

  @doc """
  Upsert counties and places per current district. Rerunnable; files are
  cached under `priv/repo/data/census-rel/`.

  Accepts `:county_rel` and `:place_rel` (raw file binaries) and
  `:place_populations` (map of place GEOID => population) for tests.
  Returns `%{ingested: n, skipped: n, missing_districts: [slug]}`.
  """
  def ingest!(opts \\ []) do
    county_rel = Keyword.get_lazy(opts, :county_rel, fn -> fetch_cached!(@county_file) end)
    place_rel = Keyword.get_lazy(opts, :place_rel, fn -> fetch_cached!(@place_file) end)

    populations =
      Keyword.get_lazy(opts, :place_populations, fn -> fetch_place_populations!(opts) end)

    counties = county_rel |> parse_rel("COUNTY") |> Enum.group_by(& &1.cd_geoid)
    places = place_rel |> parse_rel("PLACE") |> Enum.group_by(& &1.cd_geoid)
    state_codes = Map.new(Census.current_manifest(), &{&1.fips, &1.code})

    results =
      counties
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn cd_geoid ->
        with {:ok, slug} <- district_slug(cd_geoid, state_codes),
             %District{} = district <- Atlas.get_district_by_slug(slug) do
          {:ok, _profile} =
            Politics.upsert_profile(district, %{
              counties: district_counties(counties[cd_geoid]),
              places: district_places(Map.get(places, cd_geoid, []), populations),
              geography_source_url: @source_root
            })

          :ok
        else
          :skip ->
            :skipped

          nil ->
            {:ok, slug} = district_slug(cd_geoid, state_codes)
            Logger.warning("no current district for relationship geography #{slug}")
            {:missing, slug}
        end
      end)

    %{
      ingested: Enum.count(results, &(&1 == :ok)),
      skipped: Enum.count(results, &(&1 == :skipped)),
      missing_districts: for({:missing, slug} <- results, do: slug)
    }
  end

  # Every county with land inside the district, largest footprint first.
  defp district_counties(rows) do
    rows
    |> Enum.filter(&(&1.land_part > 0))
    |> Enum.sort_by(& &1.land_part, :desc)
    |> Enum.map(&%{name: &1.name, partial: &1.land_part < &1.land_total})
  end

  # Top places by population apportioned to the district by land share.
  defp district_places(rows, populations) do
    rows
    |> Enum.filter(&(&1.geoid != "" and &1.land_part > 0 and &1.land_total > 0))
    |> Enum.map(fn row ->
      share = row.land_part / row.land_total
      population = Map.get(populations, row.geoid, 0)
      {population * share, row, share}
    end)
    |> Enum.sort_by(fn {apportioned, _row, _share} -> apportioned end, :desc)
    |> Enum.take(@places_kept)
    |> Enum.map(fn {_apportioned, row, share} ->
      %{name: place_name(row.name), partial: share < 1.0}
    end)
  end

  # NAMELSAD carries the legal/statistical suffix ("Chicago city",
  # "Bethesda CDP"); the location line wants the plain name.
  defp place_name(namelsad) do
    namelsad
    |> String.replace(
      ~r/ (city|town|village|borough|CDP|municipality|comunidad|zona urbana)$/,
      ""
    )
  end

  # Relationship files are pipe-delimited with a UTF-8 BOM on the header.
  defp parse_rel(binary, other_geo) do
    [header | rows] =
      binary
      |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.map(&String.split(&1, "|"))

    col = header |> Enum.with_index() |> Map.new()
    at = fn row, name -> Enum.at(row, Map.fetch!(col, name)) end

    Enum.map(rows, fn row ->
      %{
        cd_geoid: at.(row, "GEOID_CD119_20"),
        geoid: at.(row, "GEOID_#{other_geo}_20"),
        name: at.(row, "NAMELSAD_#{other_geo}_20"),
        land_total: parse_area(at.(row, "AREALAND_#{other_geo}_20")),
        land_part: parse_area(at.(row, "AREALAND_PART"))
      }
    end)
  end

  defp parse_area(""), do: 0
  defp parse_area(value), do: String.to_integer(value)

  # CD GEOID = state FIPS + district code; "00" is at-large, "98" the
  # delegate/resident-commissioner code, non-manifest FIPS (DC, PR) skip.
  defp district_slug(<<fips::binary-size(2), district::binary-size(2)>>, state_codes) do
    with state when is_binary(state) <- Map.get(state_codes, fips, :skip),
         number when is_integer(number) <- district_number(district) do
      {:ok, District.build_slug(state, number)}
    else
      _ -> :skip
    end
  end

  defp district_number("98"), do: :skip
  defp district_number("ZZ"), do: :skip
  defp district_number(code), do: String.to_integer(code)

  defp fetch_cached!(name) do
    path = Path.expand("priv/repo/data/census-rel/#{name}")

    case File.read(path) do
      {:ok, data} ->
        data

      {:error, _reason} ->
        response =
          Req.get!("#{@source_root}/#{name}", receive_timeout: 300_000, decode_body: false)

        if response.status != 200 do
          raise "failed to download #{@source_root}/#{name} (HTTP #{response.status})"
        end

        File.mkdir_p!(Path.dirname(path))
        File.write!(path, response.body)
        response.body
    end
  end

  # Place GEOID => total population, from the same ACS vintage as the
  # district population ingest. Ranking input only; not stored.
  defp fetch_place_populations!(opts) do
    vintage = Keyword.get(opts, :vintage, ACS.default_vintage())

    key =
      opts[:key] || System.get_env("CENSUS_API_KEY") ||
        raise """
        The Census data API requires a key for place populations. Get a free
        one at https://api.census.gov/data/key_signup.html and export
        CENSUS_API_KEY.
        """

    response =
      Req.get!("https://api.census.gov/data/#{vintage}/acs/acs5",
        params: [get: "B01003_001E", for: "place:*", in: "state:*", key: key],
        receive_timeout: 300_000
      )

    with 200 <- response.status,
         [_header | rows] <- response.body do
      Map.new(rows, fn [population, state, place] ->
        {state <> place, String.to_integer(population)}
      end)
    else
      _ -> raise "ACS place-population request failed (HTTP #{response.status})"
    end
  end
end
