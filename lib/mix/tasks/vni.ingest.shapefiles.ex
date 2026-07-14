defmodule Mix.Tasks.Vni.Ingest.Shapefiles do
  @shortdoc "Download TIGER/Line congressional district shapefiles into PostGIS"

  @moduledoc """
  Downloads Census TIGER/Line district geometries and loads them into the
  Atlas under a map version.

      mix vni.ingest.shapefiles --congress 119

  Pipeline (per the ingest design): fetch the TIGER CD shapefile, shell out
  to ogr2ogr into a staging table, then Ecto-managed promotion into
  `districts` with `geom_simplified` precomputed via
  ST_SimplifyPreserveTopology(geom, 0.005). Idempotent — reruns upsert.

  Requires GDAL (`brew install gdal` provides ogr2ogr).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :info)

    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [congress: :integer, cache_dir: :string, force: :boolean]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    congress = opts[:congress] || Mix.raise("--congress is required, e.g. --congress 119")

    if congress != 119 do
      Mix.raise("only the current 119th Congress importer is implemented")
    end

    ingest_opts =
      []
      |> maybe_put(:cache_dir, opts[:cache_dir])
      |> maybe_put(:force_download, opts[:force])

    summary = VNI.Atlas.Census.seed_current!(ingest_opts)

    Mix.shell().info(
      "Imported #{summary.districts} districts across #{summary.states} states " <>
        "from TIGER/Line #{summary.vintage} (Congress #{summary.congress})."
    )
  end

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
end
