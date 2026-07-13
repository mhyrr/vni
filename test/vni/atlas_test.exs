defmodule VNI.AtlasTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
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
end
