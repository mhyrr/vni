defmodule VNI.Atlas.ACSTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Atlas.ACS
  alias VNI.Politics

  setup do
    {:ok, tx} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, district} = Atlas.upsert_district(tx, %{state: "TX", number: 33})

    {:ok, wy} =
      Atlas.create_map_version(%{
        state: "WY",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, at_large} = Atlas.upsert_district(wy, %{state: "WY", number: 0})

    %{district: district, at_large: at_large}
  end

  # Raw API shape: header row, then values as strings, state as FIPS,
  # "00" for at-large, "98" for delegate seats.
  defp fixture_rows do
    [
      ["NAME", "B01003_001E", "B05003_008E", "B05003_019E", "state", "congressional district"],
      [
        "Congressional District 33 (119th Congress), Texas",
        "789013",
        "270000",
        "290000",
        "48",
        "33"
      ],
      [
        "Congressional District (at Large) (119th Congress), Wyoming",
        "581381",
        "220000",
        "225000",
        "56",
        "00"
      ],
      [
        "Delegate District (at Large) (119th Congress), District of Columbia",
        "670050",
        "260000",
        "280000",
        "11",
        "98"
      ],
      [
        "Congressional District 5 (119th Congress), Texas",
        "760000",
        "280000",
        "290000",
        "48",
        "5"
      ]
    ]
  end

  test "upserts population per district, recording vintage and citation", ctx do
    summary = ACS.ingest!(rows: fixture_rows(), vintage: 2024)

    assert summary.ingested == 2
    assert summary.skipped == 1
    assert summary.missing_districts == ["tx-5"]

    profile = Politics.get_profile(ctx.district.id)
    assert profile.population == 789_013
    assert profile.voting_age_population == 560_000
    assert profile.acs_vintage == 2024
    assert profile.population_source_url == ACS.source_url(2024)

    assert %{population: 581_381} = Politics.get_profile(ctx.at_large.id)
  end

  test "rerun refreshes in place and preserves incumbent fields", ctx do
    {:ok, _} =
      Politics.upsert_profile(ctx.district, %{incumbent_name: "Marc A. Veasey"})

    %{ingested: 2} = ACS.ingest!(rows: fixture_rows(), vintage: 2024)
    %{ingested: 2} = ACS.ingest!(rows: fixture_rows(), vintage: 2024)

    profile = Politics.get_profile(ctx.district.id)
    assert profile.population == 789_013
    assert profile.incumbent_name == "Marc A. Veasey"
  end
end
