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

    # Independent ingests share this row: a partial upsert must merge,
    # never null out fields another ingest owns.
    assert p2.incumbent_name == "Marc Veasey"
    assert p2.incumbent_since == 2013
  end

  describe "legislators ingest" do
    setup do
      {:ok, mv} =
        Atlas.create_map_version(%{
          state: "TX",
          level: :congressional,
          congress: 119,
          effective_from: ~D[2023-01-03]
        })

      {:ok, district} = Atlas.upsert_district(mv, %{state: "TX", number: 33})
      %{district: district}
    end

    test "upserts sitting House members, skipping senators and delegates", ctx do
      summary = Politics.Legislators.ingest_current!(yaml: fixture_yaml())

      assert summary.ingested == 1
      assert summary.skipped_non_voting == 1
      assert summary.missing_districts == ["ca-12"]

      profile = Politics.get_profile(ctx.district.id)
      assert profile.incumbent_name == "Marc A. Veasey"
      assert profile.incumbent_party == :dem
      assert profile.incumbent_since == 2013
      assert profile.bioguide_id == "V000131"
      assert profile.incumbent_source_url == Politics.Legislators.source_url()

      # Rerun is idempotent — same row, refreshed in place.
      assert %{ingested: 1} = Politics.Legislators.ingest_current!(yaml: fixture_yaml())
      assert Politics.get_profile(ctx.district.id).id == profile.id
    end

    test "an unmapped party raises instead of being coerced" do
      yaml = """
      - id: {bioguide: X000001}
        name: {first: Pat, last: Example}
        terms:
        - {type: rep, start: '2025-01-03', end: '2027-01-03', state: TX, district: 33, party: Libertarian}
      """

      assert_raise ArgumentError, ~r/unmapped party/, fn ->
        Politics.Legislators.ingest_current!(yaml: yaml)
      end
    end

    defp fixture_yaml do
      """
      - id: {bioguide: V000131}
        name: {first: Marc, last: Veasey, official_full: Marc A. Veasey}
        terms:
        - {type: rep, start: '2013-01-03', end: '2015-01-03', state: TX, district: 33, party: Democrat}
        - {type: rep, start: '2025-01-03', end: '2027-01-03', state: TX, district: 33, party: Democrat}
      - id: {bioguide: C001056}
        name: {first: John, last: Cornyn}
        terms:
        - {type: sen, start: '2021-01-03', end: '2027-01-03', state: TX, party: Republican}
      - id: {bioguide: N000147}
        name: {first: Eleanor, last: Norton}
        terms:
        - {type: rep, start: '2025-01-03', end: '2027-01-03', state: DC, district: 0, party: Democrat}
      - id: {bioguide: P000197}
        name: {first: Nancy, last: Pelosi}
        terms:
        - {type: rep, start: '2025-01-03', end: '2027-01-03', state: CA, district: 12, party: Democrat}
      """
    end
  end
end
