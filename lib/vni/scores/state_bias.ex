defmodule VNI.Scores.StateBias do
  @moduledoc """
  Statewide map-bias measures over the current map set. Published like
  the compactness methodology: open formulas over public data, never a
  licensed metric, never a synthesized state score.

  ## Mean–median gap

      mean_median = median(district R share) − mean(district R share)

  over each state's district two-party presidential shares (2024, the
  raw inputs behind partisan lean). Sign matches lean: positive means
  the median district is more Republican than the state average — the
  lines favor R at the tipping point; negative favors D.

  The gap is only published for states with at least 5 districts
  (`mean_median_seat_floor/0`). The floor has a mathematical
  receipt, not an editorial one: with 2 districts the median *is* the
  mean, so the statistic is identically zero — blind — and it stays
  near-degenerate at 3–4. The literature's stricter floor of 8 would
  drop Alabama (7 seats); we keep small-n states in and let the
  methodology page own the noise caveat. States with any district
  missing its ingested share publish nothing rather than a partial
  statistic.

  ## What is deliberately absent

  The efficiency gap waits for a published uncontested-race imputation
  rule; seats–votes *asymmetry* (uniform-swing counterfactuals) is
  modeling, not measuring, and is never published. The seats–votes fact
  pair itself lives in `VNI.Politics.StateCycle` — two facts side by
  side, not a formula.

  Attribution grammar for every consumer of these numbers: the fact
  pair shows the gap, the mean–median gap attributes it, and neither
  renders without map authorship beside it.
  """

  alias VNI.Repo

  @mean_median_seat_floor 5

  def mean_median_seat_floor, do: @mean_median_seat_floor

  @doc """
  One row per state over the current map set at a level: delegation
  size, at-large flag, mean–median gap (floored), compactness
  aggregates, the state's least compact district, and map authorship.
  Ordered by state code; every state with a current map appears.
  """
  def state_rows(level \\ :congressional) do
    %{rows: rows, columns: columns} =
      Repo.query!(
        """
        WITH cur AS (
          SELECT d.state, d.number, d.slug,
                 p.pres_share_2024,
                 s.composite, s.national_rank,
                 mv.authority, mv.controlling_party, mv.authorship_source_url
          FROM districts d
          JOIN map_versions mv ON mv.id = d.map_version_id
          LEFT JOIN district_profiles p ON p.district_id = d.id
          LEFT JOIN district_scores s ON s.district_id = d.id
          WHERE mv.level = $1 AND mv.effective_until IS NULL
        ),
        stats AS (
          SELECT state,
            count(*) AS seats,
            bool_or(number = 0) AS at_large,
            -- Median minus mean: only over a complete set of ingested
            -- shares, only at or above the seat floor. A partial set
            -- publishes nothing rather than a partial statistic.
            CASE
              WHEN count(*) >= $2 AND count(pres_share_2024) = count(*) THEN
                percentile_cont(0.5) WITHIN GROUP (ORDER BY pres_share_2024)
                  - avg(pres_share_2024)
            END AS mean_median,
            avg(composite) AS mean_composite,
            percentile_cont(0.5) WITHIN GROUP (ORDER BY composite) AS median_composite,
            min(authority) AS authority,
            min(controlling_party) AS controlling_party,
            min(authorship_source_url) AS authorship_source_url
          FROM cur
          GROUP BY state
        ),
        worst AS (
          SELECT DISTINCT ON (state) state, slug AS worst_district_slug,
                 national_rank AS worst_district_rank
          FROM cur
          WHERE national_rank IS NOT NULL
          ORDER BY state, national_rank DESC
        )
        SELECT s.state, s.seats, s.at_large, s.mean_median,
               s.mean_composite, s.median_composite,
               s.authority, s.controlling_party, s.authorship_source_url,
               w.worst_district_slug, w.worst_district_rank
        FROM stats s
        LEFT JOIN worst w ON w.state = s.state
        ORDER BY s.state
        """,
        [Atom.to_string(level), @mean_median_seat_floor],
        timeout: :infinity
      )

    keys = Enum.map(columns, &String.to_atom/1)

    Enum.map(rows, fn row ->
      keys
      |> Enum.zip(row)
      |> Map.new()
      |> Map.update!(:authority, &atomize/1)
      |> Map.update!(:controlling_party, &atomize/1)
    end)
  end

  @doc "The `state_rows/1` row for one state, or nil."
  def state_row(state, level \\ :congressional) do
    Enum.find(state_rows(level), &(&1.state == state))
  end

  @doc """
  Current scored districts ordered by their state's absolute mean–median
  gap, largest first — the /districts "map skew" sort. The gap is a
  property of the statewide map, identical for every district in the
  state; sorting by magnitude interleaves R- and D-favoring maps, the
  same symmetry the lean sort uses. Districts in states below the seat
  floor sort last, never out.
  """
  def list_districts_by_skew(level \\ :congressional) do
    skew = Map.new(state_rows(level), &{&1.state, &1.mean_median})

    VNI.Scores.list_least_compact(:composite, level)
    |> Enum.sort_by(fn district ->
      case skew[district.state] do
        nil -> {1, 0.0, district.state, district.number}
        gap -> {0, -abs(gap), district.state, district.number}
      end
    end)
  end

  defp atomize(nil), do: nil
  defp atomize(value) when is_binary(value), do: String.to_existing_atom(value)
end
