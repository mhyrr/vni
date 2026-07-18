defmodule VNI.AtlasTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Atlas.Census
  alias VNI.Atlas.District

  defp create_map_version!(attrs \\ %{}) do
    defaults = %{
      state: "TX",
      level: :congressional,
      congress: 119,
      effective_from: ~D[2023-01-03],
      authority: :legislature,
      controlling_party: :rep
    }

    {:ok, mv} = Atlas.create_map_version(Map.merge(defaults, attrs))
    mv
  end

  test "slug is derived from state and number" do
    assert District.build_slug("TX", 33) == "tx-33"
    assert District.build_slug("WY", 0) == "wy-0"
  end

  test "current_map_version resolves the open-ended version" do
    _old =
      create_map_version!(%{
        congress: 118,
        effective_from: ~D[2021-01-03],
        effective_until: ~D[2023-01-02]
      })

    current = create_map_version!()

    assert Atlas.current_map_version("TX", :congressional).id == current.id
  end

  test "map version upsert is idempotent on its source identity" do
    attrs = %{
      state: "TX",
      level: :congressional,
      congress: 119,
      effective_from: ~D[2025-01-03],
      source_url: "https://example.test/first.zip"
    }

    assert {:ok, first} = Atlas.upsert_map_version(attrs)

    assert {:ok, second} =
             Atlas.upsert_map_version(%{attrs | source_url: "https://example.test/corrected.zip"})

    assert second.id == first.id
    assert second.source_url == "https://example.test/corrected.zip"
  end

  test "map version upsert re-asserts the effectivity window on rerun" do
    attrs = %{
      state: "NC",
      level: :congressional,
      congress: 118,
      effective_from: ~D[2023-01-03],
      effective_until: ~D[2025-01-01],
      source_url: "https://example.test/cd118.zip"
    }

    assert {:ok, first} = Atlas.upsert_map_version(attrs)
    assert first.effective_until == ~D[2025-01-01]

    # A rerun with the corrected close date heals the window in place.
    assert {:ok, healed} = Atlas.upsert_map_version(%{attrs | effective_until: ~D[2025-01-02]})
    assert healed.id == first.id
    assert healed.effective_until == ~D[2025-01-02]
  end

  defp ingest_attrs(overrides) do
    Map.merge(
      %{state: "NC", level: :congressional, congress: 118, effective_from: ~D[2023-01-03]},
      overrides
    )
  end

  describe "assert_ingestable_map_version!/1" do
    test "anything is ingestable when the state has no current map" do
      assert :ok = Atlas.assert_ingestable_map_version!(ingest_attrs(%{}))

      assert :ok =
               Atlas.assert_ingestable_map_version!(
                 ingest_attrs(%{effective_until: ~D[2025-01-02]})
               )
    end

    test "a current ingest matching the existing current map's identity passes" do
      create_map_version!(%{state: "NC", congress: 119, effective_from: ~D[2025-01-03]})

      assert :ok =
               Atlas.assert_ingestable_map_version!(
                 ingest_attrs(%{congress: 119, effective_from: ~D[2025-01-03]})
               )
    end

    test "a current ingest conflicting with the existing current map raises" do
      create_map_version!(%{state: "NC", congress: 119, effective_from: ~D[2025-01-03]})

      assert_raise RuntimeError, ~r/ambiguous current map/, fn ->
        Atlas.assert_ingestable_map_version!(ingest_attrs(%{congress: 120}))
      end
    end

    test "a historical ingest under a later current congress passes" do
      create_map_version!(%{state: "NC", congress: 119, effective_from: ~D[2025-01-03]})

      assert :ok =
               Atlas.assert_ingestable_map_version!(
                 ingest_attrs(%{effective_until: ~D[2025-01-02]})
               )
    end

    test "a historical ingest at or after the current congress raises" do
      create_map_version!(%{state: "NC", congress: 118, effective_from: ~D[2023-01-03]})

      assert_raise RuntimeError, ~r/supersede the current map/, fn ->
        Atlas.assert_ingestable_map_version!(ingest_attrs(%{effective_until: ~D[2025-01-02]}))
      end

      assert_raise RuntimeError, ~r/supersede the current map/, fn ->
        Atlas.assert_ingestable_map_version!(
          ingest_attrs(%{congress: 119, effective_until: ~D[2027-01-02]})
        )
      end
    end
  end

  test "list_map_versions returns a congress's maps, current or closed" do
    closed =
      create_map_version!(%{
        state: "LA",
        congress: 118,
        effective_from: ~D[2023-01-03],
        effective_until: ~D[2025-01-02]
      })

    current = create_map_version!(%{state: "LA", congress: 119, effective_from: ~D[2025-01-03]})
    _other_level = create_map_version!(%{state: "LA", congress: 118, level: :state_leg})

    assert [%{id: closed_id}] = Atlas.list_map_versions(118)
    assert closed_id == closed.id
    assert [%{id: current_id}] = Atlas.list_map_versions(119)
    assert current_id == current.id
  end

  test "current Census manifest covers exactly the 435 voting districts" do
    manifest = Census.current_manifest()

    assert length(manifest) == 50
    assert Enum.sum(Enum.map(manifest, & &1.seats)) == 435
    assert Enum.uniq_by(manifest, & &1.fips) == manifest
    refute Enum.any?(manifest, &(&1.code == "DC"))

    assert Enum.all?(manifest, fn state ->
             String.ends_with?(state.source_url, "tl_2025_#{state.fips}_cd119.zip")
           end)
  end

  test "the 118th Congress manifest uses TIGER2023 per-state archives" do
    manifest = Census.manifest(118)

    assert Enum.sum(Enum.map(manifest, & &1.seats)) == 435

    assert Enum.all?(manifest, fn state ->
             String.ends_with?(state.source_url, "TIGER2023/CD/tl_2023_#{state.fips}_cd118.zip")
           end)

    seats = Map.new(manifest, &{&1.code, &1.seats})
    assert seats["NC"] == 14
    assert seats["TX"] == 38
    assert seats["MT"] == 2
  end

  test "the 117th Congress manifest maps to the national cd116 archive" do
    manifest = Census.manifest(117)

    # The 117th was seated on the 116th's lines; TIGER never published a
    # cd117 layer, and the cd116 era predates per-state files.
    assert Enum.sum(Enum.map(manifest, & &1.seats)) == 435

    assert Enum.all?(manifest, fn state ->
             String.ends_with?(state.source_url, "TIGER2021/CD/tl_2021_us_cd116.zip")
           end)

    # 2010-census apportionment, not 2020.
    seats = Map.new(manifest, &{&1.code, &1.seats})
    assert seats["TX"] == 36
    assert seats["NC"] == 13
    assert seats["MT"] == 1
    assert seats["CA"] == 53
  end

  test "unsupported congresses are refused by name" do
    assert_raise ArgumentError, ~r/unsupported congress 116/, fn -> Census.manifest(116) end
  end

  test "district upsert is idempotent on (map_version, slug)" do
    mv = create_map_version!()

    {:ok, d1} = Atlas.upsert_district(mv, %{state: "TX", number: 33})
    {:ok, d2} = Atlas.upsert_district(mv, %{state: "TX", number: 33, land_area_sqkm: 500.0})

    assert d1.id == d2.id
    assert d2.land_area_sqkm == 500.0
    assert d2.slug == "tx-33"
  end

  test "slug lookup resolves against the current map only" do
    old =
      create_map_version!(%{
        congress: 118,
        effective_from: ~D[2021-01-03],
        effective_until: ~D[2025-01-02]
      })

    current = create_map_version!(%{effective_from: ~D[2025-01-03]})

    {:ok, _} = Atlas.upsert_district(old, %{state: "TX", number: 33})
    {:ok, current_district} = Atlas.upsert_district(current, %{state: "TX", number: 33})

    found = Atlas.get_district_by_slug("tx-33")

    assert found.id == current_district.id
    assert found.map_version_id == current.id
  end

  test "superseding a map version closes it out" do
    mv = create_map_version!()
    {:ok, closed} = Atlas.supersede_map_version(mv, ~D[2025-12-31])

    assert closed.effective_until == ~D[2025-12-31]
    assert Atlas.current_map_version("TX", :congressional) == nil
  end

  test "geometry refresh derives display geometry and geodesic measurements" do
    map_version = create_map_version!()

    geometry = %Geo.MultiPolygon{
      coordinates: [
        [[{-97.0, 30.0}, {-97.0, 30.1}, {-96.9, 30.1}, {-96.9, 30.0}, {-97.0, 30.0}]]
      ],
      srid: 4326
    }

    assert {:ok, district} = Atlas.upsert_district(map_version, %{number: 33, geom: geometry})
    assert :ok = Atlas.refresh_district_geometries!(map_version)

    refreshed = VNI.Repo.get!(District, district.id)
    assert %Geo.MultiPolygon{} = refreshed.geom_simplified
    assert refreshed.land_area_sqkm > 0.0
    assert refreshed.perimeter_km > 0.0
  end
end
