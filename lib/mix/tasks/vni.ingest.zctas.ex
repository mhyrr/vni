defmodule Mix.Tasks.Vni.Ingest.Zctas do
  @shortdoc "Download TIGER/Line ZCTA polygons and rebuild the ZIP crosswalk"

  @moduledoc """
  Loads Census ZIP Code Tabulation Areas and computes the ZIP-to-district
  crosswalk against the current maps.

      mix vni.ingest.zctas                  # ingest, then rebuild the crosswalk
      mix vni.ingest.zctas --crosswalk-only # recompute after a district ingest
      mix vni.ingest.zctas --force          # re-download the archive

  The archive is one national file of about 530 MB, cached under
  `priv/repo/data/tiger/zcta2025/` beside the district archives. The
  crosswalk is derived from geometry we already publish and is only true
  of the map it was computed against — rerun `--crosswalk-only` after any
  district ingest.

  Requires GDAL (`brew install gdal` provides ogr2ogr).
  """

  use Mix.Task

  alias VNI.Atlas.Postal

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :info)

    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [force: :boolean, cache_dir: :string, crosswalk_only: :boolean]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    unless opts[:crosswalk_only] do
      ingest_opts =
        []
        |> maybe_put(:cache_dir, opts[:cache_dir])
        |> maybe_put(:force_download, opts[:force])

      Mix.shell().info("Downloading and loading ZCTA polygons (TIGER #{Postal.vintage()})…")
      count = Postal.ingest!(ingest_opts)
      Mix.shell().info("Loaded #{count} ZCTAs.")
    end

    Mix.shell().info("Rebuilding the crosswalk…")
    pairs = Postal.rebuild_crosswalk!()
    coverage = Postal.coverage()

    Mix.shell().info(
      "#{pairs} ZCTA-district pairs from #{coverage.zctas} ZCTAs: " <>
        "#{coverage.resolved} resolve to a voting district " <>
        "(#{coverage.single} to one, #{coverage.split} split across several); " <>
        "#{coverage.zctas - coverage.resolved} resolve to none."
    )
  end

  defp maybe_put(options, _key, nil), do: options
  defp maybe_put(options, key, value), do: Keyword.put(options, key, value)
end
