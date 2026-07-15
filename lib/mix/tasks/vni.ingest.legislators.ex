defmodule Mix.Tasks.Vni.Ingest.Legislators do
  @shortdoc "Ingest incumbents from unitedstates/congress-legislators"

  @moduledoc """
  Pulls the public-domain `unitedstates/congress-legislators` YAML and
  upserts district profiles (incumbent, party, first-elected year,
  bioguide id). Rerunnable — upserts key on district identity.

      mix vni.ingest.legislators
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Ingesting #{VNI.Politics.Legislators.source_url()} ...")

    summary = VNI.Politics.Legislators.ingest_current!()

    Mix.shell().info(
      "Done. #{summary.ingested} profiles upserted, " <>
        "#{summary.skipped_non_voting} non-voting seats skipped."
    )

    case summary.missing_districts do
      [] -> :ok
      missing -> Mix.shell().error("No current district for: #{Enum.join(missing, ", ")}")
    end
  end
end
