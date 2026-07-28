defmodule Mix.Tasks.Vni.Promote.Export do
  @shortdoc "Write the derived data production cannot rebuild into priv/promotion"

  @moduledoc """
  Exports the ZIP crosswalk and district margins for promotion to production.

      mix vni.promote.export           # write priv/promotion
      mix vni.promote.export --dir DIR # write somewhere else

  Production cannot recompute any of this: the crosswalk needs 884 MB of
  ZCTA polygons and GDAL, and margins need the MEDSL archive. The release
  loads whatever is committed under `priv/promotion` — so the artifact is
  part of the deploy, and running this without committing the result
  changes nothing about what production serves.

  Run after any ingest that moves districts, margins, or the crosswalk.
  See `VNI.Promotion` for what travels and why, and
  `docs/deployment/fly.md` for the promotion procedure around it.
  """

  use Mix.Task

  alias VNI.Promotion

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :info)

    {opts, _, invalid} = OptionParser.parse(args, strict: [dir: :string])

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    dir = opts[:dir] || Path.join(File.cwd!(), "priv/promotion")

    for {_name, {path, rows}} <- Promotion.export!(dir) do
      Mix.shell().info("#{relative(path)}  #{rows} rows  #{size(path)}")
    end

    Mix.shell().info("\nCommit these — the release loads what is in the image.")
  end

  defp relative(path), do: Path.relative_to(path, File.cwd!())

  defp size(path) do
    bytes = File.stat!(path).size
    "#{Float.round(bytes / 1024, 1)} KB"
  end
end
