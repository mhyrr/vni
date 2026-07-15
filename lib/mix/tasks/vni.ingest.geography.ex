defmodule Mix.Tasks.Vni.Ingest.Geography do
  @shortdoc "Ingest district counties and places (Census relationship files)"

  @moduledoc """
  Upserts the plain-language location of every current district — counties
  covered and top places — from the Census CD119 relationship files, with
  the source recorded per row. Rerunnable; files cache locally.

      mix vni.ingest.geography

  Place ranking uses ACS place populations, so a free Census API key must
  be exported as CENSUS_API_KEY (https://api.census.gov/data/key_signup.html).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info(
      "Ingesting county/place relationships from #{VNI.Atlas.Geography.source_url()} ..."
    )

    summary = VNI.Atlas.Geography.ingest!()

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
