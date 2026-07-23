defmodule VNIWeb.HealthControllerTest do
  use VNIWeb.ConnCase

  test "returns 200 with a plain body when the repo answers", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "leaks no build, version, or connection detail", %{conn: conn} do
    body = conn |> get(~p"/healthz") |> Map.fetch!(:resp_body)

    refute body =~ "postgres"
    refute body =~ "Elixir"
    refute body =~ "vni_test"
  end

  test "skips the browser pipeline, so it sets no session cookie", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert conn.resp_cookies == %{}
  end
end
