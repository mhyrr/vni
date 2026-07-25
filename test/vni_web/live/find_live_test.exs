defmodule VNIWeb.FindLiveTest do
  use VNIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VNI.{Atlas, Politics, Scores}
  alias VNI.Atlas.Postal

  setup do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: "MD",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    {:ok, west} =
      Atlas.upsert_district(map_version, %{
        state: "MD",
        number: 3,
        geom: box(-77.0, 39.0, -76.0, 40.0)
      })

    {:ok, east} =
      Atlas.upsert_district(map_version, %{
        state: "MD",
        number: 4,
        geom: box(-76.0, 39.0, -75.0, 40.0)
      })

    {:ok, _} =
      Politics.upsert_profile(west, %{
        incumbent_name: "Sample West",
        incumbent_party: :dem,
        incumbent_since: 2013
      })

    {:ok, _} =
      Politics.upsert_profile(east, %{
        incumbent_name: "Sample East",
        incumbent_party: :rep,
        incumbent_since: 2019
      })

    :ok = Atlas.refresh_district_geometries!(map_version)
    :ok = Scores.score_current!()

    zcta!("20001", box(-76.8, 39.2, -76.6, 39.4))
    zcta!("20002", box(-76.5, 39.2, -75.5, 39.8))
    zcta!("00901", box(-66.2, 18.4, -66.0, 18.5))

    :ok = Postal.refresh_areas!()
    Postal.rebuild_crosswalk!()

    %{west: west, east: east}
  end

  test "the bare page asks for a ZIP and shows its work", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/find")

    assert has_element?(view, "#find-zip[name='zip']")

    assert has_element?(
             view,
             "#find-page",
             "published geometry rather than a bought lookup table"
           )

    assert has_element?(view, "#find-page a[href='/methodology#methodology-zip']")
    refute has_element?(view, "#find-choices")
  end

  test "a ZIP inside one district lands on it — one seat is not a choice", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/districts/md-3"}}} = live(conn, ~p"/find?zip=20001")
  end

  test "ZIP+4 resolves on the first five", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/districts/md-3"}}} =
             live(conn, ~p"/find?zip=20001-4321")
  end

  test "a split ZIP shows both shapes and never picks", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/find?zip=20002")

    assert has_element?(view, "#find-page", "20002 is in 2 districts")
    assert has_element?(view, "#find-choice-md-3[href='/districts/md-3']")
    assert has_element?(view, "#find-choice-md-4[href='/districts/md-4']")

    # The shape is the point: you pick your district by looking at it.
    assert has_element?(view, "#find-choice-md-3 svg path[d^='M']")
    assert has_element?(view, "#find-choice-md-4 svg path[d^='M']")

    # Both incumbents named, no challenger anywhere.
    assert has_element?(view, "#find-choice-md-3", "Sample West")
    assert has_element?(view, "#find-choice-md-4", "Sample East")
    refute has_element?(view, "#find-page", "challenger")

    # The share is labelled as area, with the caveat that area is not people.
    assert has_element?(view, "#find-choice-md-3", "of the ZIP")
    assert has_element?(view, "#find-page", "It is not how many people")
  end

  test "a real area with no voting seat is explained, not 404'd", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/find?zip=00901")

    assert has_element?(view, "#find-page", "no vote to withhold")
    assert has_element?(view, "#find-page", "cannot vote on final passage")
    refute has_element?(view, "#find-choices")
  end

  test "an unknown ZIP explains why a ZIP can have no polygon", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/find?zip=99999")

    assert has_element?(view, "#find-page", "The Census has no area for 99999")
    assert has_element?(view, "#find-page", "PO boxes")
  end

  test "malformed input is refused in words the form used", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/find?zip=nope")

    assert has_element?(view, "#find-page", "That isn't a ZIP code")
    assert has_element?(view, "#find-page", "We take ZIP+4 too")
  end

  describe "the chrome" do
    test "carries the ZIP field as the primary call to action", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#header-find[action='/find']")
      assert has_element?(view, "#header-zip[name='zip']")

      # The hero asks for a ZIP, with the directory as the way past it.
      assert has_element?(view, "#home-find[action='/find']")
      assert has_element?(view, "#home-find-district[href='/districts']")
    end

    test "asks for nothing on the pages where our work is checked", %{conn: conn} do
      for path <- [~p"/methodology", ~p"/sources"] do
        {:ok, view, _html} = live(conn, path)

        refute has_element?(view, "#header-find")
        refute has_element?(view, "#header-zip")
        refute has_element?(view, "#header-action")
      end
    end
  end

  defp zcta!(code, geom) do
    %VNI.Atlas.Zcta{}
    |> VNI.Atlas.Zcta.changeset(%{
      zcta5: code,
      geom: geom,
      vintage: 2025,
      source_url: Postal.source_url()
    })
    |> VNI.Repo.insert!()
  end

  defp box(west, south, east, north) do
    %Geo.MultiPolygon{
      coordinates: [
        [[{west, south}, {east, south}, {east, north}, {west, north}, {west, south}]]
      ],
      srid: 4326
    }
  end
end
