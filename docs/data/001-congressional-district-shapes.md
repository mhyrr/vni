# Congressional district shape data

**Status:** implemented for the 114th–119th Congresses (2026-07-19).

## Decision

Use the U.S. Census Bureau's full-resolution TIGER/Line congressional district
shapefiles as the canonical geometry source. Seed complete snapshots for the
114th–119th Congresses, each containing 50 state map versions and exactly 435
voting districts. Do not ingest the District of Columbia or territories into
the 435-district Atlas.

The cartographic boundary files are not valid scoring inputs. Census describes
them as simplified files intended for small-scale thematic mapping; that
generalization changes perimeter and therefore contaminates Polsby-Popper and
Schwartzberg. `geom_simplified` remains our derived display geometry.

Source landing page:

- <https://www.census.gov/programs-surveys/decennial-census/about/rdo/congressional-districts.119th_Congress.html>
- State files: `https://www2.census.gov/geo/tiger/TIGER2025/CD/tl_2025_<FIPS>_cd119.zip`
- Historical national files: `https://www2.census.gov/geo/tiger/TIGER<YEAR>/CD/tl_<YEAR>_us_cd<SESSION>.zip`
- TIGER/Line technical documentation: <https://www2.census.gov/geo/pdfs/maps-data/data/tiger/tgrshp2025/TGRSHP2025_TechDoc.pdf>

The 2025 vintage represents legal boundaries as of January 1, 2025. Census
identifies the layer as the 119th Congressional Districts and reports that
Alabama, Georgia, Louisiana, New York, and North Carolina changed plans from
the 118th Congress.

## Seed contract

`priv/repo/seeds.exs` invokes the idempotent Census importer. The importer:

1. downloads each Congress's national or per-state source ZIPs into an ignored local cache;
2. uses GDAL's `ogr2ogr` to convert each shapefile to newline-delimited GeoJSON;
3. decodes geometry through `Geo.JSON` and upserts one map version per state;
4. upserts districts by `(map_version_id, slug)`;
5. derives simplified geometry, geodesic land area, and geodesic perimeter in
   PostGIS; and
6. refuses to finish unless per-state counts match the apportionment in force
   for that Congress and the national count is exactly 435.

The ZIPs are cache, not source code. The source URLs, vintage, state manifest,
and expected counts live in code; downloading remains repeatable without
putting Census archives into Git. A failed or partial download is never promoted
into the cache.

Runtime prerequisite: GDAL (`ogr2ogr`). It is already installed in the VNI
development environment. Req is the only HTTP client.

## Historical coverage: 2015-present

The natural time slices are congressional sessions, with boundaries effective
on January 3 of the session's first year:

| Congress | Effective | Canonical source | States Census reports as changed |
|---|---|---|---|
| 114th | 2015-01-03 | Census TIGER/Line CD114 | Minnesota |
| 115th | 2017-01-03 | Census TIGER/Line CD115 | Florida, Minnesota, North Carolina, Virginia |
| 116th | 2019-01-03 | Census TIGER/Line CD116 | Colorado, Minnesota, Pennsylvania |
| 117th | 2021-01-03 | CD116 except North Carolina | North Carolina only |
| 118th | 2023-01-03 | Census TIGER/Line CD118 | all states, post-2020 Census |
| 119th | 2025-01-03 | Census TIGER/Line CD119 | Alabama, Georgia, Louisiana, New York, North Carolina |

The 117th is the one seam. Census does not collect the district cycle aligned
with the decennial census and explicitly says North Carolina was the only state
that changed between the 116th and 117th Congresses. Use CD116 for the other 49
states and the North Carolina General Assembly's enacted-2019 shapefile, with
the Redistricting Data Hub copy as a preservation/validation source.

Historical imports should store complete per-Congress snapshots first. Shape
equality and "redrawn since prior Congress" are derived facts, not ingest
assumptions: TIGER vintages can contain harmless coastline and base-geography
corrections even where the legal district plan did not change. Census's
state-reported change lists are the authoritative classification.

## Known caveats

- A district's shape is evidence about compactness, not proof of partisan
  intent. The methodology page owns that distinction.
- TIGER/Line depicts split-block boundaries more accurately than Census block
  equivalency files. Use the geometry, not whole-block assignments, for shape
  scores.
- Current means the 119th Congress (January 2025-January 2027). Plans enacted
  for the 2026 election/120th Congress are future versions and must not replace
  the current Atlas early.
- `effective_from`/`effective_until` describe the congressional session for
  public historical lookup. Enactment dates and litigation events belong in
  separate provenance fields when that pass is built.
