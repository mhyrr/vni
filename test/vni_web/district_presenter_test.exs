defmodule VNIWeb.DistrictPresenterTest do
  use ExUnit.Case, async: true

  alias VNI.Atlas.{District, MapVersion}
  alias VNI.Politics.DistrictProfile
  alias VNI.Scores.DistrictScore
  alias VNIWeb.DistrictPresenter

  test "presents sourced score data and converts geometry to a fitted SVG path" do
    district = %District{
      id: 1,
      state: "MD",
      number: 3,
      slug: "md-3",
      land_area_sqkm: 251_458.2,
      perimeter_km: 2_412.8,
      geom_simplified: %Geo.MultiPolygon{
        coordinates: [[[{0.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]]],
        srid: 4326
      },
      map_version: %MapVersion{
        congress: 119,
        source_url: "https://example.test/wy.zip"
      },
      score: %DistrictScore{
        composite: 0.232,
        polsby_popper: 0.4,
        reock: 0.5,
        convex_hull: 0.6,
        schwartzberg: 0.7,
        national_rank: 400,
        methodology_version: "2026.1"
      }
    }

    presented = DistrictPresenter.present(district, 429)

    assert presented.label == "MD-03"
    assert presented.state == "Maryland"
    refute presented.at_large
    assert presented.composite == 23
    assert presented.national_rank == 400
    assert presented.ranked_total == 429
    assert presented.land_area == "251,458"
    assert presented.tone == :red
    assert presented.shape_path =~ ~r/^M\d+\.\d{2} \d+\.\d{2}L/
    assert String.ends_with?(presented.shape_path, "Z")
  end

  test "presents an at-large district with no composite, rank, or tone band" do
    district = %District{
      id: 2,
      state: "WY",
      number: 0,
      slug: "wy-0",
      land_area_sqkm: 251_458.2,
      perimeter_km: 2_412.8,
      geom_simplified: %Geo.MultiPolygon{
        coordinates: [[[{0.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {0.0, 1.0}, {0.0, 0.0}]]],
        srid: 4326
      },
      map_version: %MapVersion{
        congress: 119,
        source_url: "https://example.test/wy.zip"
      },
      score: %DistrictScore{
        composite: nil,
        polsby_popper: 0.4,
        reock: 0.5,
        convex_hull: 0.6,
        schwartzberg: 0.7,
        national_rank: nil,
        methodology_version: "2026.2"
      }
    }

    presented = DistrictPresenter.present(district, 429)

    assert presented.label == "WY-AL"
    assert presented.at_large
    assert is_nil(presented.composite)
    assert is_nil(presented.national_rank)
    assert presented.ranked_total == 429
    assert presented.tone == :neutral
    assert presented.polsby_popper == 40

    # Profile not loaded → every profile fact is nil, never NotLoaded leakage.
    assert is_nil(presented.incumbent_name)
    assert is_nil(presented.population)
  end

  test "presents ingested profile facts with raw party letter and arithmetic tenure" do
    district = %District{
      id: 3,
      state: "TX",
      number: 33,
      slug: "tx-33",
      map_version: %MapVersion{congress: 119, source_url: "https://example.test/tx.zip"},
      score: %DistrictScore{
        composite: 0.5,
        polsby_popper: 0.5,
        reock: 0.5,
        convex_hull: 0.5,
        schwartzberg: 0.5,
        national_rank: 200,
        methodology_version: "2026.2"
      },
      profile: %DistrictProfile{
        incumbent_name: "Marc A. Veasey",
        incumbent_party: :dem,
        incumbent_since: 2013,
        incumbent_source_url: "https://unitedstates.github.io/congress-legislators/",
        population: 789_013,
        voting_age_population: 560_000,
        acs_vintage: 2024,
        population_source_url: "https://api.census.gov/data/2024/acs/acs5"
      }
    }

    presented = DistrictPresenter.present(district)

    assert presented.incumbent_name == "Marc A. Veasey"
    assert presented.incumbent_party == "D"
    assert presented.incumbent_party_key == :dem
    assert presented.incumbent_since == 2013
    assert presented.incumbent_tenure == Date.utc_today().year - 2013
    assert presented.population == "789,013"
    assert presented.voting_age_population == "560,000"
    assert presented.acs_vintage == 2024
  end
end
