defmodule VNI.Atlas.Census do
  @moduledoc """
  Census TIGER/Line congressional district ingestion.

  TIGER source archives are cached locally, converted to GeoJSON sequences by
  GDAL, and promoted through the Atlas context. Supported congresses:

    * 119 (current) — TIGER2025, per-state `tl_2025_{fips}_cd119.zip`
    * 118 — TIGER2023, per-state `tl_2023_{fips}_cd118.zip`
    * 117 — TIGER2021, one national `tl_2021_us_cd116.zip`

  The 117th Congress has no `cd117` TIGER layer: it was seated on the same
  lines as the 116th, so the Census Bureau kept publishing the `cd116`
  layer (TIGER2021 boundaries are as of 2021-01-01, two days before the
  117th convened — including the 2019 court-ordered NC redraw). That layer
  also predates the per-state file split, so it arrives as a single
  national archive routed to state map versions by `STATEFP`.

  Historical map versions are ingested pre-closed: `effective_until` is
  pinned to the day before the successor congress convened. Seat counts
  come from the decennial apportionment in force for the congress and are
  asserted per state and in total (435) on every run.
  """

  alias VNI.Atlas
  alias VNI.Atlas.MapVersion

  @current_congress 119
  @source_root "https://www2.census.gov/geo/tiger"

  # `session` is the congress number in the TIGER layer/file name — 116 for
  # our congress 117 (see moduledoc). `apportionment` picks the seat table.
  @congresses %{
    119 => %{
      vintage: 2025,
      session: 119,
      scope: :state,
      effective_from: ~D[2025-01-03],
      effective_until: nil,
      apportionment: 2020
    },
    118 => %{
      vintage: 2023,
      session: 118,
      scope: :state,
      effective_from: ~D[2023-01-03],
      effective_until: ~D[2025-01-02],
      apportionment: 2020
    },
    117 => %{
      vintage: 2021,
      session: 116,
      scope: :national,
      effective_from: ~D[2021-01-03],
      effective_until: ~D[2023-01-02],
      apportionment: 2010
    }
  }

  # Voting-seat counts per decennial apportionment: 2020 covers congresses
  # 118+, 2010 covers 113–117. Both columns sum to 435.
  @states [
    %{fips: "01", code: "AL", seats: %{2020 => 7, 2010 => 7}},
    %{fips: "02", code: "AK", seats: %{2020 => 1, 2010 => 1}},
    %{fips: "04", code: "AZ", seats: %{2020 => 9, 2010 => 9}},
    %{fips: "05", code: "AR", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "06", code: "CA", seats: %{2020 => 52, 2010 => 53}},
    %{fips: "08", code: "CO", seats: %{2020 => 8, 2010 => 7}},
    %{fips: "09", code: "CT", seats: %{2020 => 5, 2010 => 5}},
    %{fips: "10", code: "DE", seats: %{2020 => 1, 2010 => 1}},
    %{fips: "12", code: "FL", seats: %{2020 => 28, 2010 => 27}},
    %{fips: "13", code: "GA", seats: %{2020 => 14, 2010 => 14}},
    %{fips: "15", code: "HI", seats: %{2020 => 2, 2010 => 2}},
    %{fips: "16", code: "ID", seats: %{2020 => 2, 2010 => 2}},
    %{fips: "17", code: "IL", seats: %{2020 => 17, 2010 => 18}},
    %{fips: "18", code: "IN", seats: %{2020 => 9, 2010 => 9}},
    %{fips: "19", code: "IA", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "20", code: "KS", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "21", code: "KY", seats: %{2020 => 6, 2010 => 6}},
    %{fips: "22", code: "LA", seats: %{2020 => 6, 2010 => 6}},
    %{fips: "23", code: "ME", seats: %{2020 => 2, 2010 => 2}},
    %{fips: "24", code: "MD", seats: %{2020 => 8, 2010 => 8}},
    %{fips: "25", code: "MA", seats: %{2020 => 9, 2010 => 9}},
    %{fips: "26", code: "MI", seats: %{2020 => 13, 2010 => 14}},
    %{fips: "27", code: "MN", seats: %{2020 => 8, 2010 => 8}},
    %{fips: "28", code: "MS", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "29", code: "MO", seats: %{2020 => 8, 2010 => 8}},
    %{fips: "30", code: "MT", seats: %{2020 => 2, 2010 => 1}},
    %{fips: "31", code: "NE", seats: %{2020 => 3, 2010 => 3}},
    %{fips: "32", code: "NV", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "33", code: "NH", seats: %{2020 => 2, 2010 => 2}},
    %{fips: "34", code: "NJ", seats: %{2020 => 12, 2010 => 12}},
    %{fips: "35", code: "NM", seats: %{2020 => 3, 2010 => 3}},
    %{fips: "36", code: "NY", seats: %{2020 => 26, 2010 => 27}},
    %{fips: "37", code: "NC", seats: %{2020 => 14, 2010 => 13}},
    %{fips: "38", code: "ND", seats: %{2020 => 1, 2010 => 1}},
    %{fips: "39", code: "OH", seats: %{2020 => 15, 2010 => 16}},
    %{fips: "40", code: "OK", seats: %{2020 => 5, 2010 => 5}},
    %{fips: "41", code: "OR", seats: %{2020 => 6, 2010 => 5}},
    %{fips: "42", code: "PA", seats: %{2020 => 17, 2010 => 18}},
    %{fips: "44", code: "RI", seats: %{2020 => 2, 2010 => 2}},
    %{fips: "45", code: "SC", seats: %{2020 => 7, 2010 => 7}},
    %{fips: "46", code: "SD", seats: %{2020 => 1, 2010 => 1}},
    %{fips: "47", code: "TN", seats: %{2020 => 9, 2010 => 9}},
    %{fips: "48", code: "TX", seats: %{2020 => 38, 2010 => 36}},
    %{fips: "49", code: "UT", seats: %{2020 => 4, 2010 => 4}},
    %{fips: "50", code: "VT", seats: %{2020 => 1, 2010 => 1}},
    %{fips: "51", code: "VA", seats: %{2020 => 11, 2010 => 11}},
    %{fips: "53", code: "WA", seats: %{2020 => 10, 2010 => 10}},
    %{fips: "54", code: "WV", seats: %{2020 => 2, 2010 => 3}},
    %{fips: "55", code: "WI", seats: %{2020 => 8, 2010 => 8}},
    %{fips: "56", code: "WY", seats: %{2020 => 1, 2010 => 1}}
  ]

  def current_congress, do: @current_congress

  def supported_congresses, do: @congresses |> Map.keys() |> Enum.sort()

  @doc """
  The source manifest for a congress: one entry per state with the seat
  count in force and the TIGER archive it ingests from. National-scope
  congresses share one archive URL across every state.
  """
  def manifest(congress) do
    spec = congress_spec!(congress)

    Enum.map(@states, fn state ->
      %{
        fips: state.fips,
        code: state.code,
        seats: Map.fetch!(state.seats, spec.apportionment),
        source_url: source_url(spec, if(spec.scope == :state, do: state.fips))
      }
    end)
  end

  @doc "The pinned current-Congress source manifest."
  def current_manifest, do: manifest(@current_congress)

  @doc "Download and ingest all 435 voting districts for the current Congress."
  def seed_current!(opts \\ []), do: seed_congress!(@current_congress, opts)

  @doc "Download and ingest all 435 voting districts for a supported Congress."
  def seed_congress!(congress, opts \\ []) do
    spec = congress_spec!(congress)
    ensure_ogr2ogr!()
    cache_dir = Keyword.get(opts, :cache_dir, default_cache_dir(congress))
    force_download? = Keyword.get(opts, :force_download, false)
    File.mkdir_p!(cache_dir)

    total =
      case spec.scope do
        :state -> seed_from_state_archives!(congress, spec, cache_dir, force_download?)
        :national -> seed_from_national_archive!(congress, spec, cache_dir, force_download?)
      end

    if total != 435 do
      raise "expected 435 voting districts, imported #{total}"
    end

    %{congress: congress, vintage: spec.vintage, states: length(@states), districts: total}
  end

  ## Per-state archives (cd118+)

  defp seed_from_state_archives!(congress, spec, cache_dir, force_download?) do
    Enum.reduce(manifest(congress), 0, fn state, total ->
      count = ingest_state!(state, congress, spec, cache_dir, force_download?)

      if count != state.seats do
        raise "#{state.code}: expected #{state.seats} districts, imported #{count}"
      end

      total + count
    end)
  end

  defp ingest_state!(state, congress, spec, cache_dir, force_download?) do
    :ok = Atlas.assert_ingestable_map_version!(map_version_attrs(state, congress, spec))
    archive = Path.join(cache_dir, archive_name(spec, state.fips))
    download!(state.source_url, archive, force_download?)
    geojson = convert_to_geojson_sequence!(archive, congress, state.fips)

    try do
      map_version = upsert_map_version!(state, congress, spec)
      count = import_geojson_sequence!(geojson, map_version, spec)
      :ok = Atlas.refresh_district_geometries!(map_version)
      assert_persisted!(map_version, state.code, count)
      count
    after
      File.rm(geojson)
    end
  end

  defp import_geojson_sequence!(path, map_version, spec) do
    key = district_code_key(spec)

    path
    |> File.stream!([], :line)
    |> Enum.reduce(0, fn line, count ->
      feature = line |> strip_record_separator() |> Jason.decode!()

      case feature |> Map.fetch!("properties") |> Map.fetch!(key) |> district_number() do
        :not_a_district -> count
        number -> upsert_feature_district!(map_version, number, feature) && count + 1
      end
    end)
  end

  ## One national archive (cd116, the congress-117 lines)

  defp seed_from_national_archive!(congress, spec, cache_dir, force_download?) do
    url = source_url(spec, nil)
    manifest = manifest(congress)

    for state <- manifest do
      :ok = Atlas.assert_ingestable_map_version!(map_version_attrs(state, congress, spec))
    end

    archive = Path.join(cache_dir, archive_name(spec, nil))
    download!(url, archive, force_download?)
    geojson = convert_to_geojson_sequence!(archive, congress, "us")

    try do
      map_versions =
        Map.new(manifest, fn state ->
          {state.fips, upsert_map_version!(state, congress, spec)}
        end)

      counts = import_national_geojson_sequence!(geojson, map_versions, spec)

      Enum.reduce(manifest, 0, fn state, total ->
        map_version = Map.fetch!(map_versions, state.fips)
        :ok = Atlas.refresh_district_geometries!(map_version)
        count = Map.get(counts, state.fips, 0)

        if count != state.seats do
          raise "#{state.code}: expected #{state.seats} districts, imported #{count}"
        end

        assert_persisted!(map_version, state.code, count)
        total + count
      end)
    after
      File.rm(geojson)
    end
  end

  # One streaming pass over the national sequence, routing each feature to
  # its state's map version by STATEFP. Features outside the 50 voting
  # states (DC, PR, territories) fall through uncounted.
  defp import_national_geojson_sequence!(path, map_versions, spec) do
    key = district_code_key(spec)

    path
    |> File.stream!([], :line)
    |> Enum.reduce(%{}, fn line, counts ->
      feature = line |> strip_record_separator() |> Jason.decode!()
      properties = Map.fetch!(feature, "properties")
      fips = Map.fetch!(properties, "STATEFP")

      with %MapVersion{} = map_version <- Map.get(map_versions, fips),
           number when is_integer(number) <-
             properties |> Map.fetch!(key) |> district_number() do
        upsert_feature_district!(map_version, number, feature)
        Map.update(counts, fips, 1, &(&1 + 1))
      else
        _ -> counts
      end
    end)
  end

  ## Shared promotion

  defp map_version_attrs(state, congress, spec) do
    %{
      state: state.code,
      level: :congressional,
      congress: congress,
      effective_from: spec.effective_from,
      effective_until: spec.effective_until,
      source_url: state.source_url
    }
  end

  defp upsert_map_version!(state, congress, spec) do
    case Atlas.upsert_map_version(map_version_attrs(state, congress, spec)) do
      {:ok, map_version} ->
        map_version

      {:error, changeset} ->
        raise "invalid #{state.code} map version: #{inspect(changeset.errors)}"
    end
  end

  defp upsert_feature_district!(map_version, number, feature) do
    geometry = feature |> Map.fetch!("geometry") |> Geo.JSON.decode!() |> as_multi_polygon!()

    case Atlas.upsert_district(map_version, %{number: number, geom: geometry}) do
      {:ok, district} ->
        district

      {:error, changeset} ->
        raise "invalid district #{map_version.state}-#{number}: #{inspect(changeset.errors)}"
    end
  end

  defp assert_persisted!(map_version, state_code, count) do
    persisted_count = map_version |> Atlas.list_districts() |> length()

    if persisted_count != count do
      raise "#{state_code}: parsed #{count} districts but persisted #{persisted_count}"
    end

    :ok
  end

  defp district_code_key(spec), do: "CD#{spec.session}FP"

  # TIGER uses ZZ for land or water not assigned to a congressional
  # district and 98 for non-voting delegate seats (DC, PR, territories).
  defp district_number("ZZ"), do: :not_a_district
  defp district_number("98"), do: :not_a_district
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

  defp convert_to_geojson_sequence!(archive, congress, label) do
    output_path =
      Path.join(
        System.tmp_dir!(),
        "vni-cd#{congress}-#{label}-#{System.unique_integer([:positive])}.geojsonl"
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
      {output, status} -> raise "ogr2ogr failed for #{label} (#{status}): #{output}"
    end
  end

  defp ensure_ogr2ogr! do
    if System.find_executable("ogr2ogr") == nil do
      raise "Census shape ingestion requires GDAL's ogr2ogr executable"
    end
  end

  defp archive_name(spec, nil), do: "tl_#{spec.vintage}_us_cd#{spec.session}.zip"
  defp archive_name(spec, fips), do: "tl_#{spec.vintage}_#{fips}_cd#{spec.session}.zip"

  defp source_url(spec, fips) do
    "#{@source_root}/TIGER#{spec.vintage}/CD/#{archive_name(spec, fips)}"
  end

  defp congress_spec!(congress) do
    case Map.fetch(@congresses, congress) do
      {:ok, spec} ->
        spec

      :error ->
        raise ArgumentError,
              "unsupported congress #{inspect(congress)}; " <>
                "supported: #{inspect(supported_congresses())}"
    end
  end

  # Cache directories are keyed by our congress number; the archive inside
  # keeps its TIGER name (cd117's cache holds tl_2021_us_cd116.zip).
  defp default_cache_dir(congress) do
    Path.expand("priv/repo/data/tiger/cd#{congress}")
  end
end
