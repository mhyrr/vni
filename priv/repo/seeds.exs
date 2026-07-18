# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Idempotent by design — every step upserts, so reruns refresh in place.
# `VNI_SKIP_DISTRICT_SEEDS=1` skips the whole block (used by CI/tests).

unless System.get_env("VNI_SKIP_DISTRICT_SEEDS") in ["1", "true"] do
  for congress <- VNI.Atlas.Census.supported_congresses() do
    summary = VNI.Atlas.Census.seed_congress!(congress)

    IO.puts(
      "Seeded #{summary.districts} districts for the #{congress}th Congress " <>
        "from Census TIGER/Line #{summary.vintage}."
    )
  end

  authorship = VNI.Atlas.MapAuthorship.seed_current!()

  IO.puts(
    "Stamped map authorship (Loyola, All About Redistricting) on " <>
      "#{authorship.updated} current map versions."
  )

  current = VNI.Atlas.Census.current_congress()

  for congress <- VNI.Atlas.Census.supported_congresses(), congress != current do
    :ok = VNI.Scores.score_congress!(congress)
  end

  :ok = VNI.Scores.score_current!()

  IO.puts(
    "Scored every congress within its own cohort (methodology #{VNI.Scores.methodology_version()})."
  )
end
