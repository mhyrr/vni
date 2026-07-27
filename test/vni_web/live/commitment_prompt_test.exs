defmodule VNIWeb.CommitmentPromptTest do
  @moduledoc """
  The modal's suppression rules, which are the whole difference between
  this and the newsletter popup design 004 §1 rejected. The delay and the
  dismissal memory live in JavaScript; what is asserted here is where the
  dialog is allowed to exist at all, and what it says when it does.
  """

  use VNIWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias VNI.{Atlas, Pledges, Politics, Scores}

  setup do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: "OH",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    {:ok, district} =
      Atlas.upsert_district(map_version, %{
        state: "OH",
        number: 9,
        geom: %Geo.MultiPolygon{
          coordinates: [
            [[{-83.5, 41.6}, {-83.3, 41.6}, {-83.3, 41.8}, {-83.5, 41.8}, {-83.5, 41.6}]]
          ],
          srid: 4326
        }
      })

    {:ok, _} =
      Politics.upsert_profile(district, %{
        incumbent_name: "Marcy Kaptur",
        incumbent_party: :dem,
        incumbent_since: 1983,
        last_margin_pct: 0.9,
        last_margin_votes: 2_382,
        last_votes_cast: 264_000,
        last_margin_cycle: 2024,
        last_margin_party: :dem,
        margin_source_url: "https://doi.org/10.7910/DVN/IG0UN2"
      })

    :ok = Atlas.refresh_district_geometries!(map_version)
    :ok = Scores.score_current!()

    %{district: district}
  end

  test "fires on the pages that are trying to sign people up", %{conn: conn} do
    for path <- [~p"/", ~p"/atlas", ~p"/districts", ~p"/act"] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, "#commitment-prompt"), "expected the prompt on #{path}"
    end
  end

  test "never where a skeptic is checking our work", %{conn: conn} do
    for path <- [~p"/methodology", ~p"/sources"] do
      {:ok, view, _html} = live(conn, path)
      refute has_element?(view, "#commitment-prompt"), "prompt must not fire on #{path}"
    end
  end

  test "never inside the flow it exists to start", %{conn: conn} do
    {:ok, join, _html} = live(conn, ~p"/districts/oh-9/join")
    refute has_element?(join, "#commitment-prompt")

    {:ok, find, _html} = live(conn, ~p"/find")
    refute has_element?(find, "#commitment-prompt")
  end

  test "the confirmation page marks the reader as committed and asks nothing", %{
    district: district,
    conn: conn
  } do
    {:ok, _outcome, _pledge, token} =
      Pledges.record(district, %{"commitment" => "yes", "email" => "voter@example.com"})

    {:ok, view, _html} = live(conn, ~p"/commitment/#{token}")

    refute has_element?(view, "#commitment-prompt")
    # Colocated hook names compile fully qualified.
    assert has_element?(view, "#commitment-confirmed[phx-hook$='MarkCommitted']")
  end

  describe "what it says" do
    test "on a district page it names the seat, the incumbent, and the count", %{
      district: district,
      conn: conn
    } do
      commit!(district, "a@example.com")
      commit!(district, "b@example.com")

      {:ok, view, _html} = live(conn, ~p"/districts/oh-9")
      render_async(view)

      assert has_element?(view, "#commitment-prompt", "2 committed in OH-09")
      assert has_element?(view, "#commitment-prompt", "Will you vote against Marcy Kaptur")
      assert has_element?(view, "#commitment-prompt", "has held this seat since 1983")
      assert has_element?(view, "#commitment-prompt a[href='/districts/oh-9/join']")

      # It asks for a commitment, not a ZIP — the seat is already known.
      refute has_element?(view, "#prompt-zip")
    end

    test "an empty seat says so rather than printing a proud zero", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/districts/oh-9")
      render_async(view)

      assert has_element?(view, "#commitment-prompt", "Nobody in OH-09 has answered yet")
    end

    test "off a district page the ask is general and the ZIP is the route to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#commitment-prompt", "Will you vote against your incumbent")
      assert has_element?(view, "#commitment-prompt form[action='/find']")
      assert has_element?(view, "#prompt-zip[name='zip']")
    end

    test "the historical lens has nobody to vote against, so it asks generally", %{conn: conn} do
      {:ok, historical} =
        Atlas.create_map_version(%{
          state: "OH",
          level: :congressional,
          congress: 118,
          effective_from: ~D[2023-01-03],
          effective_until: ~D[2025-01-02],
          source_url: "https://www2.census.gov/geo/tiger/TIGER2023/CD/"
        })

      {:ok, _} =
        Atlas.upsert_district(historical, %{
          state: "OH",
          number: 9,
          geom: %Geo.MultiPolygon{
            coordinates: [
              [[{-83.6, 41.5}, {-83.2, 41.5}, {-83.2, 41.9}, {-83.6, 41.9}, {-83.6, 41.5}]]
            ],
            srid: 4326
          }
        })

      {:ok, view, _html} = live(conn, ~p"/congresses/118/districts/oh-9")
      render_async(view)

      # Present, but never inviting a commitment against a retired seat.
      assert has_element?(view, "#commitment-prompt")
      refute has_element?(view, "#commitment-prompt a[href='/districts/oh-9/join']")
      assert has_element?(view, "#prompt-zip")
    end

    test "every version can be left without committing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#commitment-prompt form[method='dialog'] button", "Not now")
    end
  end

  defp commit!(district, email) do
    {:ok, _outcome, _pledge, token} =
      Pledges.record(district, %{"commitment" => "yes", "email" => email})

    {:ok, _} = Pledges.confirm(token)
  end
end
