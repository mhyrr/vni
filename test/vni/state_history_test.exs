defmodule VNI.Politics.StateHistoryTest do
  use VNI.DataCase, async: true

  import ExUnit.CaptureLog

  alias VNI.Politics
  alias VNI.Politics.StateHistory

  @house_header "year,state,state_po,state_fips,state_cen,state_ic,office,district,stage," <>
                  "runoff,special,candidate,party,writein,mode,candidatevotes,totalvotes," <>
                  "unofficial,version,fusion_ticket"

  defp house_row(year, state, district, candidate, party, votes, opts \\ []) do
    runoff = Keyword.get(opts, :runoff, "FALSE")
    special = Keyword.get(opts, :special, "FALSE")

    "#{year},#{state},#{state},0,0,0,US HOUSE,#{district},GEN,#{runoff},#{special}," <>
      "#{candidate},#{party},FALSE,TOTAL,#{votes},1000,FALSE,20250910,FALSE"
  end

  defp house_csv do
    [
      @house_header,
      # ND at-large, 2024: Dem-NPL affiliate must count as a D seat.
      house_row(2024, "ND", 0, "NPL WINNER", "DEMOCRATIC-NPL", 600),
      house_row(2024, "ND", 0, "R LOSER", "REPUBLICAN", 400),
      # TX two districts, 2024: one per party.
      house_row(2024, "TX", 1, "R WINNER", "REPUBLICAN", 700),
      house_row(2024, "TX", 1, "D LOSER", "DEMOCRAT", 300),
      house_row(2024, "TX", 2, "D WINNER", "DEMOCRAT", 550),
      house_row(2024, "TX", 2, "R LOSER", "REPUBLICAN", 450),
      # TX-1 midterm 2022 decided by a runoff — first round must not count.
      house_row(2022, "TX", 1, "D FIRST ROUND", "DEMOCRAT", 900),
      house_row(2022, "TX", 1, "R WINNER", "REPUBLICAN", 501, runoff: "TRUE"),
      house_row(2022, "TX", 1, "D LOSER", "DEMOCRAT", 499, runoff: "TRUE"),
      # A special never counts toward the delegation.
      house_row(2022, "TX", 2, "SPECIAL WINNER", "DEMOCRAT", 999, special: "TRUE"),
      house_row(2022, "TX", 2, "D WINNER", "DEMOCRAT", 800),
      house_row(2022, "TX", 2, "R LOSER", "REPUBLICAN", 200),
      # VT independent: :other, never rebucketed into a major party.
      house_row(2024, "VT", 0, "I WINNER", "INDEPENDENT", 900),
      house_row(2024, "VT", 0, "R LOSER", "REPUBLICAN", 100),
      # District-years with no regular general still seat a member:
      # a court-ordered special general (TX 2006 pattern) ...
      special_general_row(2024, "GA", 1, "R WINNER", "REPUBLICAN", 600),
      special_general_row(2024, "GA", 1, "D LOSER", "DEMOCRAT", 400),
      # ... or a court-ordered open primary (TX 1996 pattern).
      special_primary_row(2024, "GA", 2, "D WINNER", "DEMOCRAT", 700),
      special_primary_row(2024, "GA", 2, "R LOSER", "REPUBLICAN", 300)
    ]
    |> Enum.join("\n")
  end

  defp special_general_row(year, state, district, candidate, party, votes) do
    house_row(year, state, district, candidate, party, votes, special: "TRUE")
  end

  defp special_primary_row(year, state, district, candidate, party, votes) do
    "#{year},#{state},#{state},0,0,0,US HOUSE,#{district},PRI,FALSE,TRUE," <>
      "#{candidate},#{party},FALSE,TOTAL,#{votes},1000,FALSE,20250910,FALSE"
  end

  @president_header "year,state,state_po,state_fips,state_cen,state_ic,office,candidate," <>
                      "party_detailed,writein,candidatevotes,totalvotes,version,notes,party_simplified"

  defp president_csv do
    rows =
      for {year, state, party, votes} <- [
            {2024, "TX", "REPUBLICAN", 560},
            {2024, "TX", "DEMOCRAT", 440},
            {2024, "TX", "OTHER", 55},
            {2024, "ND", "REPUBLICAN", 700},
            {2024, "ND", "DEMOCRAT", 300},
            {2024, "VT", "REPUBLICAN", 320},
            {2024, "VT", "DEMOCRAT", 680}
          ] do
        "#{year},#{state},#{state},0,0,0,US PRESIDENT,CANDIDATE,#{party},False,#{votes},1000,v,,#{party}"
      end

    Enum.join([@president_header | rows], "\n")
  end

  test "seats and pres shares per state-cycle" do
    log =
      capture_log(fn ->
        summary = StateHistory.ingest!(house_csv: house_csv(), president_csv: president_csv())
        assert summary.rows == 5
        assert summary.cycles == 2
        # Fixture cycles never sum to 435 — the invariant flags them all.
        assert map_size(summary.off_total_cycles) == 2
      end)

    assert log =~ "seat counted as :other"

    [tx22, tx24] = Politics.state_history("TX")

    assert %{cycle: 2022, seats_dem: 1, seats_rep: 1, seats_other: 0, pres_r_share: nil} = tx22
    assert tx24.cycle == 2024
    assert %{seats_dem: 1, seats_rep: 1} = tx24
    # Third parties are outside the two-party share: 560/(560+440).
    assert_in_delta tx24.pres_r_share, 56.0, 0.001
    assert tx24.pres_source_url == StateHistory.president_source_url()
    assert tx22.pres_source_url == nil
    assert tx24.seats_source_url == StateHistory.house_source_url()

    [nd24] = Politics.state_history("ND")
    assert %{seats_dem: 1, seats_rep: 0, seats_other: 0} = nd24

    [vt24] = Politics.state_history("VT")
    assert %{seats_dem: 0, seats_rep: 0, seats_other: 1} = vt24

    # Court-ordered contests with no regular general still seat members.
    [ga24] = Politics.state_history("GA")
    assert %{seats_dem: 1, seats_rep: 1, seats_other: 0} = ga24
  end

  test "rerun is idempotent and latest_state_cycles picks the newest row" do
    capture_log(fn ->
      StateHistory.ingest!(house_csv: house_csv(), president_csv: president_csv())
      StateHistory.ingest!(house_csv: house_csv(), president_csv: president_csv())
    end)

    assert length(Politics.state_history("TX")) == 2

    latest = Politics.latest_state_cycles()
    assert latest["TX"].cycle == 2024
    assert latest["ND"].cycle == 2024
  end
end
