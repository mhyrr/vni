defmodule VNIWeb.PublicLiveTest do
  use VNIWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "homepage presents the case and routes into the evidence", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-hero")
    assert has_element?(view, "#home-find-district[href='/districts']")
    assert has_element?(view, "#home-open-atlas[href='/atlas']")
    assert has_element?(view, "#home-answer-question[href='/act']")
  end

  test "atlas renders an explorable district field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/atlas")

    assert has_element?(view, "#atlas-field[phx-update='stream']")
    assert has_element?(view, "#atlas-field > a[href='/districts/md-03']")
    assert has_element?(view, "#atlas-open-directory[href='/districts']")
  end

  test "district directory sorts independent attributes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/districts")

    assert has_element?(view, "#sort-compactness.is-active")

    view
    |> element("#sort-map-bias")
    |> render_click()

    assert_patch(view, ~p"/districts?sort=map_bias")
    assert has_element?(view, "#sort-map-bias.is-active")
    assert has_element?(view, "#districts > a:first-of-type[data-slug='tx-35']")
  end

  test "district profile compares distinct measures", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/districts/md-03")

    assert has_element?(view, "#district-profile-md-03")
    assert has_element?(view, "#district-scorecard")
    assert has_element?(view, "#district-action[href='/act']")
  end

  test "methodology makes the compactness caveat visible", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/methodology")

    assert has_element?(view, "#methodology-page")
  end

  test "action prototype responds without persisting data", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/act")

    refute has_element?(view, "#fenno-response")

    view
    |> element("#answer-yes")
    |> render_click()

    assert has_element?(view, "#fenno-response")
  end
end
