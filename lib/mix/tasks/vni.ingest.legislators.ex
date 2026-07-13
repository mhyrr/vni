defmodule Mix.Tasks.Vni.Ingest.Legislators do
  @shortdoc "Ingest incumbents from unitedstates/congress-legislators"

  @moduledoc """
  Pulls the public-domain `unitedstates/congress-legislators` YAML and
  upserts district profiles (incumbent, party, first-elected year,
  bioguide id).

      mix vni.ingest.legislators
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    Mix.raise("""
    Not implemented yet. Will fetch legislators-current.yaml and upsert
    VNI.Politics.DistrictProfile rows keyed by district slug.
    """)
  end
end
