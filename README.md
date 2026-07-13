# Vote No Incumbents (VNI)

A political action and data project built on one doctrine: anti-entrenchment.

- **No incumbents.** Vote everyone out. R and D.
- **No gerrymanders**, as measured by shapes, with open methodology.
- **Term limits.**
- **Leave the Supreme Court be.** No term limits there; independence is paramount.

The full design is in [docs/design/001-design-pass-1.md](docs/design/001-design-pass-1.md). Build order: the Atlas (all 435 districts in PostGIS, compactness-scored with open methodology), then the 2030 reapportionment module and the long-form landing essay, then the pledge assurance contract.

## Stack

Phoenix 1.8 / LiveView, PostgreSQL + PostGIS, Oban, Swoosh. Single app, single database, boring on purpose.

## Setup

Requires Elixir 1.15+, PostgreSQL with PostGIS (`brew install postgresql@17 postgis`), and GDAL for shapefile ingestion (`ogr2ogr` ships with the PostGIS formula).

    mix setup            # deps, database, migrations, assets
    mix test
    mix phx.server       # localhost:4000

## Data pipeline

Rerunnable, idempotent mix tasks (ingestion tasks are skeletons until Phase 1 data work lands):

    mix vni.ingest.shapefiles --congress 119   # TIGER/Line → PostGIS
    mix vni.ingest.legislators                 # incumbents, tenure, bioguide ids
    mix vni.ingest.results --cycle 2024        # margins + partisan lean inputs
    mix vni.score                              # compactness metrics + national ranks

## Architecture notes

- **Districts are versioned by map.** "TX-33" is not a stable identifier; "TX-33 under the map effective for the 120th Congress" is. Every district hangs off a `map_version`; the current map is the one with `effective_until = nil`.
- **Measurement rules.** Area/perimeter in geography casts, constructions (bounding circle, convex hull) in EPSG:5070. Never raw 4326 degrees. See `VNI.Scores`.
- **Compactness is a shape metric, not a gerrymander metric.** The methodology page owns that caveat; scores are never presented without authorship and partisan context alongside.
- **Partisan lean is our own published formula** over public presidential-results-by-CD data (`VNI.Politics.partisan_lean/2`) — never Cook PVI.
