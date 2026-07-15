# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     VNI.Repo.insert!(%VNI.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

unless System.get_env("VNI_SKIP_DISTRICT_SEEDS") in ["1", "true"] do
  summary = VNI.Atlas.Census.seed_current!()

  IO.puts(
    "Seeded #{summary.districts} congressional districts " <>
      "from Census TIGER/Line #{summary.vintage}."
  )

  authorship = VNI.Atlas.MapAuthorship.seed_current!()

  IO.puts(
    "Stamped map authorship (Loyola, All About Redistricting) on " <>
      "#{authorship.updated} current map versions."
  )
end
