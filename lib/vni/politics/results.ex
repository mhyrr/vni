defmodule VNI.Politics.Results do
  @moduledoc """
  Election-results ingestion: House winning margins and presidential-by-CD
  partisan lean, each cited per row on the district profile.

  ## Margins (MEDSL)

  Source: MIT Election Data + Science Lab, "U.S. House 1976–2024" (CC0),
  https://doi.org/10.7910/DVN/IG0UN2. The Dataverse download sits behind a
  guestbook, so the file is a manually fetched local cache (see
  `house_returns_path/0`) — same spirit as the TIGER archive cache.
  Despite the dataset's `.tab` display name, the original file format is
  comma-separated.

  Measurement rules, decided 2026-07-14 (TK-003):

    * `last_margin_pct` is the winning margin of the district's most recent
      House **general** on record: 100 × (top candidate − runner-up) / all
      votes cast for ranked candidates in that race. 2024 is preferred;
      when a district's latest general on record is older, that cycle is
      used and recorded in `last_margin_cycle` — never silence.
    * Fusion tickets (NY, CT) are aggregated by candidate before ranking;
      a candidate's party is the party of their highest-vote ballot line.
    * Pseudo-candidates (write-in scatter, blanks, under/overvotes, RCV
      exhausted ballots) never rank and never count in the denominator.
    * Unopposed races keep their arithmetic: with no second candidate the
      margin is 100.0. States that skip the tally for unopposed seats
      (FL, OK) code the winner as 1 vote of 1, which lands on the same
      100.0 — unopposed is the strongest entrenchment signal, not a gap.
    * All-party and top-two generals (LA, WA, CA) are candidate contests:
      the margin is top-two regardless of party, so a same-party general
      counts as contested.
    * Special elections are excluded — the regular general seats the
      Congress the current map addresses.
    * If a general went to a runoff, the runoff is the deciding contest
      and replaces the first round.

  ## Partisan lean (The Downballot + MEDSL national)

  Lean is our own published formula (`VNI.Politics.partisan_lean/2`),
  never Cook PVI. Inputs are two-party presidential vote shares:

      lean = 0.75 × (district R share − national R share, 2024)
           + 0.25 × (district R share − national R share, 2020)

  in percentage points; positive = more Republican than the nation.

  District shares come from The Downballot's (Daily Kos Elections)
  calculations of 2024 and 2020 presidential results on the district lines
  used in 2024 — the lines of the 119th Congress, matching our current
  map set. Reuse is permitted with citation and link (their stated terms);
  the sheet is cited on every row. Their published shares are mostly
  whole percentages (occasionally decimal), so lean carries roughly
  ±0.5pt input precision.
  National shares are computed from MEDSL "U.S. President 1976–2024"
  (CC0, https://doi.org/10.7910/DVN/42MVDX), also a guestbook-gated
  local cache.
  """

  require Logger

  alias NimbleCSV.RFC4180, as: CSV
  alias VNI.Atlas
  alias VNI.Atlas.District
  alias VNI.Politics

  @house_cycles ["2024", "2022"]
  @lean_cycles [2024, 2020]

  @house_source_url "https://doi.org/10.7910/DVN/IG0UN2"
  @president_source_url "https://doi.org/10.7910/DVN/42MVDX"
  @lean_source_url "https://docs.google.com/spreadsheets/d/1ng1i_Dm_RMDnEvauH44pgE6JCUsapcuu8F2pCfeLWFo"

  # Non-voting delegate seats have no district in the 435-seat map set.
  @non_voting ~w(AS DC GU MP PR VI)

  # Rows that are bookkeeping, not candidacies.
  @pseudo_candidates ["", "NA", "WRITEIN", "BLANK", "UNDERVOTES", "OVERVOTES"] ++
                       ["EXHAUSTED BALLOT", "EXHAUSTED BALLOTS", "NOT ASSIGNED"]

  def house_source_url, do: @house_source_url
  def lean_source_url, do: @lean_source_url
  def house_returns_path, do: Path.expand("priv/repo/data/medsl/1976-2024-house.csv")
  def president_returns_path, do: Path.expand("priv/repo/data/medsl/1976-2024-president.csv")

  def pres_by_cd_path,
    do: Path.expand("priv/repo/data/downballot/pres_by_cd_2024_lines.csv")

  @doc """
  Upsert the most recent House general margin per current district.

  Accepts `:house_csv` (raw CSV binary) for tests; otherwise reads the
  local MEDSL cache. Returns
  `%{ingested: n, fallback_cycles: %{cycle => n}, missing_districts: [slug]}`.
  """
  def ingest_margins!(opts \\ []) do
    csv = Keyword.get_lazy(opts, :house_csv, fn -> read_cache!(house_returns_path()) end)
    [header | rows] = CSV.parse_string(csv, skip_headers: false)
    col = header |> Enum.with_index() |> Map.new()

    results =
      rows
      |> Enum.filter(&countable_general?(&1, col))
      |> Enum.group_by(fn row ->
        {at(row, col, "state_po"), at(row, col, "district"), at(row, col, "year")}
      end)
      |> Enum.flat_map(fn {{state, district, year}, group} ->
        case decide_race(group, col) do
          nil -> []
          race -> [{{state, district}, Map.put(race, :cycle, String.to_integer(year))}]
        end
      end)
      |> Enum.group_by(fn {key, _race} -> key end, fn {_key, race} -> race end)
      |> Enum.map(fn {{state, district}, races} ->
        race = Enum.max_by(races, & &1.cycle)
        upsert_margin(state, district, race)
      end)

    %{
      ingested: Enum.count(results, &match?({:ok, _cycle}, &1)),
      fallback_cycles:
        for({:ok, cycle} <- results, cycle != 2024, do: cycle) |> Enum.frequencies(),
      missing_districts: for({:missing, slug} <- results, do: slug)
    }
  end

  defp countable_general?(row, col) do
    at(row, col, "year") in @house_cycles and
      at(row, col, "stage") == "GEN" and
      at(row, col, "special") != "TRUE" and
      at(row, col, "state_po") not in @non_voting
  end

  # The deciding contest for one district-cycle: runoff rows when a runoff
  # happened, otherwise the general itself. Returns nil when no rankable
  # candidate remains (never the case in practice).
  defp decide_race(group, col) do
    group =
      case Enum.filter(group, &(at(&1, col, "runoff") == "TRUE")) do
        [] -> group
        runoff_rows -> runoff_rows
      end

    candidates =
      group
      |> Enum.reject(&(at(&1, col, "candidate") in @pseudo_candidates))
      |> Enum.group_by(&at(&1, col, "candidate"))
      |> Enum.map(fn {_candidate, rows} ->
        votes = rows |> Enum.map(&int_at(&1, col, "candidatevotes")) |> Enum.sum()
        top_line = Enum.max_by(rows, &int_at(&1, col, "candidatevotes"))
        %{votes: votes, party: at(top_line, col, "party")}
      end)
      |> Enum.sort_by(& &1.votes, :desc)

    case candidates do
      [] ->
        nil

      [winner | rest] ->
        runner_up_votes =
          case rest do
            [second | _] -> second.votes
            [] -> 0
          end

        denominator = winner.votes + Enum.sum(Enum.map(rest, & &1.votes))

        %{
          margin: Float.round(100.0 * (winner.votes - runner_up_votes) / denominator, 2),
          party: winner_party(winner.party)
        }
    end
  end

  defp upsert_margin(state, district_code, race) do
    slug = District.build_slug(state, String.to_integer(district_code))

    case Atlas.get_district_by_slug(slug) do
      nil ->
        Logger.warning("no current district for House result #{slug}")
        {:missing, slug}

      district ->
        {:ok, _profile} =
          Politics.upsert_profile(district, %{
            last_margin_pct: race.margin,
            last_margin_cycle: race.cycle,
            last_margin_party: race.party,
            margin_source_url: @house_source_url
          })

        {:ok, race.cycle}
    end
  end

  # Party exactly as the record states it, mapped to the storage enum. The
  # DFL is Minnesota's Democratic affiliate (a published fact, not a
  # judgment); anything else non-major stores as :ind and is logged.
  defp winner_party("DEMOCRAT"), do: :dem
  defp winner_party("DEMOCRATIC-FARMER-LABOR"), do: :dem
  defp winner_party("REPUBLICAN"), do: :rep
  defp winner_party("INDEPENDENT"), do: :ind

  defp winner_party(other) do
    Logger.warning("non-major winning party stored as :ind: #{inspect(other)}")
    :ind
  end

  @doc """
  Upsert partisan lean per current district from two-party presidential
  shares (district: The Downballot on 2024 lines; national: MEDSL).

  Accepts `:pres_by_cd_csv` and `:president_csv` binaries for tests.
  Returns `%{ingested: n, missing_districts: [slug]}`.
  """
  def ingest_lean!(opts \\ []) do
    pres_by_cd =
      Keyword.get_lazy(opts, :pres_by_cd_csv, fn ->
        fetch_cached!(pres_by_cd_path(), "#{@lean_source_url}/export?format=csv")
      end)

    president =
      Keyword.get_lazy(opts, :president_csv, fn -> read_cache!(president_returns_path()) end)

    national = national_two_party_shares(president)

    results =
      pres_by_cd
      |> district_two_party_shares()
      |> Enum.map(fn {slug, district_shares} ->
        lean =
          @lean_cycles
          |> Enum.map(&Map.fetch!(district_shares, &1))
          |> Politics.partisan_lean(Enum.map(@lean_cycles, &Map.fetch!(national, &1)))

        case Atlas.get_district_by_slug(slug) do
          nil ->
            Logger.warning("no current district for presidential result #{slug}")
            {:missing, slug}

          district ->
            {:ok, _profile} =
              Politics.upsert_profile(district, %{
                partisan_lean: Float.round(lean, 1),
                lean_source_url: @lean_source_url
              })

            :ok
        end
      end)

    %{
      ingested: Enum.count(results, &(&1 == :ok)),
      missing_districts: for({:missing, slug} <- results, do: slug)
    }
  end

  # The Downballot sheet: preamble rows, then a header block, then one row
  # per district ("AK-AL,<incumbent>,<party>,Harris,Trump,Margin,Biden,
  # Trump,Margin"). Only the vote-share columns are read — incumbent
  # context is ingested from the legislators dataset, and challenger info
  # never enters the system from anywhere.
  defp district_two_party_shares(csv) do
    csv
    |> CSV.parse_string(skip_headers: false)
    |> Enum.filter(&match?([<<_, _, ?-, _::binary>> | _], &1))
    |> Enum.map(fn [district, _incumbent, _party, d24, r24, _m24, d20, r20, _m20 | _rest] ->
      {state, number} = parse_dk_district(district)

      {District.build_slug(state, number),
       %{
         2024 => two_party_share(r24, d24),
         2020 => two_party_share(r20, d20)
       }}
    end)
  end

  defp parse_dk_district(label) do
    [state, district] = String.split(label, "-", parts: 2)

    case district do
      "AL" -> {state, 0}
      number -> {state, String.to_integer(number)}
    end
  end

  # Published shares are usually whole percentages, occasionally decimal.
  defp two_party_share(r_share, d_share) do
    r = parse_number!(r_share)
    d = parse_number!(d_share)
    100.0 * r / (r + d)
  end

  defp parse_number!(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> raise ArgumentError, "unparseable share in pres-by-CD data: #{inspect(value)}"
    end
  end

  # National R share of the two-party vote per cycle, summed over the
  # state-level MEDSL returns using their party_simplified coding.
  defp national_two_party_shares(csv) do
    [header | rows] = CSV.parse_string(csv, skip_headers: false)
    col = header |> Enum.with_index() |> Map.new()
    cycles = Enum.map(@lean_cycles, &Integer.to_string/1)

    rows
    |> Enum.filter(&(at(&1, col, "year") in cycles))
    |> Enum.group_by(&at(&1, col, "year"))
    |> Map.new(fn {year, year_rows} ->
      by_party =
        Enum.group_by(
          year_rows,
          &at(&1, col, "party_simplified"),
          &int_at(&1, col, "candidatevotes")
        )

      dem = Enum.sum(Map.fetch!(by_party, "DEMOCRAT"))
      rep = Enum.sum(Map.fetch!(by_party, "REPUBLICAN"))
      {String.to_integer(year), 100.0 * rep / (dem + rep)}
    end)
  end

  defp at(row, col, name), do: Enum.at(row, Map.fetch!(col, name))
  defp int_at(row, col, name), do: row |> at(col, name) |> String.to_integer()

  defp read_cache!(path) do
    case File.read(path) do
      {:ok, csv} ->
        csv

      {:error, reason} ->
        raise """
        missing local dataset cache #{path} (#{reason}).

        The MEDSL Dataverse gates downloads behind a guestbook, so this file
        is fetched manually once: open the dataset in a browser, complete the
        guestbook, download the original-format file, and place it at the
        path above.

          House:     #{@house_source_url}
          President: #{@president_source_url}
        """
    end
  end

  # The Downballot sheet has no download gate — cache on first use.
  defp fetch_cached!(path, url) do
    case File.read(path) do
      {:ok, csv} ->
        csv

      {:error, _reason} ->
        response = Req.get!(url, receive_timeout: 120_000, decode_body: false)

        if response.status != 200 do
          raise "failed to download #{url} (HTTP #{response.status})"
        end

        File.mkdir_p!(Path.dirname(path))
        File.write!(path, response.body)
        response.body
    end
  end
end
