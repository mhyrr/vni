defmodule Mix.Tasks.Vni.Ingest.Results do
  @shortdoc "Ingest election results by district (margins + partisan lean inputs)"

  @moduledoc """
  Loads election results by district from public datasets (MIT Election
  Data + Science Lab; presidential-by-CD for lean) and updates last-margin
  and partisan-lean fields on district profiles.

      mix vni.ingest.results --cycle 2024

  Lean uses our own published formula (VNI.Politics.partisan_lean/2),
  never Cook PVI.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [cycle: :integer])
    cycle = opts[:cycle] || Mix.raise("--cycle is required, e.g. --cycle 2024")

    Mix.raise("Not implemented yet. Will ingest #{cycle} results by district.")
  end
end
