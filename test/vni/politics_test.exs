defmodule VNI.PoliticsTest do
  use VNI.DataCase, async: true

  alias VNI.{Atlas, Politics}

  test "partisan lean is a weighted two-cycle margin vs the nation" do
    # District ran R+10 and R+8 while the nation ran R+1 and D+2 (as R-D margins).
    assert_in_delta Politics.partisan_lean([10.0, 8.0], [1.0, -2.0]), 9.25, 0.001

    # Single-cycle fallback is a plain difference.
    assert Politics.partisan_lean([5.0], [2.0]) == 3.0
  end

  test "profile upsert is idempotent per district" do
    {:ok, mv} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2023-01-03]
      })

    {:ok, district} = Atlas.upsert_district(mv, %{state: "TX", number: 33})

    {:ok, p1} =
      Politics.upsert_profile(district, %{
        incumbent_name: "Marc Veasey",
        incumbent_party: :dem,
        incumbent_since: 2013
      })

    {:ok, p2} = Politics.upsert_profile(district, %{last_margin_pct: 28.4})

    assert p1.id == p2.id
    assert p2.last_margin_pct == 28.4
  end
end
