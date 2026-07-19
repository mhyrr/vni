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
    assert presented.tone == :worst
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
      map_version: %MapVersion{
        congress: 119,
        source_url: "https://example.test/tx.zip",
        authority: :legislature,
        controlling_party: :rep,
        authorship_source_url: "https://redistricting.lls.edu/state/texas/"
      },
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
        population_source_url: "https://api.census.gov/data/2024/acs/acs5",
        last_margin_pct: 30.85,
        last_margin_cycle: 2024,
        last_margin_party: :dem,
        margin_source_url: "https://doi.org/10.7910/DVN/IG0UN2",
        partisan_lean: -20.8,
        lean_source_url: "https://docs.google.com/spreadsheets/d/example",
        counties: [
          %{"name" => "Tarrant County", "partial" => true},
          %{"name" => "Dallas County", "partial" => true},
          %{"name" => "Denton County", "partial" => true},
          %{"name" => "Ellis County", "partial" => false},
          %{"name" => "Johnson County", "partial" => false}
        ],
        places: [
          %{"name" => "Fort Worth", "partial" => true},
          %{"name" => "Dallas", "partial" => true}
        ],
        geography_source_url: "https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld"
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

    # Margin: one display decimal, winner party in evidence colors.
    assert presented.last_margin == "30.9"
    assert presented.last_margin_cycle == 2024
    assert presented.last_margin_party == "D"
    assert presented.last_margin_party_key == :dem
    refute presented.unopposed

    # Lean rounds for display with our R+/D+ sign convention.
    assert presented.partisan_lean == "D+21"
    assert presented.partisan_lean_party_key == :dem

    # Lean color grammar: hue = direction, opacity = magnitude on [0.2, 1.0],
    # saturating at ±30 points. D+20.8 → blue at 0.2 + 0.8 × 20.8/30.
    assert presented.lean_tone == :blue
    assert presented.lean_intensity == 0.75

    # Authorship, exactly as curated.
    assert presented.map_authority == "the state legislature"
    assert presented.map_authority_short == "Legislature"
    assert presented.map_controlling_party == "Republicans in control at adoption"
    assert presented.map_controlling_party_short == "R"
    assert presented.authorship_source_url =~ "redistricting.lls.edu"

    # Location lines trim with a counted overflow, never silently.
    assert presented.county_line ==
             "Tarrant County (part) · Dallas County (part) · Denton County (part) · +2 more"

    assert presented.place_line == "Fort Worth (part) · Dallas (part)"
  end

  test "presents an unopposed margin and a nonpartisan authority" do
    district = %District{
      id: 4,
      state: "AK",
      number: 0,
      slug: "ak-0",
      map_version: %MapVersion{
        congress: 119,
        source_url: "https://example.test/ak.zip",
        authorship_source_url: "https://redistricting.lls.edu/state/alaska/"
      },
      score: %DistrictScore{
        composite: nil,
        polsby_popper: 0.5,
        reock: 0.5,
        convex_hull: 0.5,
        schwartzberg: 0.5,
        national_rank: nil,
        methodology_version: "2026.2"
      },
      profile: %DistrictProfile{
        last_margin_pct: 100.0,
        last_margin_cycle: 2024,
        last_margin_party: :rep
      }
    }

    presented = DistrictPresenter.present(district)

    assert presented.unopposed
    assert presented.last_margin == "100.0"
    assert presented.last_margin_party_key == :rep

    # No lean or geography ingested yet — nil, not a crash or a zero.
    assert is_nil(presented.partisan_lean)
    assert presented.lean_tone == :neutral
    assert is_nil(presented.lean_intensity)
    assert is_nil(presented.county_line)

    # At-large: no authority, but the citation still documents the seat.
    assert is_nil(presented.map_authority)
    assert presented.authorship_source_url =~ "alaska"
  end

  describe "summary_line/1" do
    test "leads with the member and the people they represent" do
      assert DistrictPresenter.summary_line(%{
               incumbent_name: "Marc A. Veasey",
               population: "789,013",
               congress: 119
             }) == "Marc A. Veasey represents 789,013 people in the 119th Congress."
    end

    test "names a vacancy rather than dropping the sentence" do
      assert DistrictPresenter.summary_line(%{
               incumbent_name: nil,
               population: "789,013",
               congress: 119
             }) ==
               "This seat is vacant — 789,013 people with no member in the 119th Congress."
    end

    test "a historical cohort has no member or population ingested" do
      assert DistrictPresenter.summary_line(%{
               incumbent_name: nil,
               population: nil,
               at_large: false,
               state: "Texas",
               state_seats: 38,
               congress: 118
             }) == "One of 38 Texas districts in the 118th Congress."

      assert DistrictPresenter.summary_line(%{
               incumbent_name: nil,
               population: nil,
               at_large: true,
               state: "Wyoming",
               state_seats: 1,
               congress: 118
             }) == "Wyoming's at-large district in the 118th Congress."
    end
  end

  describe "state_context/2" do
    # A square-degree district at the west edge of a two-district state.
    defp square(west, east, south, north) do
      %Geo.MultiPolygon{
        coordinates: [
          [[{west, south}, {east, south}, {east, north}, {west, north}, {west, south}]]
        ],
        srid: 4326
      }
    end

    defp box(view_box) do
      view_box |> String.split(" ") |> Enum.map(&String.to_float/1)
    end

    test "projects subject and siblings into one shared frame" do
      subject = square(0.0, 1.0, 0.0, 1.0)
      siblings = [%{slug: "xx-2", geom: square(1.0, 2.0, 0.0, 1.0)}]

      context = DistrictPresenter.state_context(subject, siblings)

      # The frame spans both districts: twice as wide as tall, normalized to 100.
      assert [+0.0, +0.0, width, height] = box(context.view_box)
      assert_in_delta width, 100.0, 0.01
      assert_in_delta height, 50.0, 0.01

      # The subject occupies the western half, so the focus box sits left of centre
      # and is meaningfully smaller than the whole state.
      assert [x, _y, focus_width, _focus_height] = box(context.focus_box)
      assert x < width / 2
      assert focus_width < width / 2 + 10

      assert length(context.sibling_paths) == 1
      assert context.subject_path =~ "M"
      assert context.animate?
    end

    test "corrects longitude for latitude so states are not stretched" do
      # At 60°N, cos(60°) = 0.5: a 2°x1° box is as wide as it is tall on the ground.
      subject = square(0.0, 2.0, 59.5, 60.5)

      context = DistrictPresenter.state_context(subject, [])

      assert [+0.0, +0.0, width, height] = box(context.view_box)
      assert_in_delta width, height, 2.0
    end

    test "at-large districts have no siblings and nothing to zoom out to" do
      context = DistrictPresenter.state_context(square(0.0, 1.0, 0.0, 1.0), [])

      refute context.animate?
      assert context.sibling_paths == []
      assert context.focus_box == context.view_box
    end
  end
end
