defmodule VNI.Politics.StateHistory do
  @moduledoc """
  Statewide seats–votes history, 1976–2024: one row per state per cycle
  with the House delegation split and, in presidential years, the R share
  of the state's two-party presidential vote.

  ## Seats (MEDSL House)

  Winners come from the same race-deciding rules as the margin ingest
  (`VNI.Politics.Results.decide_race/2`): fusion lines aggregate by
  candidate, a runoff replaces its first round — the seat counts and the
  published margins must agree on who won. Each district-cycle counts
  its *seating contest*: the regular general when one exists, else the
  court-ordered November contest MEDSL records instead (see
  `seating_contest/2`); vacancy specials held alongside a general never
  displace it. MEDSL publishes ranked-choice races at tallies where the
  top vote-getter is the actual winner (verified on ME-02 2018, the
  race RCV flipped).

  Winner parties map to `:dem`/`:rep`/`:other` with the historical
  affiliates included (ND's Democratic-NPL, MN's DFL and 1975–1995
  Independent-Republican era). Anything else — Vermont's independents,
  one-off ballot labels — counts as `:other` and is logged, never
  silently rebucketed into a major party.

  ## Votes (MEDSL President)

  `pres_r_share` = 100 × R / (D + R) over the state's certified
  presidential returns, coded by MEDSL `party_simplified`. Midterm
  cycles carry seats only; the share stays nil rather than interpolated,
  because interpolation is modeling and this series publishes
  measurements.
  """

  require Logger

  alias NimbleCSV.RFC4180, as: CSV
  alias VNI.Politics.{Results, StateCycle}
  alias VNI.Repo

  @house_source_url "https://doi.org/10.7910/DVN/IG0UN2"
  @president_source_url "https://doi.org/10.7910/DVN/42MVDX"

  @house_seat_total 435

  def house_source_url, do: @house_source_url
  def president_source_url, do: @president_source_url

  @doc """
  Upsert the full seats–votes series. Idempotent — rows are keyed on
  (state, cycle) and each rerun replaces them wholesale (this ingest is
  the row's only writer). Accepts `:house_csv` and `:president_csv`
  binaries for tests. Returns
  `%{rows: n, cycles: n, off_total_cycles: %{cycle => seat_total}}` —
  every cycle since 1976 should sum to #{@house_seat_total} seats.
  """
  def ingest!(opts \\ []) do
    house =
      Keyword.get_lazy(opts, :house_csv, fn ->
        Results.read_cache!(Results.house_returns_path())
      end)

    president =
      Keyword.get_lazy(opts, :president_csv, fn ->
        Results.read_cache!(Results.president_returns_path())
      end)

    seats = seat_tallies(house)
    pres = state_pres_shares(president)
    now = DateTime.utc_now(:second)

    rows =
      for {{state, cycle}, tally} <- seats do
        pres_share = Map.get(pres, {state, cycle})

        %{
          state: state,
          cycle: cycle,
          seats_dem: Map.get(tally, :dem, 0),
          seats_rep: Map.get(tally, :rep, 0),
          seats_other: Map.get(tally, :other, 0),
          pres_r_share: pres_share,
          seats_source_url: @house_source_url,
          pres_source_url: if(pres_share, do: @president_source_url),
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(StateCycle, rows,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:state, :cycle]
    )

    totals =
      rows
      |> Enum.group_by(& &1.cycle)
      |> Map.new(fn {cycle, cycle_rows} ->
        {cycle, Enum.sum(Enum.map(cycle_rows, &(&1.seats_dem + &1.seats_rep + &1.seats_other)))}
      end)

    off_total = Map.filter(totals, fn {_cycle, total} -> total != @house_seat_total end)

    for {cycle, total} <- off_total do
      Logger.warning("state history: #{cycle} sums to #{total} seats, expected 435")
    end

    %{rows: length(rows), cycles: map_size(totals), off_total_cycles: off_total}
  end

  # {state, cycle} => %{dem: n, rep: n, other: n}, from the seating
  # contest in every district-cycle.
  defp seat_tallies(csv) do
    [header | rows] = CSV.parse_string(csv, skip_headers: false)
    col = header |> Enum.with_index() |> Map.new()

    rows
    |> Enum.reject(&(Results.at(&1, col, "state_po") in Results.non_voting()))
    |> Enum.group_by(fn row ->
      {Results.at(row, col, "state_po"), Results.at(row, col, "district"),
       Results.at(row, col, "year")}
    end)
    |> Enum.flat_map(fn {{state, _district, year}, group} ->
      case group |> seating_contest(col) |> Results.decide_race(col) do
        nil -> []
        race -> [{{state, String.to_integer(year)}, seat_party(race.party)}]
      end
    end)
    |> Enum.group_by(fn {key, _party} -> key end, fn {_key, party} -> party end)
    |> Map.new(fn {key, parties} -> {key, Enum.frequencies(parties)} end)
  end

  # The contest that seated the member. Every seat is up in every even
  # year, so a district-year with no regular general on record was seated
  # by whatever November contest MEDSL does record: court-ordered
  # specials (TX 2006, LULAC v. Perry) or court-ordered open primaries
  # (TX 1996, Bush v. Vera — outright majority elected; otherwise the
  # December runoff appears as a regular GEN row and takes tier-1
  # precedence). A vacancy special held concurrently with a general
  # never wins: tier 1 always beats it. These 3 tiers cover every
  # district-year in the file except the 14 known court-ordered cases.
  defp seating_contest(group, col) do
    tiers = [
      fn row ->
        Results.at(row, col, "stage") == "GEN" and Results.at(row, col, "special") != "TRUE"
      end,
      fn row -> Results.at(row, col, "stage") == "GEN" end,
      fn row ->
        Results.at(row, col, "stage") == "PRI" and Results.at(row, col, "special") == "TRUE"
      end
    ]

    Enum.find_value(tiers, [], fn tier ->
      case Enum.filter(group, tier) do
        [] -> nil
        rows -> rows
      end
    end)
  end

  # Major parties and their published state affiliates. Everything else
  # is :other — logged, never silently rebucketed.
  defp seat_party("DEMOCRAT"), do: :dem
  defp seat_party("DEMOCRATIC"), do: :dem
  defp seat_party("DEMOCRATIC-FARMER-LABOR"), do: :dem
  defp seat_party("DEMOCRATIC-FARM-LABOR"), do: :dem
  defp seat_party("DEMOCRATIC-NPL"), do: :dem
  defp seat_party("DEMOCRATIC-NONPARTISAN LEAGUE"), do: :dem
  defp seat_party("REPUBLICAN"), do: :rep
  defp seat_party("INDEPENDENT-REPUBLICAN"), do: :rep

  defp seat_party(other) do
    Logger.warning("state history: seat counted as :other for party #{inspect(other)}")
    :other
  end

  # {state, cycle} => R share of the two-party presidential vote.
  defp state_pres_shares(csv) do
    [header | rows] = CSV.parse_string(csv, skip_headers: false)
    col = header |> Enum.with_index() |> Map.new()

    rows
    |> Enum.filter(&(Results.at(&1, col, "state_po") not in Results.non_voting()))
    |> Enum.group_by(fn row ->
      {Results.at(row, col, "state_po"), Results.at(row, col, "year")}
    end)
    |> Enum.flat_map(fn {{state, year}, group} ->
      by_party =
        Enum.group_by(
          group,
          &Results.at(&1, col, "party_simplified"),
          &(&1 |> Results.at(col, "candidatevotes") |> String.to_integer())
        )

      dem = by_party |> Map.get("DEMOCRAT", []) |> Enum.sum()
      rep = by_party |> Map.get("REPUBLICAN", []) |> Enum.sum()

      if dem + rep > 0 do
        [{{state, String.to_integer(year)}, 100.0 * rep / (dem + rep)}]
      else
        []
      end
    end)
    |> Map.new()
  end
end
