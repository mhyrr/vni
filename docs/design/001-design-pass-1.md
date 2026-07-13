# Vote No Incumbents — Design Pass 1

**Status:** accepted as the build spec for Phases 1–2 (2026-07-12). UI design deliberately deferred to a separate discussion.

**Working name:** VNI. **Stack:** Phoenix / LiveView, PostgreSQL + PostGIS, Oban, Swoosh. Single Elixir app, single Postgres database, boring on purpose.

---

## 0. Origin notes (first pass, full history)

Honest history: anti-incumbency is evergreen and always breaks on Fenno's paradox (hate Congress, love your guy). The novel mechanism: an assurance contract — "my pledge to vote out my incumbent activates only when N% of pledges in other districts activate" — Kickstarter for electoral housecleaning, solving the unilateral-defection problem.

Doctrine: exclusively anti-entrenchment (incumbency, gerrymandering, term limits); no position on anything the parties fight about, including how votes are cast; the SCOTUS carve-out strengthens credibility.

Cautions: congressional term limits require a constitutional amendment; this is a movement needing a face, and think hard before becoming a political brand.

The Greg-shaped crawl step: the gerrymander compactness scorer — score all 435 districts on shape metrics from public shapefiles, publish ranked with open methodology. Nonpartisan by construction; builds the data spine before any platform exists.

Why Phoenix: if this succeeds it gets bigger, and nobody wants to inherit a TypeScript mess. Shapefiles live in Postgres with a really good cage around them. The main page is long-form marketing — the case for voting no incumbents, keyed on red cities and blue country. Surveys let people describe their district at local/state/federal levels; aggregation powers the collective-action mechanism and activation emails.

### Doctrine (canonical)

- **No Incumbents.** Vote everyone out. R and D.
- **No gerrymanders**, as measured by shapes, with open methodology.
- **Term limits.**
- **Leave the Supreme Court be.** No term limits there — independence is paramount, and the carve-out is what makes the rest credible.

---

## 1. Shape of the thing

Three layers, built in order, each independently valuable:

1. **The Atlas (crawl).** All 435 districts in PostGIS, scored on compactness with open methodology, each with a district page showing shape, score, incumbent, partisan lean, who drew the map, and when it redraws. Zero accounts, zero politics beyond published facts. This is the data spine and it stands alone as a credible artifact.
2. **The Pledge (walk).** The assurance contract: "my pledge activates when the threshold is met elsewhere." Email-verified pledges, a public activation dashboard, and outreach when thresholds trip.
3. **The Voice (run).** Surveys at local/state/federal levels, aggregation, the long-form landing narrative (red cities, blue country), essays.

The key architectural consequence: the Atlas must be _versioned by map_, not just by district. Mid-decade redistricting is live right now (Texas redrew in 2025, other states responded), so "TX-33" is not a stable identifier — "TX-33 under the map effective for the 120th Congress" is. Bake this in from migration one or you'll be untangling it later.

---

## 2. Data model

### Contexts

```
VNI.Atlas           districts, geometries, map versions, ingestion
VNI.Scores          compactness metrics, composite score, rankings
VNI.Politics        incumbents, partisan lean, map authorship, redraw timeline
VNI.Reapportionment 2030 census projections, Huntington-Hill
VNI.Pledges         assurance contract state machine        (Phase 3)
VNI.Surveys         district-experience submissions         (Phase 4)
VNI.Outreach        email confirmation + activation broadcasts (Phase 3)
```

Core schemas as built: see `lib/vni/atlas/map_version.ex`, `lib/vni/atlas/district.ex`, `lib/vni/scores/district_score.ex`, `lib/vni/politics/district_profile.ex`. Canonical geometry is `geometry(MultiPolygon, 4326)`; measurement happens in geography casts or EPSG:5070 (CONUS Albers) — never raw 4326 degrees. Simplest consistent rule: `ST_Area(geom::geography)` and `ST_Perimeter(geom::geography)` everywhere; constructions with no geography version (minimum bounding circle, convex hull) run in 5070.

### Compactness in SQL

The whole scorer is Elixir orchestrating a handful of SQL statements (`VNI.Scores`). Metrics: Polsby-Popper (4πA/P²), Reock (area / minimum bounding circle), convex hull ratio, Schwartzberg (circle-equivalent perimeter ratio, expressed in [0,1]). Composite = mean of the four after min-max normalization across the current map set. Rank with a window function.

**Honesty requirement for the methodology page:** compactness is a _shape_ metric, not a _gerrymander_ metric. Some ugly districts are VRA majority-minority districts drawn under court order; some perfectly compact maps are efficient partisan gerrymanders (packing can look tidy). Publish the scores as what they are — "the 435 districts ranked by geometric compactness, with authorship and partisan context alongside" — and let the juxtaposition do the work. Later, add efficiency gap and mean-median difference from election results as separate columns. Saying this out loud on the methodology page is what makes the site credible rather than a gotcha machine.

---

## 3. Data sources & ingestion

All public, all free, all scriptable:

| Data | Source | Format |
|---|---|---|
| District geometries | Census TIGER/Line (CD119) | Shapefile, public domain |
| Incumbents, tenure, bioguide | `unitedstates/congress-legislators` (GitHub) | YAML, public domain |
| Election results by district | MIT Election Data + Science Lab | CSV |
| Presidential results by CD (for lean) | Daily Kos Elections / published datasets | CSV — verify redistribution terms |
| Map authorship & litigation status | Loyola "All About Redistricting", NCSL | Manual curation, ~50 rows |
| State population estimates (for 2030) | Census Bureau annual estimates | CSV |

Note on partisan lean: don't use Cook PVI verbatim — it's their branded, licensed product. Compute our own lean from public presidential-results-by-CD data with a published formula (weighted two-cycle average vs. national margin, `VNI.Politics.partisan_lean/2`). Same information, clean provenance, fits the open-methodology posture.

Ingestion pipeline as mix tasks (rerunnable, idempotent):

```
mix vni.ingest.shapefiles --congress 119   # downloads TIGER, ogr2ogr → PostGIS
mix vni.ingest.legislators                 # pulls YAML, upserts profiles
mix vni.ingest.results --cycle 2024
mix vni.score                              # computes metrics + national ranks
```

Use `ogr2ogr` (or `shp2pgsql`) shelled out via `System.cmd` into a staging table, then Ecto-managed promotion into `districts`. Pre-compute `geom_simplified` at ingest with `ST_SimplifyPreserveTopology(geom, 0.005)` — district pages serve that as GeoJSON directly, no tile server needed at this scale. 435 simplified polygons is nothing; MapLibre GL JS via a LiveView hook renders it happily. National overview map can use a single pre-baked simplified GeoJSON file cached at the edge.

Authorship data (who drew each map, commission vs. legislature, court status) is ~50 states × a few fields — curate it by hand in a seeds file with source URLs per row. Hand-curation with citations is a feature here, not a shortcut.

---

## 4. The 2030 module

Pure math: Huntington-Hill (method of equal proportions, `VNI.Reapportionment`) against Census annual state population estimates; publish projected seat gains/losses for post-2030 reapportionment. Page shows: projected apportionment, seats gained/lost by state, which states' gains land in legislatures vs. commissions (i.e., where the next gerrymanders will be drawn), and countdown framing to the 2031 redraw. Ties the whole "when will this change" question to something concrete, and it updates annually when new estimates drop — recurring content for free.

---

## 5. The assurance contract (Phase 3 — not yet built)

The mechanism design matters more than the code. Sketch:

```
pledges:          email (citext, unique per email+district+level), confirmed_at
                  (double opt-in or it doesn't count), district_id, level,
                  status (unconfirmed | standing | activated | withdrawn),
                  token (magic-link management, no accounts)
activation_rules: name ("National 2026"), min_districts, pledges_per_district,
                  evaluated_at, tripped_at
```

Design decisions to make deliberately, not by default:

- **Denominator problem.** "N% of pledges in other districts" — percent of _what_? Registered voters per district invites endless disputes about the base. Recommendation: absolute thresholds — _the contract trips when ≥ K districts each hold ≥ X confirmed pledges_. Legible, auditable, and the public dashboard becomes a Kickstarter-style progress bar per district. That dashboard is itself the growth mechanic.
- **No accounts.** Email + magic link token. Confirm, view status, withdraw. Anything heavier kills conversion and creates a PII liability nobody wants.
- **Evaluation.** Nightly Oban job checks rules, transitions pledges to `:activated`, enqueues the broadcast email. All transitions logged in an events table — the credibility of an assurance contract rests on the trigger being verifiable, so publish the evaluation code and the (anonymized, per-district) counts.
- **Compliance.** CAN-SPAM basics (physical address, unsubscribe); emailing people about voting behavior is near the edges of state-level political communication rules. Pledge lists are politically sensitive PII — encrypt at rest, minimal retention, never sell/share, say so loudly.
- **Fraud posture v1:** double opt-in + one pledge per email per district + disposable-domain blocklist. Don't over-engineer; the dashboard being directionally honest is enough at crawl scale.

Surveys are the same pattern with a free-text payload: district, level, "what would it take for you to vote out your incumbent," structured enough to aggregate. Store raw, aggregate later — schema humility about what you'll want to slice.

---

## 6. Pages & routes

```
/                    Long-form landing (the essay-as-homepage)
/districts           Ranked table: sortable by composite, lean, tenure, authority
/d/:slug             District page (tx-33): map, scores, incumbent, authorship, redraw date
/methodology         The open-methodology page. Load-bearing for credibility.
/2030                Reapportionment projections
/pledge              The contract: explain, pledge, dashboard        (Phase 3)
/p/:token            Manage my pledge                                (Phase 3)
/dashboard           Public activation progress                      (Phase 3)
/admin               LiveDashboard + Oban Web, auth'd
```

**Landing page.** Long-form marketing, closer to an essay than a SaaS splash. The red-cities/blue-country thread gives it a visual grammar too — the district table can carry it (lean color vs. compactness score creates the "both parties do this" pattern at a glance, which _is_ the nonpartisan-by-construction argument, shown not told). Structure: the Fenno's paradox hook ("you hate Congress; you'll re-elect your guy; here's why that's not a contradiction you have to live with") → the entrenchment doctrine → the mechanism → the data → the pledge. The Atlas is the proof-of-seriousness that makes the essay land.

**District page anatomy** (the shareable unit — design for the screenshot):

- Map, shaded by party, simplified outline
- Composite score + rank ("387th of 435") with the four metrics expandable
- Incumbent, party, tenure ("in office since 2003"), last margin
- Map provenance: drawn by [authority], controlled by [party], effective [date], litigation status, next scheduled redraw
- Partisan lean with our formula linked
- Later: the pledge CTA and per-district pledge count

---

## 7. Build order

**Phase 1 — Atlas (the crawl).** Ingestion pipeline, scoring engine, district pages, ranked index, methodology page. No email, no accounts, no pledge. Ship this and it's already a citable artifact — "the site that ranks all 435 districts by compactness with open methodology" is linkable by anyone across the spectrum precisely because it asks nothing of them.

**Phase 2 — 2030 module + landing essay.** Huntington-Hill projections, the long-form homepage. Still zero user data.

**Phase 3 — Pledge.** Assurance contract, dashboard, Outreach context, compliance pass. This is where the founder-face question becomes real — Phases 1–2 can live pseudonymously as a data project; Phase 3 is asking people for commitments and someone has to sign it. The architecture doesn't force the decision, but the phase boundary is where the decision lives.

**Phase 4 — Surveys + state/local.** The `level` enum and `map_versions.level` field are already in the schema, so extension is additive; state legislative shapefiles are also on TIGER when ready.

---

## 8. Open questions to settle before building further

1. Threshold constants for the contract (K districts × X pledges) — pick something achievable enough that the dashboard shows motion.
2. Domain/name — VNI is placeholder; the name is doing marketing work on a project whose homepage is an essay.
3. Whether the scoring code itself goes on GitHub day one (recommend yes — "open methodology" with closed code is half a claim).
4. Entity question — for Phases 1–2, nothing; before Phase 3, whether this wants a 501(c)(4) wrapper is a real conversation.
5. Whether district pages include _challenger_ info eventually — doctrinally pure anti-entrenchment says no (any challenger will do), and that purity is worth protecting.
