defmodule VNIWeb.StateLiveTest do
  use VNIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VNI.{Atlas, Politics, Repo}
  alias VNI.Scores

  test "index renders a districted state row with fact pair and skew, at-large in the strip", %{
    conn: conn
  } do
    seed_districted_state!()
    seed_at_large_state!()

    {:ok, view, _html} = live(conn, ~p"/states")

    assert has_element?(view, "#state-tx", "Texas")
    assert has_element?(view, "#state-tx .seats-votes-strip")
    assert has_element?(view, "#state-tx", "R+0.5 seats")
    assert has_element?(view, "#state-tx", "50.0 / 50.0")
    assert has_element?(view, "#state-tx", "3 / 2")
    assert has_element?(view, "#state-tx", "R+2.0")
    assert has_element?(view, "#state-index #state-tx a[href='/states/tx']")

    # At-large sits in the strip below the table, never in the sortable rows.
    refute has_element?(view, "#state-table #state-wy")
    assert has_element?(view, "#state-at-large a[href='/states/wy']", "Wyoming")
  end

  test "index sort params switch ordering and unknown sort falls back to default", %{conn: conn} do
    seed_districted_state!()
    seed_small_state!()

    {:ok, view, _html} = live(conn, ~p"/states")
    assert has_element?(view, "#sort-gap.is-active")

    view |> element("#sort-seats") |> render_click()
    assert_patch(view, ~p"/states?sort=seats")
    rows = view |> element("#state-rows") |> render()

    codes =
      Regex.scan(~r/id="state-([a-z]{2})"/, rows)
      |> Enum.map(fn [_, code] -> code end)

    assert Enum.take(codes, 2) == ["tx", "ut"]

    {:ok, view, _html} = live(conn, ~p"/states?sort=bogus")
    assert has_element?(view, "#sort-gap.is-active")
  end

  test "show page: districted state renders authorship, fact pair, skew", %{conn: conn} do
    seed_districted_state!()

    {:ok, view, _html} = live(conn, ~p"/states/tx")

    assert has_element?(view, "#state-authorship", "State legislature")
    assert has_element?(view, "#state-authorship", "Republican control at adoption")
    assert has_element?(view, "#state-authorship a[href*='redistricting.lls.edu']")

    assert has_element?(view, "#state-fact-r", "50.0% of the two-party presidential vote")
    assert has_element?(view, "#state-fact-r", "3 of 5 seats")
    assert has_element?(view, "#state-fact-d", "50.0% of the two-party presidential vote")
    assert has_element?(view, "#state-fact-d", "2 of 5 seats")

    assert has_element?(view, "#state-skew-value", "Mean–median gap: R+2.0")

    assert has_element?(
             view,
             "#state-skew-line a[href='/methodology#methodology-bias']"
           )
  end

  test "show page: a 2-seat state renders the too-few-districts line", %{conn: conn} do
    seed_small_state!()

    {:ok, view, _html} = live(conn, ~p"/states/ut")

    assert has_element?(
             view,
             "#state-skew-too-few",
             "Mean–median gap: — too few districts to measure (2)"
           )

    refute has_element?(view, "#state-skew-value")
  end

  test "show page: at-large renders the no-lines copy and no bias block", %{conn: conn} do
    seed_at_large_state!()

    {:ok, view, _html} = live(conn, ~p"/states/wy")

    assert has_element?(
             view,
             "#state-authorship",
             "No map drawn. One representative, statewide"
           )

    refute has_element?(view, "#state-bias")
  end

  test "show page renders the chart with a circle only in presidential years", %{conn: conn} do
    seed_districted_state!()

    {:ok, sc_id} =
      Repo.insert(
        struct(VNI.Politics.StateCycle, %{
          state: "TX",
          cycle: 2022,
          seats_dem: 2,
          seats_rep: 3,
          seats_other: 0,
          pres_r_share: nil,
          seats_source_url: "https://example.test/house"
        })
      )

    assert sc_id

    {:ok, view, _html} = live(conn, ~p"/states/tx")
    html = render(view)

    assert html =~ ~r/<circle/
    assert Regex.scan(~r/<circle/, html) |> length() == 1
    assert html =~ "state-history-chart"
  end

  test "district rows link to /districts/:slug", %{conn: conn} do
    seed_districted_state!()

    {:ok, view, _html} = live(conn, ~p"/states/tx")

    assert has_element?(view, "#state-district-rows a[href='/districts/tx-1']")
    assert has_element?(view, "#state-district-rows a[href='/districts/tx-2']")
  end

  test "unknown state code redirects to /states with a flash", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/states"}}} = live(conn, ~p"/states/zz")
  end

  defp seed_districted_state! do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://example.test/tx.zip",
        authority: :legislature,
        controlling_party: :rep,
        authorship_source_url: "https://redistricting.lls.edu/state/texas/"
      })

    # Sorted: 30, 40, 50, 60, 60 — median 50, mean 48, mean_median = R+2.0.
    shares = [30.0, 40.0, 50.0, 60.0, 60.0]

    for {share, i} <- Enum.with_index(shares) do
      number = i + 1

      {:ok, district} =
        Atlas.upsert_district(mv, %{state: "TX", number: number, geom: geom(number)})

      {:ok, _} = Politics.upsert_profile(district, %{pres_share_2024: share})
    end

    :ok = Atlas.refresh_district_geometries!(mv)
    :ok = Scores.score_current!()

    Repo.insert!(%VNI.Politics.StateCycle{
      state: "TX",
      cycle: 2024,
      seats_dem: 2,
      seats_rep: 3,
      seats_other: 0,
      pres_r_share: 50.0,
      seats_source_url: "https://example.test/house",
      pres_source_url: "https://example.test/pres"
    })

    :ok
  end

  defp seed_small_state! do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: "UT",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://example.test/ut.zip",
        authority: :legislature,
        controlling_party: :rep,
        authorship_source_url: "https://redistricting.lls.edu/state/utah/"
      })

    for number <- [1, 2] do
      {:ok, _district} =
        Atlas.upsert_district(mv, %{state: "UT", number: number, geom: geom(20 + number)})
    end

    :ok = Atlas.refresh_district_geometries!(mv)
    :ok = Scores.score_current!()

    Repo.insert!(%VNI.Politics.StateCycle{
      state: "UT",
      cycle: 2024,
      seats_dem: 0,
      seats_rep: 2,
      seats_other: 0,
      pres_r_share: 58.0,
      seats_source_url: "https://example.test/house"
    })

    :ok
  end

  defp seed_at_large_state! do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: "WY",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://example.test/wy.zip",
        authorship_source_url: "https://redistricting.lls.edu/state/wyoming/"
      })

    {:ok, _district} = Atlas.upsert_district(mv, %{state: "WY", number: 0, geom: geom(40)})

    :ok = Atlas.refresh_district_geometries!(mv)
    :ok = Scores.score_current!()

    Repo.insert!(%VNI.Politics.StateCycle{
      state: "WY",
      cycle: 2024,
      seats_dem: 0,
      seats_rep: 1,
      seats_other: 0,
      pres_r_share: 70.0,
      seats_source_url: "https://example.test/house"
    })

    :ok
  end

  defp geom(number) do
    x = -100.0 + number
    y = 30.0

    %Geo.MultiPolygon{
      coordinates: [[[{x, y}, {x + 0.5, y}, {x + 0.5, y + 0.5}, {x, y + 0.5}, {x, y}]]],
      srid: 4326
    }
  end
end
