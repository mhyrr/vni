defmodule VNI.Atlas.Census do
  @moduledoc """
  Census TIGER/Line congressional district ingestion.

  TIGER source archives are cached locally, converted to GeoJSON sequences by
  GDAL, and promoted through the Atlas context. The current bootstrap is
  deliberately limited to the 119th Congress.
  """

  alias VNI.Atlas
  alias VNI.Atlas.MapVersion

  @congress 119
  @vintage 2025
  @effective_from ~D[2025-01-03]
  @source_root "https://www2.census.gov/geo/tiger/TIGER2025/CD"

  @states [
    %{fips: "01", code: "AL", seats: 7},
    %{fips: "02", code: "AK", seats: 1},
    %{fips: "04", code: "AZ", seats: 9},
    %{fips: "05", code: "AR", seats: 4},
    %{fips: "06", code: "CA", seats: 52},
    %{fips: "08", code: "CO", seats: 8},
    %{fips: "09", code: "CT", seats: 5},
    %{fips: "10", code: "DE", seats: 1},
    %{fips: "12", code: "FL", seats: 28},
    %{fips: "13", code: "GA", seats: 14},
    %{fips: "15", code: "HI", seats: 2},
    %{fips: "16", code: "ID", seats: 2},
    %{fips: "17", code: "IL", seats: 17},
    %{fips: "18", code: "IN", seats: 9},
    %{fips: "19", code: "IA", seats: 4},
    %{fips: "20", code: "KS", seats: 4},
    %{fips: "21", code: "KY", seats: 6},
    %{fips: "22", code: "LA", seats: 6},
    %{fips: "23", code: "ME", seats: 2},
    %{fips: "24", code: "MD", seats: 8},
    %{fips: "25", code: "MA", seats: 9},
    %{fips: "26", code: "MI", seats: 13},
    %{fips: "27", code: "MN", seats: 8},
    %{fips: "28", code: "MS", seats: 4},
    %{fips: "29", code: "MO", seats: 8},
    %{fips: "30", code: "MT", seats: 2},
    %{fips: "31", code: "NE", seats: 3},
    %{fips: "32", code: "NV", seats: 4},
    %{fips: "33", code: "NH", seats: 2},
    %{fips: "34", code: "NJ", seats: 12},
    %{fips: "35", code: "NM", seats: 3},
    %{fips: "36", code: "NY", seats: 26},
    %{fips: "37", code: "NC", seats: 14},
    %{fips: "38", code: "ND", seats: 1},
    %{fips: "39", code: "OH", seats: 15},
    %{fips: "40", code: "OK", seats: 5},
    %{fips: "41", code: "OR", seats: 6},
    %{fips: "42", code: "PA", seats: 17},
    %{fips: "44", code: "RI", seats: 2},
    %{fips: "45", code: "SC", seats: 7},
    %{fips: "46", code: "SD", seats: 1},
    %{fips: "47", code: "TN", seats: 9},
    %{fips: "48", code: "TX", seats: 38},
    %{fips: "49", code: "UT", seats: 4},
    %{fips: "50", code: "VT", seats: 1},
    %{fips: "51", code: "VA", seats: 11},
    %{fips: "53", code: "WA", seats: 10},
    %{fips: "54", code: "WV", seats: 2},
    %{fips: "55", code: "WI", seats: 8},
    %{fips: "56", code: "WY", seats: 1}
  ]

  @doc "The pinned current-Congress source manifest."
  def current_manifest do
    Enum.map(@states, fn state ->
      Map.put(state, :source_url, source_url(state.fips))
    end)
  end

  @doc "Download and ingest all 435 voting districts for the 119th Congress."
  def seed_current!(opts \\ []) do
    ensure_ogr2ogr!()
    cache_dir = Keyword.get(opts, :cache_dir, default_cache_dir())
    force_download? = Keyword.get(opts, :force_download, false)
    File.mkdir_p!(cache_dir)

    total =
      Enum.reduce(current_manifest(), 0, fn state, total ->
        count = ingest_state!(state, cache_dir, force_download?)

        if count != state.seats do
          raise "#{state.code}: expected #{state.seats} districts, imported #{count}"
        end

        total + count
      end)

    if total != 435 do
      raise "expected 435 voting districts, imported #{total}"
    end

    %{congress: @congress, vintage: @vintage, states: length(@states), districts: total}
  end

  defp ingest_state!(state, cache_dir, force_download?) do
    assert_no_conflicting_current_map!(state.code)
    archive = archive_path(cache_dir, state.fips)
    download!(state.source_url, archive, force_download?)
    geojson = convert_to_geojson_sequence!(archive, state.fips)

    try do
      map_version = upsert_map_version!(state)
      count = import_geojson_sequence!(geojson, map_version)
      :ok = Atlas.refresh_district_geometries!(map_version)

      persisted_count = map_version |> Atlas.list_districts() |> length()

      if persisted_count != count do
        raise "#{state.code}: parsed #{count} districts but persisted #{persisted_count}"
      end

      count
    after
      File.rm(geojson)
    end
  end

  defp assert_no_conflicting_current_map!(state) do
    case Atlas.current_map_version(state, :congressional) do
      nil ->
        :ok

      %MapVersion{congress: @congress, effective_from: @effective_from} ->
        :ok

      %MapVersion{} = map_version ->
        raise """
        #{state} already has current map version #{map_version.id} for Congress \
        #{map_version.congress}; refusing to create an ambiguous current map
        """
    end
  end

  defp upsert_map_version!(state) do
    attrs = %{
      state: state.code,
      level: :congressional,
      congress: @congress,
      effective_from: @effective_from,
      source_url: state.source_url
    }

    case Atlas.upsert_map_version(attrs) do
      {:ok, map_version} ->
        map_version

      {:error, changeset} ->
        raise "invalid #{state.code} map version: #{inspect(changeset.errors)}"
    end
  end

  defp import_geojson_sequence!(path, map_version) do
    path
    |> File.stream!([], :line)
    |> Enum.reduce(0, fn line, count ->
      feature = line |> strip_record_separator() |> Jason.decode!()
      properties = Map.fetch!(feature, "properties")
      district_code = Map.fetch!(properties, "CD119FP")

      case district_number(district_code) do
        :not_a_district ->
          count

        number ->
          geometry =
            feature |> Map.fetch!("geometry") |> Geo.JSON.decode!() |> as_multi_polygon!()

          case Atlas.upsert_district(map_version, %{number: number, geom: geometry}) do
            {:ok, _district} ->
              count + 1

            {:error, changeset} ->
              raise "invalid district #{district_code}: #{inspect(changeset.errors)}"
          end
      end
    end)
  end

  # TIGER uses ZZ for land or water not assigned to a congressional district.
  defp district_number("ZZ"), do: :not_a_district
  defp district_number(code), do: String.to_integer(code)

  defp as_multi_polygon!(%Geo.MultiPolygon{} = geometry), do: geometry

  defp as_multi_polygon!(%Geo.Polygon{} = geometry) do
    %Geo.MultiPolygon{coordinates: [geometry.coordinates], srid: geometry.srid}
  end

  defp as_multi_polygon!(geometry) do
    raise "expected Polygon or MultiPolygon, got: #{inspect(geometry.__struct__)}"
  end

  defp strip_record_separator(<<0x1E, rest::binary>>), do: rest
  defp strip_record_separator(line), do: line

  defp download!(url, path, force_download?) do
    if force_download? || !valid_zip?(path) do
      temporary_path = path <> ".download"
      File.rm(temporary_path)

      response =
        Req.get!(url,
          into: File.stream!(temporary_path),
          decode_body: false,
          receive_timeout: 120_000
        )

      if response.status != 200 || !valid_zip?(temporary_path) do
        File.rm(temporary_path)
        raise "failed to download Census archive #{url} (HTTP #{response.status})"
      end

      File.rename!(temporary_path, path)
    end

    path
  end

  defp valid_zip?(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        signature = IO.binread(file, 4)
        File.close(file)
        signature in [<<0x50, 0x4B, 0x03, 0x04>>, <<0x50, 0x4B, 0x05, 0x06>>]

      {:error, _reason} ->
        false
    end
  end

  defp convert_to_geojson_sequence!(archive, fips) do
    output_path =
      Path.join(
        System.tmp_dir!(),
        "vni-cd#{@congress}-#{fips}-#{System.unique_integer([:positive])}.geojsonl"
      )

    args = [
      "-f",
      "GeoJSONSeq",
      output_path,
      "/vsizip/#{Path.expand(archive)}",
      "-t_srs",
      "EPSG:4326",
      "-nlt",
      "MULTIPOLYGON",
      "-overwrite"
    ]

    case System.cmd("ogr2ogr", args, stderr_to_stdout: true) do
      {_output, 0} -> output_path
      {output, status} -> raise "ogr2ogr failed for FIPS #{fips} (#{status}): #{output}"
    end
  end

  defp ensure_ogr2ogr! do
    if System.find_executable("ogr2ogr") == nil do
      raise "Census shape ingestion requires GDAL's ogr2ogr executable"
    end
  end

  defp archive_path(cache_dir, fips) do
    Path.join(cache_dir, "tl_#{@vintage}_#{fips}_cd#{@congress}.zip")
  end

  defp source_url(fips) do
    "#{@source_root}/tl_#{@vintage}_#{fips}_cd#{@congress}.zip"
  end

  defp default_cache_dir do
    Path.expand("priv/repo/data/tiger/cd#{@congress}")
  end
end
