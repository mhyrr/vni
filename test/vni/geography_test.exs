defmodule VNI.Atlas.GeographyTest do
  use VNI.DataCase, async: true

  alias VNI.Atlas
  alias VNI.Atlas.Geography
  alias VNI.Politics

  setup do
    {:ok, tx} =
      Atlas.create_map_version(%{
        state: "TX",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03]
      })

    {:ok, district} = Atlas.upsert_district(tx, %{state: "TX", number: 33})

    {:ok, wy} =
      Atlas.create_map_version(%{
        state: "WY",
        level: :congressional,
        congress: 119,
        effective_from: ~D[2025-01-03]
      })

    {:ok, at_large} = Atlas.upsert_district(wy, %{state: "WY", number: 0})

    %{district: district, at_large: at_large}
  end

  @bom <<0xEF, 0xBB, 0xBF>>

  # Raw relationship-file shape: pipe-delimited, BOM on the header,
  # block-aligned areas (whole containment = exact equality).
  defp county_rel do
    @bom <>
      """
      OID_CD119_20|GEOID_CD119_20|NAMELSAD_CD119_20|AREALAND_CD119_20|AREAWATER_CD119_20|MTFCC_CD119_20|FUNCSTAT_CD119_20|OID_COUNTY_20|GEOID_COUNTY_20|NAMELSAD_COUNTY_20|AREALAND_COUNTY_20|AREAWATER_COUNTY_20|MTFCC_COUNTY_20|CLASSFP_COUNTY_20|FUNCSTAT_COUNTY_20|AREALAND_PART|AREAWATER_PART
      1|4833|Congressional District 33|500|10|G5200|N|2|48113|Dallas County|2000|50|G4020|H1|A|300|5
      1|4833|Congressional District 33|500|10|G5200|N|3|48439|Tarrant County|2000|50|G4020|H1|A|200|5
      1|4833|Congressional District 33|500|10|G5200|N|4|48999|Watery County|2000|50|G4020|H1|A|0|5
      5|5600|Congressional District (at Large)|9000|10|G5200|N|6|56025|Natrona County|900|50|G4020|H1|A|900|5
      7|1198|Delegate District (at Large)|100|10|G5200|N|8|11001|District of Columbia|100|50|G4020|H1|A|100|5
      9|4805|Congressional District 5|100|10|G5200|N|10|48001|Anderson County|100|50|G4020|H1|A|100|5
      """
  end

  defp place_rel do
    @bom <>
      """
      OID_CD119_20|GEOID_CD119_20|NAMELSAD_CD119_20|AREALAND_CD119_20|AREAWATER_CD119_20|MTFCC_CD119_20|FUNCSTAT_CD119_20|OID_PLACE_20|GEOID_PLACE_20|NAMELSAD_PLACE_20|AREALAND_PLACE_20|AREAWATER_PLACE_20|MTFCC_PLACE_20|CLASSFP_PLACE_20|FUNCSTAT_PLACE_20|AREALAND_PART|AREAWATER_PART
      1|4833|Congressional District 33|500|10|G5200|N|||||||||100|5
      1|4833|Congressional District 33|500|10|G5200|N|2|4819000|Dallas city|1000|50|G4110|C1|A|250|5
      1|4833|Congressional District 33|500|10|G5200|N|3|4827000|Fort Worth city|1000|50|G4110|C1|A|100|5
      1|4833|Congressional District 33|500|10|G5200|N|4|4831928|Hamlet CDP|100|0|G4210|U1|A|100|0
      5|5600|Congressional District (at Large)|9000|10|G5200|N|6|5613150|Casper city|700|50|G4110|C1|A|700|5
      """
  end

  # Dallas is split (250 of 1000 land): apportioned 325k beats whole tiny
  # Hamlet (9k) and Fort Worth's sliver (10% of 950k = 95k).
  defp place_populations do
    %{"4819000" => 1_300_000, "4827000" => 950_000, "4831928" => 9_000, "5613150" => 58_000}
  end

  test "upserts ordered counties and population-ranked places", ctx do
    summary =
      Geography.ingest!(
        county_rel: county_rel(),
        place_rel: place_rel(),
        place_populations: place_populations()
      )

    assert summary.ingested == 2
    assert summary.skipped == 1
    assert summary.missing_districts == ["tx-5"]

    profile = Politics.get_profile(ctx.district.id)

    # Largest in-district footprint first; the water-only overlap is out.
    assert profile.counties == [
             %{"name" => "Dallas County", "partial" => true},
             %{"name" => "Tarrant County", "partial" => true}
           ]

    # Ranked by apportioned population; LSAD suffixes stripped; the
    # unassigned-remainder row (empty place) is ignored.
    assert profile.places == [
             %{"name" => "Dallas", "partial" => true},
             %{"name" => "Fort Worth", "partial" => true},
             %{"name" => "Hamlet", "partial" => false}
           ]

    assert profile.geography_source_url == Geography.source_url()

    at_large = Politics.get_profile(ctx.at_large.id)
    assert at_large.counties == [%{"name" => "Natrona County", "partial" => false}]
    assert at_large.places == [%{"name" => "Casper", "partial" => false}]
  end

  test "rerun refreshes in place and preserves other domains", ctx do
    {:ok, _} = Politics.upsert_profile(ctx.district, %{incumbent_name: "Marc A. Veasey"})

    opts = [
      county_rel: county_rel(),
      place_rel: place_rel(),
      place_populations: place_populations()
    ]

    %{ingested: 2} = Geography.ingest!(opts)
    %{ingested: 2} = Geography.ingest!(opts)

    profile = Politics.get_profile(ctx.district.id)
    assert [%{"name" => "Dallas County"} | _rest] = profile.counties
    assert profile.incumbent_name == "Marc A. Veasey"
  end
end
