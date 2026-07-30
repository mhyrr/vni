defmodule VNIWeb.SocialMetaTest do
  @moduledoc """
  The unfurl, asserted on the dead render.

  Every test here uses `get/2` rather than `live/2` deliberately. A
  crawler runs no JavaScript and never connects a socket, so the static
  HTTP response is the entire surface these tags exist for — asserting
  through a live view would prove something no platform ever sees.
  """

  use VNIWeb.ConnCase, async: false

  alias VNI.{Atlas, Politics, Scores}

  setup do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: "MD",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/",
        authority: :legislature,
        controlling_party: :dem,
        authorship_source_url: "https://redistricting.lls.edu/state/maryland/"
      })

    {:ok, district} =
      Atlas.upsert_district(map_version, %{
        state: "MD",
        number: 3,
        geom: %Geo.MultiPolygon{
          coordinates: [
            [[{-77.0, 39.0}, {-76.8, 39.0}, {-76.8, 39.2}, {-77.0, 39.2}, {-77.0, 39.0}]]
          ],
          srid: 4326
        }
      })

    {:ok, _profile} =
      Politics.upsert_profile(district, %{
        incumbent_name: "Sample Incumbent",
        incumbent_party: :dem,
        incumbent_since: 2013,
        last_margin_pct: 9.2,
        last_margin_votes: 38_412,
        last_votes_cast: 417_522,
        last_margin_cycle: 2024,
        last_margin_party: :dem,
        margin_source_url: "https://doi.org/10.7910/DVN/IG0UN2"
      })

    :ok = Scores.score_current!()

    :ok
  end

  defp meta(html, property) do
    ~r/<meta [^>]*(?:property|name)="#{Regex.escape(property)}" content="([^"]*)"/
    |> Regex.run(html, capture: :all_but_first)
    |> case do
      [value] -> value
      nil -> nil
    end
  end

  test "every page unfurls with a title, a description, and a large image", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert meta(html, "og:title") == "Vote No Incumbents"
    assert meta(html, "og:description") =~ "entrench power"
    assert meta(html, "twitter:card") == "summary_large_image"
    assert meta(html, "og:image") =~ "images/og/default"
  end

  test "the image URL is absolute — a relative one unfurls as nothing", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert meta(html, "og:image") =~ ~r"^https?://"
  end

  test "a page's own title carries into the unfurl", %{conn: conn} do
    html = conn |> get(~p"/methodology") |> html_response(200)

    refute meta(html, "og:title") == "Vote No Incumbents"
  end

  test "a current district unfurls into its own card", %{conn: conn} do
    html = conn |> get(~p"/districts/md-3") |> html_response(200)

    assert meta(html, "og:image") =~ "images/og/districts/md-3"
  end

  test "a historical district falls back — its card would state current facts", %{conn: conn} do
    html = conn |> get(~p"/congresses/118/districts/md-3") |> html_response(200)

    assert meta(html, "og:image") =~ "images/og/default"
    refute meta(html, "og:image") =~ "districts/md-3"
  end

  test "the card the tags point at is actually on disk" do
    path = Path.join([File.cwd!(), "priv/static", VNIWeb.SocialMeta.default_image()])

    assert File.exists?(path),
           "og:image points at #{path}, which does not exist — run mix vni.og.cards"
  end
end
