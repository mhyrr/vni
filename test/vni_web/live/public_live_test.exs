defmodule VNIWeb.PublicLiveTest do
  use VNIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VNI.Atlas
  alias VNI.Politics
  alias VNI.Scores

  test "homepage presents the case and routes into the evidence", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, "#home-find-district[href='/districts']")
    assert has_element?(view, "#home-open-atlas[href='/atlas']")
    assert has_element?(view, "#home-answer-question[href='/act']")
  end

  test "atlas renders an explorable district field", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/atlas")
    render_async(view)

    assert has_element?(view, "#atlas-field[phx-update='stream']")
    assert has_element?(view, "#atlas-field > a[href='/districts/md-3']")
    assert has_element?(view, "#district-md-3 svg path[d^='M']")
    assert has_element?(view, "#atlas-open-directory[href='/districts']")

    # Ranking covers drawn districts only; at-large shows the badge, not a rank.
    assert has_element?(view, "#district-md-3 .atlas-cell-meta", "Rank 1 / 2")

    assert has_element?(
             view,
             "#district-ak-0 .atlas-cell-meta",
             "AT-LARGE · no district lines drawn"
           )

    refute has_element?(view, "#district-ak-0 .atlas-cell-meta", "Rank")

    # Hover strip carries the ingested facts once they exist.
    assert has_element?(view, "#district-md-3 .atlas-cell-meta", "Sample Incumbent")
    assert has_element?(view, "#district-md-3 .atlas-cell-meta", "Pop. 789,013")
    refute has_element?(view, "#district-tx-35 .atlas-cell-meta", "Pop.")
  end

  test "district profile presents incumbent and population facts", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/districts/md-3")
    render_async(view)

    tenure = Date.utc_today().year - 2013

    assert has_element?(view, "#district-representative", "Sample Incumbent")
    assert has_element?(view, "#district-representative", "Party · D")
    assert has_element?(view, "#district-representative", "In the House since 2013")
    assert has_element?(view, "#district-representative", "Tenure · #{tenure} years")
    assert has_element?(view, "#district-representative", "789,013")
    assert has_element?(view, "#district-representative", "560,000")
    assert has_element?(view, "#district-representative", "ACS 2024 five-year")

    # Doctrine hard line: incumbent facts only, never challenger info.
    assert has_element?(view, "#district-representative", "No challenger appears here")
  end

  test "district profile omits the representative section without ingested facts", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/districts/tx-35")
    render_async(view)

    assert has_element?(view, "#district-profile-tx-35")
    refute has_element?(view, "#district-representative")
  end

  test "at-large district profile shows the exclusion instead of a rank", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/districts/ak-0")
    render_async(view)

    assert has_element?(view, "#district-profile-ak-0")
    assert has_element?(view, "#district-scorecard")
    assert has_element?(view, "#district-at-large", "AT-LARGE")
    assert has_element?(view, "#district-at-large", "excluded from the 2-district ranking")
    refute has_element?(view, "#district-profile-ak-0", "rank 1 is most compact")
  end

  test "district directory sorts independent attributes", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/districts")
    render_async(view)

    assert has_element?(view, "#sort-composite.is-active")
    assert has_element?(view, "#districts > a:first-of-type[data-slug='tx-35']")

    view
    |> element("#sort-reock")
    |> render_click()

    assert_patch(view, ~p"/districts?sort=reock")
    render_async(view)
    assert has_element?(view, "#sort-reock.is-active")
    assert has_element?(view, "#districts > a:first-of-type[data-slug='tx-35']")
  end

  test "district profile compares distinct measures", %{conn: conn} do
    seed_districts!()
    {:ok, view, _html} = live(conn, ~p"/districts/md-3")
    render_async(view)

    assert has_element?(view, "#district-profile-md-3")
    assert has_element?(view, "#district-scorecard")
    assert has_element?(view, "#district-scorecard .metric-bar", "Polsby–Popper")
    assert has_element?(view, "#district-action[href='/act']")
  end

  test "methodology makes the compactness caveat visible", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/methodology")

    assert has_element?(view, "#methodology-page")
    assert has_element?(view, "#methodology-limits", "At-large states have no lines to judge.")
    assert has_element?(view, "#methodology-limits", "Hawaii's 2nd is the worked example.")
  end

  test "action prototype responds without persisting data", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/act")

    refute has_element?(view, "#fenno-response")

    view
    |> element("#answer-yes")
    |> render_click()

    assert has_element?(view, "#fenno-response")
  end

  defp seed_districts! do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: "MD",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    {:ok, compact} =
      Atlas.upsert_district(map_version, %{
        state: "MD",
        number: 3,
        geom: square_geometry(-77.0, 39.0)
      })

    {:ok, _profile} =
      Politics.upsert_profile(compact, %{
        incumbent_name: "Sample Incumbent",
        incumbent_party: :dem,
        incumbent_since: 2013,
        incumbent_source_url: "https://unitedstates.github.io/congress-legislators/",
        population: 789_013,
        voting_age_population: 560_000,
        acs_vintage: 2024,
        population_source_url: "https://api.census.gov/data/2024/acs/acs5"
      })

    {:ok, texas_map} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    {:ok, _contorted} =
      Atlas.upsert_district(texas_map, %{
        state: "TX",
        number: 35,
        geom: hook_geometry(-98.0, 30.0)
      })

    {:ok, alaska_map} =
      Atlas.create_map_version(%{
        state: "AK",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    {:ok, _at_large} =
      Atlas.upsert_district(alaska_map, %{
        state: "AK",
        number: 0,
        geom: square_geometry(-150.0, 61.0)
      })

    :ok = Atlas.refresh_district_geometries!(map_version)
    :ok = Atlas.refresh_district_geometries!(texas_map)
    :ok = Atlas.refresh_district_geometries!(alaska_map)
    :ok = Scores.score_current!()
  end

  defp square_geometry(x, y) do
    %Geo.MultiPolygon{
      coordinates: [[[{x, y}, {x + 0.2, y}, {x + 0.2, y + 0.2}, {x, y + 0.2}, {x, y}]]],
      srid: 4326
    }
  end

  defp hook_geometry(x, y) do
    %Geo.MultiPolygon{
      coordinates: [
        [
          [
            {x, y},
            {x + 1.0, y},
            {x + 1.0, y + 0.05},
            {x + 0.05, y + 0.05},
            {x + 0.05, y + 0.95},
            {x + 1.0, y + 0.95},
            {x + 1.0, y + 1.0},
            {x, y + 1.0},
            {x, y}
          ]
        ]
      ],
      srid: 4326
    }
  end
end
