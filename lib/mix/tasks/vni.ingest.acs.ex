defmodule Mix.Tasks.Vni.Ingest.Acs do
  @shortdoc "Ingest district population from the Census ACS 5-year API"

  @moduledoc """
  Upserts total and voting-age population per current district, with the
  ACS vintage and request URL recorded on every row. Rerunnable.

      mix vni.ingest.acs                  # default vintage
      mix vni.ingest.acs --vintage 2023

  Requires a free Census API key in CENSUS_API_KEY
  (https://api.census.gov/data/key_signup.html).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [vintage: :integer])
    vintage = opts[:vintage] || VNI.Atlas.ACS.default_vintage()

    Mix.shell().info("Ingesting ACS #{vintage} 5-year population by congressional district...")

    summary = VNI.Atlas.ACS.ingest!(vintage: vintage)

    Mix.shell().info(
      "Done. #{summary.ingested} districts updated, " <>
        "#{summary.skipped} non-map geographies skipped."
    )

    case summary.missing_districts do
      [] -> :ok
      missing -> Mix.shell().error("No current district for: #{Enum.join(missing, ", ")}")
    end
  end
end
