defmodule VNI.Atlas.MapAuthorship do
  @moduledoc """
  Hand-curated authorship of each state's current congressional map: who
  drew it (authority) and which party controlled the process at adoption.
  Curation with citations is the feature — every row cites Loyola Law
  School's All About Redistricting state page (non-partisan reference).

  Semantics, decided on TK-004:

    * `authority` is the institution that produced the map actually in
      force for the 119th Congress, including mid-decade court-ordered
      redraws (AL 2023, GA 2023, LA 2024, NC 2023, NY 2024).
    * `controlling_party` is the party in control of that process at
      adoption — the trifecta party for legislature maps (the mechanical
      fact, even where statute constrains drafting, as in Iowa),
      `:split` for evenly appointed commissions, `:nonpartisan` for
      citizen commissions and court/special-master maps.
    * At-large states (single district) have no lines to draw: authority
      and party stay nil, the citation still documents the seat.

  Rows describe the *current* map versions. When a mid-decade redraw
  lands for the 120th Congress (TX/MO/OH 2025 activity), it enters as a
  new map version with its own authorship row — never by editing these.
  """

  require Logger

  alias VNI.Atlas
  alias VNI.Repo

  @loyola "https://redistricting.lls.edu/state"

  # {state, authority, controlling_party, loyola page slug}
  @rows [
    {"AL", :special_master, :nonpartisan, "alabama"},
    {"AK", nil, nil, "alaska"},
    {"AZ", :independent_commission, :nonpartisan, "arizona"},
    {"AR", :legislature, :rep, "arkansas"},
    {"CA", :independent_commission, :nonpartisan, "california"},
    {"CO", :independent_commission, :nonpartisan, "colorado"},
    {"CT", :special_master, :nonpartisan, "connecticut"},
    {"DE", nil, nil, "delaware"},
    {"FL", :legislature, :rep, "florida"},
    {"GA", :legislature, :rep, "georgia"},
    {"HI", :politician_commission, :split, "hawaii"},
    {"ID", :independent_commission, :nonpartisan, "idaho"},
    {"IL", :legislature, :dem, "illinois"},
    {"IN", :legislature, :rep, "indiana"},
    {"IA", :legislature, :rep, "iowa"},
    {"KS", :legislature, :rep, "kansas"},
    {"KY", :legislature, :rep, "kentucky"},
    {"LA", :legislature, :rep, "louisiana"},
    {"ME", :legislature, :dem, "maine"},
    {"MD", :legislature, :dem, "maryland"},
    {"MA", :legislature, :dem, "massachusetts"},
    {"MI", :independent_commission, :nonpartisan, "michigan"},
    {"MN", :court, :nonpartisan, "minnesota"},
    {"MS", :legislature, :rep, "mississippi"},
    {"MO", :legislature, :rep, "missouri"},
    {"MT", :independent_commission, :nonpartisan, "montana"},
    {"NE", :legislature, :rep, "nebraska"},
    {"NV", :legislature, :dem, "nevada"},
    {"NH", :special_master, :nonpartisan, "new-hampshire"},
    {"NJ", :politician_commission, :split, "new-jersey"},
    {"NM", :legislature, :dem, "new-mexico"},
    {"NY", :legislature, :dem, "new-york"},
    {"NC", :legislature, :rep, "north-carolina"},
    {"ND", nil, nil, "north-dakota"},
    {"OH", :legislature, :rep, "ohio"},
    {"OK", :legislature, :rep, "oklahoma"},
    {"OR", :legislature, :dem, "oregon"},
    {"PA", :court, :nonpartisan, "pennsylvania"},
    {"RI", :legislature, :dem, "rhode-island"},
    {"SC", :legislature, :rep, "south-carolina"},
    {"SD", nil, nil, "south-dakota"},
    {"TN", :legislature, :rep, "tennessee"},
    {"TX", :legislature, :rep, "texas"},
    {"UT", :legislature, :rep, "utah"},
    {"VT", nil, nil, "vermont"},
    {"VA", :special_master, :nonpartisan, "virginia"},
    {"WA", :independent_commission, :split, "washington"},
    {"WV", :legislature, :rep, "west-virginia"},
    {"WI", :court, :nonpartisan, "wisconsin"},
    {"WY", nil, nil, "wyoming"}
  ]

  def rows do
    Enum.map(@rows, fn {state, authority, controlling_party, slug} ->
      %{
        state: state,
        authority: authority,
        controlling_party: controlling_party,
        authorship_source_url: "#{@loyola}/#{slug}/"
      }
    end)
  end

  @doc """
  Stamp authorship onto the current congressional map version of every
  state. Rerunnable — plain updates keyed on the current map. Returns
  `%{updated: n, missing_states: [state]}`; a missing state means its
  map version has not been ingested yet.
  """
  def seed_current! do
    results =
      Enum.map(rows(), fn row ->
        case Atlas.current_map_version(row.state, :congressional) do
          nil ->
            Logger.warning("no current congressional map version for #{row.state}")
            {:missing, row.state}

          map_version ->
            map_version
            |> Ecto.Changeset.change(
              authority: row.authority,
              controlling_party: row.controlling_party,
              authorship_source_url: row.authorship_source_url
            )
            |> Repo.update!()

            :ok
        end
      end)

    %{
      updated: Enum.count(results, &(&1 == :ok)),
      missing_states: for({:missing, state} <- results, do: state)
    }
  end
end
