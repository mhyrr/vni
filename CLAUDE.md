# VNI — Vote No Incumbents

Phoenix/LiveView + PostGIS political data project. Design spec: `docs/design/001-design-pass-1.md`. Phoenix conventions: `AGENTS.md`.

## Load-bearing subsystems (handle inline, never delegate)

- **Map versioning** (`VNI.Atlas`). Districts are addressed through map versions; current = `effective_until IS NULL`. Never make a district slug globally unique or query districts without a map-version constraint — mid-decade redistricting breaks that instantly.
- **Scoring methodology** (`VNI.Scores`). The site's credibility rests on reproducible open methodology. Measurement rules are documented in the moduledoc and are not negotiable: geography casts for area/perimeter, EPSG:5070 for constructions, never raw 4326 degrees. Any formula change bumps `@methodology_version`.
- **Pledge data (Phase 3, future).** Politically sensitive PII. Double opt-in, encrypt at rest, minimal retention. Treat like money.

## Doctrine constraints on code and copy

Exclusively anti-entrenchment: incumbency, gerrymandering, term limits. No position on anything the parties fight about. SCOTUS carve-out (no term limits there). No challenger info on district pages — any challenger will do; the purity is the point. Published facts only in `VNI.Politics`. Never use Cook PVI (licensed); lean comes from our formula over public data.

## Conventions

- Ingest tasks are rerunnable and idempotent (upserts keyed on natural identity).
- Compactness scoring is Elixir orchestrating SQL — keep the math in PostGIS, the orchestration thin.
- Hand-curated data (map authorship, ~50 rows) lives in seeds with a source URL per row.
- `mix precommit` before claiming done (compile --warnings-as-errors, format, test).
- Local Postgres: `brew services start postgresql@17` (PostGIS lives in the @17 tree).
