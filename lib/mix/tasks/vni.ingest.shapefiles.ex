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
    {opts, _, _} = OptionParser.parse(args, strict: [congress: :integer])
    congress = opts[:congress] || Mix.raise("--congress is required, e.g. --congress 119")

    Mix.raise("""
    Not implemented yet. Will ingest TIGER/Line CD#{congress} shapefiles:
    download → ogr2ogr staging table → promote to districts under a
    congress-#{congress} map version per state.
    """)
  end
end
