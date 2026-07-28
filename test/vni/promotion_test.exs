defmodule VNI.PromotionTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Atlas.{Zcta, ZctaDistrict}
  alias VNI.Politics.DistrictProfile
  alias VNI.Promotion

  setup do
    map_version = map_version!("MD")
    west = district!(map_version, 3)
    east = district!(map_version, 4)

    profile!(west, 1_234)
    profile!(east, 5_678)

    # Two ZCTAs that resolve, and one that does not. The third is the
    # District of Columbia case: a real ZCTA whose seat elects a delegate
    # who cannot vote on final passage, which `Postal.resolve/1` reports
    # as `:no_district` rather than `:unknown`. It only survives that
    # distinction in production if the row itself travels.
    inside = zcta!("20001")
    straddle = zcta!("20002")
    _no_district = zcta!("20003")

    pair!(inside, west, 1.0)
    pair!(straddle, west, 0.6)
    pair!(straddle, east, 0.4)

    %{dir: tmp_dir(), west: west, east: east}
  end

  describe "export!/1 then load!/1" do
    test "restores every row through its natural key", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()

      assert %{zctas: 3, crosswalk: 3, margins: 2} = Promotion.load!(dir)

      assert Repo.all(from(z in Zcta, select: z.zcta5, order_by: z.zcta5)) ==
               ~w(20001 20002 20003)

      assert Repo.aggregate(ZctaDistrict, :count) == 3

      assert Repo.all(from(p in DistrictProfile, select: p.last_margin_votes)) |> Enum.sort() ==
               [1_234, 5_678]
    end

    test "a ZCTA in no district still travels", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()
      Promotion.load!(dir)

      assert Repo.get_by(Zcta, zcta5: "20003")

      assert Repo.aggregate(
               from(zd in ZctaDistrict,
                 join: z in Zcta,
                 on: z.id == zd.zcta_id,
                 where: z.zcta5 == "20003"
               ),
               :count
             ) == 0
    end

    test "shares survive the round trip exactly", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()
      Promotion.load!(dir)

      shares =
        Repo.all(
          from(zd in ZctaDistrict,
            join: z in Zcta,
            on: z.id == zd.zcta_id,
            where: z.zcta5 == "20002",
            select: zd.zcta_share,
            order_by: [desc: zd.zcta_share]
          )
        )

      assert shares == [0.6, 0.4]
    end

    test "loading twice changes nothing", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()

      first = Promotion.load!(dir)
      assert Promotion.load!(dir) == first
      assert Repo.aggregate(ZctaDistrict, :count) == 3
      assert Repo.aggregate(Zcta, :count) == 3
    end
  end

  describe "geometry" do
    test "does not travel — a promoted ZCTA arrives without it", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()
      Promotion.load!(dir)

      assert Repo.get_by(Zcta, zcta5: "20001").geom == nil
    end

    test "is left alone where it already exists", %{dir: dir} do
      Promotion.export!(dir)

      # No clear: the polygons are still here, as they would be on a
      # machine that ingested them. A promotion must not wipe them.
      Promotion.load!(dir)

      assert %Geo.MultiPolygon{} = Repo.get_by(Zcta, zcta5: "20001").geom
    end
  end

  describe "the crosswalk is replaced wholesale" do
    test "a pair the artifact no longer carries is dropped", %{dir: dir, east: east} do
      Promotion.export!(dir)

      # A pair that would not survive today's sliver rule, sitting in the
      # database from an older map. Upserting would leave it; the load
      # deletes and rebuilds, as rebuild_crosswalk!/1 does.
      stale = zcta!("20009")
      pair!(stale, east, 0.001)

      Promotion.load!(dir)

      assert Repo.aggregate(ZctaDistrict, :count) == 3

      assert Repo.aggregate(
               from(zd in ZctaDistrict,
                 join: z in Zcta,
                 on: z.id == zd.zcta_id,
                 where: z.zcta5 == "20009"
               ),
               :count
             ) == 0
    end
  end

  describe "refusing to guess" do
    test "raises on a district slug this database does not have", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()

      # The map moved out from under the artifact.
      Repo.delete_all(DistrictProfile)
      Repo.delete_all(Atlas.District)

      assert_raise RuntimeError, ~r/no district for "md-3"/, fn ->
        Promotion.load!(dir)
      end
    end

    test "raises when a margin has no profile to land on", %{dir: dir} do
      Promotion.export!(dir)
      clear_promoted!()
      Repo.delete_all(DistrictProfile)

      assert_raise RuntimeError, ~r/no district profile for md-/, fn ->
        Promotion.load!(dir)
      end
    end

    test "raises on an artifact whose columns have moved", %{dir: dir} do
      Promotion.export!(dir)

      path = Path.join(dir, "margins.csv.gz")
      File.write!(path, :zlib.gzip("slug,votes\nmd-3,1234\n"))

      assert_raise RuntimeError, ~r/expected \["district_slug", "last_margin_votes"\]/, fn ->
        Promotion.load!(dir)
      end
    end

    test "raises when there is no artifact at all" do
      dir = tmp_dir()

      assert_raise RuntimeError, ~r/run `mix vni.promote.export`/, fn ->
        Promotion.load!(dir)
      end
    end
  end

  ## Fixtures

  defp clear_promoted! do
    Repo.delete_all(ZctaDistrict)
    Repo.delete_all(Zcta)
    Repo.update_all(DistrictProfile, set: [last_margin_votes: nil])
  end

  defp tmp_dir do
    dir =
      Path.join([
        System.tmp_dir!(),
        "vni-promotion-test",
        Integer.to_string(System.unique_integer([:positive]))
      ])

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    dir
  end

  defp map_version!(state) do
    {:ok, map_version} =
      Atlas.create_map_version(%{
        state: state,
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03],
        source_url: "https://www2.census.gov/geo/tiger/TIGER2025/CD/"
      })

    map_version
  end

  defp district!(map_version, number) do
    {:ok, district} =
      Atlas.upsert_district(map_version, %{
        state: map_version.state,
        number: number,
        geom: box(-77.0, 39.0, -76.0, 40.0)
      })

    district
  end

  defp profile!(district, margin_votes) do
    %DistrictProfile{district_id: district.id}
    |> DistrictProfile.changeset(%{last_margin_votes: margin_votes})
    |> Repo.insert!()
  end

  defp zcta!(code) do
    %Zcta{}
    |> Zcta.changeset(%{
      zcta5: code,
      geom: box(-76.8, 39.2, -76.6, 39.4),
      vintage: 2025,
      source_url: VNI.Atlas.Postal.source_url()
    })
    |> Repo.insert!()
    |> then(fn zcta ->
      # `area_sqkm` is computed by the ingest, and the artifact carries it.
      Repo.update_all(from(z in Zcta, where: z.id == ^zcta.id), set: [area_sqkm: 42.5])
      zcta
    end)
  end

  defp pair!(zcta, district, share) do
    Repo.insert!(%ZctaDistrict{
      zcta_id: zcta.id,
      district_id: district.id,
      overlap_sqkm: 42.5 * share,
      zcta_share: share
    })
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
