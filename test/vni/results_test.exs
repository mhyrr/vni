defmodule VNI.Politics.ResultsTest do
  use VNI.DataCase, async: true

  alias VNI.{Atlas, Politics}
  alias VNI.Politics.Results

  setup do
    districts =
      for {state, number} <- [{"TX", 33}, {"WY", 0}, {"LA", 3}, {"GA", 2}], into: %{} do
        {:ok, mv} =
          Atlas.create_map_version(%{
            state: state,
            level: :congressional,
            congress: 119,
            effective_from: ~D[2025-01-03]
          })

        {:ok, district} = Atlas.upsert_district(mv, %{state: state, number: number})
        {district.slug, district}
      end

    %{districts: districts}
  end

  @house_header "year,state,state_po,state_fips,state_cen,state_ic,office,district,stage," <>
                  "runoff,special,candidate,party,writein,mode,candidatevotes,totalvotes," <>
                  "unofficial,version,fusion_ticket"

  defp house_row(year, state, district, candidate, party, votes, total, opts \\ []) do
    runoff = Keyword.get(opts, :runoff, "FALSE")
    special = Keyword.get(opts, :special, "FALSE")
    fusion = Keyword.get(opts, :fusion, "FALSE")

    "#{year},#{state},#{state},0,0,0,US HOUSE,#{district},GEN,#{runoff},#{special}," <>
      "#{candidate},#{party},FALSE,TOTAL,#{votes},#{total},FALSE,20250910,#{fusion}"
  end

  defp house_csv do
    [
      @house_header,
      # TX-33 2024: fusion candidate aggregates across ballot lines before
      # ranking; the write-in scatter row never ranks.
      house_row(2024, "TX", 33, "MARC VEASEY", "DEMOCRAT", 60_000, 100_500, fusion: "TRUE"),
      house_row(2024, "TX", 33, "MARC VEASEY", "WORKING FAMILIES", 5_000, 100_500,
        fusion: "TRUE"
      ),
      house_row(2024, "TX", 33, "PAT CHALLENGER", "REPUBLICAN", 35_000, 100_500),
      house_row(2024, "TX", 33, "WRITEIN", "NA", 500, 100_500),
      # A special that must not displace the regular general.
      house_row(2024, "TX", 33, "SOMEONE ELSE", "REPUBLICAN", 99, 100, special: "TRUE"),
      # An older TX-33 general that loses to the 2024 one.
      house_row(2022, "TX", 33, "MARC VEASEY", "DEMOCRAT", 99, 100),
      house_row(2022, "TX", 33, "OLD RIVAL", "REPUBLICAN", 1, 100),
      # WY at-large 2024: unopposed with no tally (FL/OK-style 1-of--1 coding).
      house_row(2024, "WY", 0, "HARRIET HAGEMAN", "REPUBLICAN", 1, -1),
      # LA-3 has no 2024 row on record: falls back to the 2022 all-party
      # general, a same-party top-two that still counts as contested.
      house_row(2022, "LA", 3, "CLAY HIGGINS", "REPUBLICAN", 140_000, 200_000),
      house_row(2022, "LA", 3, "HOLDEN HOGGATT", "REPUBLICAN", 60_000, 200_000),
      # GA-2 2022 went to a runoff: the runoff is the deciding contest.
      house_row(2022, "GA", 2, "CANDIDATE A", "DEMOCRAT", 45_000, 100_000),
      house_row(2022, "GA", 2, "CANDIDATE B", "REPUBLICAN", 40_000, 100_000),
      house_row(2022, "GA", 2, "CANDIDATE C", "LIBERTARIAN", 15_000, 100_000),
      house_row(2022, "GA", 2, "CANDIDATE A", "DEMOCRAT", 51_000, 100_000, runoff: "TRUE"),
      house_row(2022, "GA", 2, "CANDIDATE B", "REPUBLICAN", 49_000, 100_000, runoff: "TRUE"),
      # Non-voting delegate seat: skipped, not "missing".
      house_row(2024, "DC", 0, "DELEGATE", "DEMOCRAT", 100, 100),
      # No tx-5 in the test map set: reported as missing.
      house_row(2024, "TX", 5, "SOMEBODY", "REPUBLICAN", 60, 100),
      house_row(2024, "TX", 5, "OTHERBODY", "DEMOCRAT", 40, 100),
      # Outside the ingested cycles entirely.
      house_row(2020, "TX", 33, "MARC VEASEY", "DEMOCRAT", 100, 100)
    ]
    |> Enum.join("\n")
  end

  test "margins: fusion, unopposed, fallback cycle, runoffs, and skips", ctx do
    summary = Results.ingest_margins!(house_csv: house_csv())

    assert summary.ingested == 4
    assert summary.fallback_cycles == %{2022 => 2}
    assert summary.missing_districts == ["tx-5"]

    tx33 = Politics.get_profile(ctx.districts["tx-33"].id)
    # (65_000 - 35_000) / 100_000 ranked votes — fusion lines aggregated,
    # write-in scatter excluded from the denominator.
    assert tx33.last_margin_pct == 30.0
    assert tx33.last_margin_cycle == 2024
    assert tx33.last_margin_party == :dem
    assert tx33.margin_source_url == Results.house_source_url()

    # Unopposed, no tally recorded: margin is 100 by rule, not a gap.
    wy0 = Politics.get_profile(ctx.districts["wy-0"].id)
    assert wy0.last_margin_pct == 100.0
    assert wy0.last_margin_party == :rep

    # Latest general on record, cycle noted on the row.
    la3 = Politics.get_profile(ctx.districts["la-3"].id)
    assert la3.last_margin_pct == 40.0
    assert la3.last_margin_cycle == 2022
    assert la3.last_margin_party == :rep

    # The runoff, not the first round, decides GA-2.
    ga2 = Politics.get_profile(ctx.districts["ga-2"].id)
    assert ga2.last_margin_pct == 2.0
    assert ga2.last_margin_party == :dem

    # Rerun is idempotent.
    assert %{ingested: 4} = Results.ingest_margins!(house_csv: house_csv())
    assert Politics.get_profile(ctx.districts["tx-33"].id).id == tx33.id
  end

  @president_header "year,state,state_po,state_fips,state_cen,state_ic,office,candidate," <>
                      "party_detailed,writein,candidatevotes,totalvotes,version,notes,party_simplified"

  defp president_csv do
    rows =
      for {year, party, votes} <- [
            {2024, "DEMOCRAT", 300},
            {2024, "DEMOCRAT", 180},
            {2024, "REPUBLICAN", 500},
            {2024, "OTHER", 20},
            {2020, "DEMOCRAT", 510},
            {2020, "REPUBLICAN", 470},
            {2020, "OTHER", 20}
          ] do
        "#{year},SOMEWHERE,SW,0,0,0,US PRESIDENT,CANDIDATE,#{party},False,#{votes},1000,v,,#{party}"
      end

    Enum.join([@president_header | rows], "\n")
  end

  defp pres_by_cd_csv do
    """
    Calculated by The Downballot,,,Subscribe to our newsletter,,,,,
    District,Incumbent,Party,2024,,,2020,,
    ,,,Harris,Trump,Margin,Biden,Trump,Margin
    TX-33,Ignored Incumbent,(D),70,30,40,72,28,44
    WY-AL,Ignored Incumbent,(R),26,72,-46,27,70,-44
    TX-05,Ignored Incumbent,(R),40,60,-20,40,60,-20
    """
  end

  test "lean: two-party shares vs the nation, 3:1 weighted", ctx do
    summary =
      Results.ingest_lean!(pres_by_cd_csv: pres_by_cd_csv(), president_csv: president_csv())

    assert summary.ingested == 2
    assert summary.missing_districts == ["tx-5"]

    # National R two-party share: 2024 = 500/980, 2020 = 470/980.
    national_2024 = 100.0 * 500 / 980
    national_2020 = 100.0 * 470 / 980

    tx33 = Politics.get_profile(ctx.districts["tx-33"].id)

    expected_tx33 =
      0.75 * (100.0 * 30 / 100 - national_2024) + 0.25 * (100.0 * 28 / 100 - national_2020)

    assert_in_delta tx33.partisan_lean, expected_tx33, 0.06
    assert tx33.lean_source_url == Results.lean_source_url()
    # Deep-blue district: strongly negative (D+), Republican-lean positive.
    assert tx33.partisan_lean < -15

    wy0 = Politics.get_profile(ctx.districts["wy-0"].id)

    expected_wy0 =
      0.75 * (100.0 * 72 / 98 - national_2024) + 0.25 * (100.0 * 70 / 97 - national_2020)

    assert_in_delta wy0.partisan_lean, expected_wy0, 0.06
    assert wy0.partisan_lean > 15
  end

  test "margins and lean merge on the shared profile row", ctx do
    Results.ingest_margins!(house_csv: house_csv())
    Results.ingest_lean!(pres_by_cd_csv: pres_by_cd_csv(), president_csv: president_csv())

    profile = Politics.get_profile(ctx.districts["tx-33"].id)
    assert profile.last_margin_pct == 30.0
    assert profile.partisan_lean < 0
  end
end
