defmodule Mix.Tasks.Vni.Score do
  @shortdoc "Compute compactness metrics, composite scores, and national ranks"

  @moduledoc """
  Runs the scoring engine over the current map set.

      mix vni.score                       # all current congressional maps
      mix vni.score --congress 118        # one historical congress's cohort
      mix vni.score --map-version 42      # raw metrics for one map version only

  A full run computes the four raw metrics per district, then normalizes
  and ranks within the cohort — the current map set, or one congress's
  map set; scores never mix across congresses (see VNI.Scores for the
  measurement rules).
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :info)

    {opts, _, _} = OptionParser.parse(args, strict: [map_version: :integer, congress: :integer])

    cond do
      congress = opts[:congress] ->
        Mix.shell().info("Scoring the #{congress}th Congress's map set within its own cohort...")
        VNI.Scores.score_congress!(congress, :congressional)
        Mix.shell().info("Done. Methodology version #{VNI.Scores.methodology_version()}.")

      id = opts[:map_version] ->
        Mix.shell().info("Computing raw metrics for map version #{id}...")
        VNI.Scores.compute_metrics!(id)

        Mix.shell().info(
          "Done. Run `mix vni.score` with no args to refresh composite + national ranks."
        )

      true ->
        Mix.shell().info("Scoring all current congressional map versions...")
        VNI.Scores.score_current!(:congressional)
        Mix.shell().info("Done. Methodology version #{VNI.Scores.methodology_version()}.")
    end
  end
end
