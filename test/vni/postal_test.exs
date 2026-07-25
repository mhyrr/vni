defmodule VNI.PostalTest do
  use VNI.DataCase, async: false

  alias VNI.Atlas
  alias VNI.Atlas.Postal

  describe "normalize/1" do
    test "takes five digits, and the first five of a ZIP+4" do
      assert Postal.normalize("43604") == {:ok, "43604"}
      assert Postal.normalize("43604-1234") == {:ok, "43604"}
      assert Postal.normalize("436041234") == {:ok, "43604"}
      assert Postal.normalize("  43604  ") == {:ok, "43604"}
      assert Postal.normalize("436 04") == {:ok, "43604"}
    end

    test "keeps leading zeros — an integer parse would eat Massachusetts" do
      assert Postal.normalize("02134") == {:ok, "02134"}
    end

    test "refuses anything that is not a ZIP" do
      assert Postal.normalize("4360") == :error
      assert Postal.normalize("436045") == :error
      assert Postal.normalize("ohio!") == :error
      assert Postal.normalize("43604-12") == :error
      assert Postal.normalize("") == :error
      assert Postal.normalize(nil) == :error
    end
  end

  describe "the crosswalk" do
    setup do
      # Two districts sharing the meridian at -76, each a one-degree box,
      # both drawn under the one map Maryland has.
      map_version = map_version!("MD")
      west = district!(map_version, 3, box(-77.0, 39.0, -76.0, 40.0))
      east = district!(map_version, 4, box(-76.0, 39.0, -75.0, 40.0))

      # Wholly inside the western district.
      inside = zcta!("20001", box(-76.8, 39.2, -76.6, 39.4))

      # Straddles the line, roughly half in each.
      straddle = zcta!("20002", box(-76.5, 39.2, -75.5, 39.8))

      # Crosses the line by 0.001° — about 86 metres of a 43-kilometre box.
      # Real geometry, genuinely intersecting, and not a district anyone
      # in that ZIP lives in.
      sliver = zcta!("20003", box(-76.001, 39.2, -75.5, 39.8))

      :ok = Postal.refresh_areas!()
      Postal.rebuild_crosswalk!()

      %{west: west, east: east, inside: inside, straddle: straddle, sliver: sliver}
    end

    test "a ZCTA inside one district resolves to that district alone", %{west: west} do
      assert {:ok, [match]} = Postal.resolve("20001")
      assert match.district.id == west.id

      # Wholly covered: the share is exactly one, with no construction
      # error to round away.
      assert_in_delta match.zcta_share, 1.0, 0.0001
    end

    test "a split ZCTA returns both, largest overlap first", %{west: west, east: east} do
      assert {:ok, [first, second]} = Postal.resolve("20002")

      assert first.zcta_share >= second.zcta_share
      assert Enum.sort([first.district.id, second.district.id]) == Enum.sort([west.id, east.id])

      # Halves of one box: neither side may claim it.
      assert_in_delta first.zcta_share, 0.5, 0.02
      assert_in_delta second.zcta_share, 0.5, 0.02

      # The parts account for the whole — no area invented, none lost.
      assert_in_delta first.zcta_share + second.zcta_share, 1.0, 0.0001
    end

    test "a boundary sliver is not a district you live in", %{east: east} do
      assert {:ok, matches} = Postal.resolve("20003")

      assert [%{district: %{id: id}}] = matches
      assert id == east.id
    end

    test "the sliver rule is a published number, not a hidden one", %{sliver: sliver} do
      # Drop the floor and the same geometry yields the extra pair, which
      # is what the floor is there to exclude.
      Postal.rebuild_crosswalk!(minimum_share: 0.0)

      matches =
        from(zd in VNI.Atlas.ZctaDistrict, where: zd.zcta_id == ^sliver.id)
        |> Repo.all()

      assert length(matches) == 2
      assert Enum.any?(matches, &(&1.zcta_share < Postal.minimum_share()))
    end

    test "an unknown ZIP is not a crash" do
      assert Postal.resolve("99999") == {:error, :unknown}
    end

    test "a real ZCTA with no voting district says so rather than reporting nothing" do
      # An area far from any district we loaded — DC and the territories
      # look like this: real ground, no seat that votes on final passage.
      zcta!("00901", box(-66.2, 18.4, -66.0, 18.5))
      :ok = Postal.refresh_areas!()
      Postal.rebuild_crosswalk!()

      assert Postal.resolve("00901") == {:error, :no_district}
    end

    test "malformed input never reaches the database" do
      assert Postal.resolve("nope") == {:error, :malformed}
    end
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

  defp district!(map_version, number, geom) do
    {:ok, district} =
      Atlas.upsert_district(map_version, %{
        state: map_version.state,
        number: number,
        geom: geom
      })

    district
  end

  defp zcta!(code, geom) do
    %VNI.Atlas.Zcta{}
    |> VNI.Atlas.Zcta.changeset(%{
      zcta5: code,
      geom: geom,
      vintage: 2025,
      source_url: VNI.Atlas.Postal.source_url()
    })
    |> Repo.insert!()
  end

  defp box(west, south, east, north) do
    %Geo.MultiPolygon{
      coordinates: [
        [
          [
            {west, south},
            {east, south},
            {east, north},
            {west, north},
            {west, south}
          ]
        ]
      ],
      srid: 4326
    }
  end
end
