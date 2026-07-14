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
