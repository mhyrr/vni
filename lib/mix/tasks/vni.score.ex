defmodule Mix.Tasks.Vni.Score do
  @shortdoc "Compute compactness metrics, composite scores, and national ranks"

  @moduledoc """
  Runs the scoring engine over the current map set.

      mix vni.score                       # all current congressional maps
      mix vni.score --map-version 42      # raw metrics for one map version only

  A full run computes the four raw metrics per district, then normalizes
  and ranks nationally (see VNI.Scores for the measurement rules).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, strict: [map_version: :integer])

    case opts[:map_version] do
      nil ->
        Mix.shell().info("Scoring all current congressional map versions...")
        VNI.Scores.score_current!(:congressional)
        Mix.shell().info("Done. Methodology version #{VNI.Scores.methodology_version()}.")

      id ->
        Mix.shell().info("Computing raw metrics for map version #{id}...")
        VNI.Scores.compute_metrics!(id)

        Mix.shell().info(
          "Done. Run `mix vni.score` with no args to refresh composite + national ranks."
        )
    end
  end
end
