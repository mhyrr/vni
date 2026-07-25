defmodule VNI.Atlas.Tiger do
  @moduledoc """
  The shared mechanics of pulling a Census TIGER/Line archive into a
  stream of GeoJSON features.

  Download to a cache, verify it is really a zip, shell out to GDAL for
  the projection and geometry-type normalisation, hand back a path to a
  GeoJSON sequence. Nothing here knows what the features mean — districts
  and ZCTAs both arrive this way and diverge at promotion.

  Requires GDAL (`brew install gdal` provides ogr2ogr).
  """

  @root "https://www2.census.gov/geo/tiger"

  @doc "The TIGER root, for building archive URLs."
  def source_root, do: @root

  @doc """
  Fetch `url` into `path` unless a valid archive is already cached there.

  A partial download lands on a temporary path and is only renamed once
  it verifies, so an interrupted fetch can never be mistaken for a cache
  hit on the next run.
  """
  def download!(url, path, force_download? \\ false) do
    if force_download? || !valid_zip?(path) do
      temporary_path = path <> ".download"
      File.rm(temporary_path)

      response =
        Req.get!(url,
          into: File.stream!(temporary_path),
          decode_body: false,
          receive_timeout: 600_000,
          connect_options: tls_connect_options()
        )

      if response.status != 200 || !valid_zip?(temporary_path) do
        File.rm(temporary_path)
        raise "failed to download Census archive #{url} (HTTP #{response.status})"
      end

      File.rename!(temporary_path, path)
    end

    path
  end

  @doc """
  Convert a cached TIGER archive to a newline-delimited GeoJSON sequence
  in EPSG:4326, every feature a MultiPolygon. Returns the output path;
  the caller deletes it.
  """
  def to_geojson_sequence!(archive, label) do
    ensure_ogr2ogr!()

    output_path =
      Path.join(
        System.tmp_dir!(),
        "vni-#{label}-#{System.unique_integer([:positive])}.geojsonl"
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

  @doc "Stream a GeoJSON sequence as decoded features."
  def stream_features!(path) do
    path
    |> File.stream!([], :line)
    |> Stream.map(&(&1 |> strip_record_separator() |> Jason.decode!()))
  end

  @doc "Normalise a decoded GeoJSON geometry to a MultiPolygon."
  def as_multi_polygon!(%Geo.MultiPolygon{} = geometry), do: geometry

  def as_multi_polygon!(%Geo.Polygon{} = geometry) do
    %Geo.MultiPolygon{coordinates: [geometry.coordinates], srid: geometry.srid}
  end

  def as_multi_polygon!(geometry) do
    raise "expected Polygon or MultiPolygon, got: #{inspect(geometry.__struct__)}"
  end

  def ensure_ogr2ogr! do
    if System.find_executable("ogr2ogr") == nil do
      raise "Census shape ingestion requires GDAL's ogr2ogr executable"
    end
  end

  defp strip_record_separator(<<0x1E, rest::binary>>), do: rest
  defp strip_record_separator(line), do: line

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

  # Mint's CAStore dependency is optional. Use the operating system's bundle
  # explicitly so a fresh seed works in both the macOS development environment
  # and a Debian release image without adding a dependency solely for certs.
  defp tls_connect_options do
    cert_path =
      Enum.find(
        ["/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"],
        &File.regular?/1
      )

    if cert_path,
      do: [transport_opts: [cacertfile: String.to_charlist(cert_path)]],
      else: []
  end
end
