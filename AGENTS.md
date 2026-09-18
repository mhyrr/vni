# VNI — Vote No Incumbents

The public case against incumbency entrenchment: an Atlas of every
congressional district with its shape scored by open methodology, the
incumbent's tenure and margin beside it, and a per-district count of voters
committed to voting the incumbent out. One Phoenix application: Elixir 1.19,
Phoenix 1.8, LiveView 1.1, PostgreSQL 17 with PostGIS, deployed on Fly.

| Read this | For |
|---|---|
| `README.md` | The four demands, and why compactness is never shown without authorship and partisan context |
| `docs/design/001-design-pass-1.md` | The build spec: doctrine, data model, sources, phases |
| `docs/design/002-interface-pass-1.md` | The surface: the user journey, visual and copy direction |
| `docs/design/003-congress-time-lens.md` | Historical congresses: what follows the selected Congress, and what must say it is current |
| `docs/design/004-voter-commitment.md` | The commitment: schema, goal and target rules, what is deferred |
| `docs/data-sources.md` | The registry of every ingested dataset, rendered at `/sources` |
| `docs/deployment/fly.md` | Production: promoting derived data, deploy, recovery |

## Load-bearing subsystems (handle inline, never delegate)

- **Map versioning** (`VNI.Atlas`). Districts are addressed through map
  versions; current = `effective_until IS NULL`. Never make a district slug
  globally unique or query districts without a map-version constraint —
  mid-decade redistricting breaks that instantly. Slugs are unique per
  `map_version_id`, and a pledge is to a seat under one map.
- **Scoring methodology** (`VNI.Scores`). The site's credibility rests on
  reproducible open methodology. Measurement rules are documented in the
  moduledoc and are not negotiable: geography casts for area/perimeter,
  EPSG:5070 for constructions, never raw 4326 degrees. Any formula change
  bumps `@methodology_version`.

## Doctrine constraints on code and copy

Exclusively anti-entrenchment: incumbency, gerrymandering, term limits. No
position on anything the parties fight about. SCOTUS carve-out (no term
limits there). No challenger info on district pages — any challenger will
do; the purity is the point. Published facts only in `VNI.Politics`. Never
use Cook PVI (licensed); lean comes from our formula over public data
(`VNI.Politics.partisan_lean/2`). All ingested data must come from
government or non-partisan sources, cited with a source URL. The registry is
`docs/data-sources.md`, changed in the same commit as any new or changed
ingest; `VNIWeb.SourcesLive` parses it at compile time, so its table and
Notes formats are part of the build.

## Where things live

```text
lib/vni/atlas.ex                   districts and map versions; slug lookups resolve against current maps
lib/vni/atlas/census.ex            supported_congresses/0 and TIGER seeding
lib/vni/atlas/map_authorship.ex    hand-curated authorship rows, one cited source each
lib/vni/atlas/postal.ex            ZIP to district, computed from ZCTA geometry
lib/vni/scores.ex                  compactness: Elixir orchestrating PostGIS SQL
lib/vni/politics.ex                published facts: incumbents, margins, lean, state history
lib/vni/pledges.ex                 voter commitments; every public count starts from `live/0`
lib/vni/promotion.ex               derived rows production cannot recompute, loaded at release
lib/mix/tasks/                     mix vni.*: ingest, score, export, cards
lib/vni_web/district_presenter.ex  the maps public LiveViews consume (state_presenter.ex for /states)
lib/vni_web/congress_time.ex       Congress-qualified routes; unqualified means current
lib/vni_web/share_card.ex          the words on every shareable artifact
```

## Commands

```sh
mix precommit          # compile, deps.unlock --unused, format, test
mix ecto.reset         # seeds: TIGER for every supported congress, authorship, each cohort scored
VNI_SKIP_DISTRICT_SEEDS=1 mix ecto.reset   # schema only, no downloads
mix vni.ingest.shapefiles --congress N     # historical congresses land closed; then mix vni.score --congress N
mix vni.ingest.zctas   # not in mix setup; /find answers nothing without it
mix vni.ingest.zctas --crosswalk-only      # after any district ingest: pairs are true of one map only
mix vni.promote.export # writes priv/promotion; commit it after any ingest that moves districts, margins, or the crosswalk
mix vni.og.cards       # writes priv/static/images/og/; commit the PNGs, rerun after geometry, incumbent, or margin changes
```

`mix precommit` before calling anything done. Its alias spells
`--warning-as-errors`, which Mix ignores, so a compile warning passes it
until TK-028 lands; read the compile output.

Ingest, scoring, and card rendering are dev-side only (GDAL's `ogr2ogr`,
`rsvg-convert`, the Census API, manually fetched MEDSL files). Production
gets bulk data by logical dump and restore, and derived rows only from what
is committed under `priv/promotion` and `priv/static/images/og/`; the Docker
build cannot reach a database. `mix vni.og.cards` refuses to run unless
fontconfig resolves Arial Black, because a substituted font bakes silently
wrong images.

## Conventions

- The user runs the dev server; never start `mix phx.server`. When it is
  up, Tidewave's MCP tools (`project_eval`, `execute_sql_query`,
  `get_docs`, `get_source_location`) evaluate code and query `vni_dev`.
- Postgres is the shared Docker PostGIS in `~/work/infra`
  (`docker compose up -d`). Its volume holds every project's dev databases:
  never remove it. Leave the brew Postgres services stopped; they split
  port 5432.
- Ingest tasks are rerunnable and idempotent (upserts keyed on natural
  identity).
- Compactness scoring is Elixir orchestrating SQL — keep the math in
  PostGIS, the orchestration thin.
- Hand-curated data (map authorship) lives in `VNI.Atlas.MapAuthorship`
  with a source URL per row, applied by `priv/repo/seeds.exs`. A mid-decade
  redraw gets a new row on its new map version, never an edit.
- Public LiveViews consume `VNIWeb.DistrictPresenter` (and
  `VNIWeb.StatePresenter`) maps, never raw structs — geometry stays out of
  the socket.
- The Docker build compiles `lib/` after copying `docs/` and before
  `assets/`: nothing may read `assets/` at compile time.
- Use `:req` (`Req`) for HTTP; avoid `:httpoison`, `:tesla`, `:httpc`.
- Incidents and gotchas go to HIVE memory (project `vni`), not this file.
