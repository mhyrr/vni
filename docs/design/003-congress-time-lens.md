# Congress time lens

**Status:** accepted implementation contract for TK-009's first historical UI pass (2026-07-18).

## Purpose

Let a reader rewind the Atlas by Congress without replacing the current `/states`
and `/districts` designs with a separate history product. The selected Congress is
a map-history lens: geometry and geometry-derived scores follow it. Facts that do
not yet have historical coverage may remain current, but must say so beside the
fact rather than borrowing the selected Congress by implication.

## Addressing and navigation

Every exact snapshot has a stable, Congress-qualified URL:

- `/congresses/:congress/states`
- `/congresses/:congress/states/:state`
- `/congresses/:congress/districts`
- `/congresses/:congress/districts/:slug`

The existing unqualified routes remain the normal present-day experience. They
resolve the current Congress without redirecting, so today's site does not gain
ceremony merely because history exists.

Historical-capable pages render one shared time rail above their existing hero:

```text
← 118th Congress       119th Congress · 2025–2027 · CURRENT
```

The rail uses a fixed three-column layout so the selected Congress remains
visually centered when either neighbor is absent. Previous and next links preserve
the current surface and its identifier. The selected Congress is also available
as a direct list of supported sessions for accessibility and non-linear travel.

## What rewinds

The first pass rewinds only facts backed by Congress-specific data:

- district boundaries and display shapes;
- the four raw compactness measures;
- compactness composite and national rank, always described as belonging to that
  Congress's cohort;
- state map summaries that can be computed from that Congress's district cohort.

Current-only facts may remain on a historical page when they still provide useful
present-day context. Each such section carries an adjacent label such as
`CURRENT-DAY CONTEXT · NOT REWOUND`. A historical Congress label must never sit
over a current incumbent, margin, lean, population, map authorship, or other fact
without that qualification. Unsupported facts may instead be omitted where the
qualification would add more noise than value.

## Map continuity

A new Congress is not presumed to be a new district plan. Complete per-Congress
snapshots remain the storage and scoring model; the presentation treats unchanged
lines as continuity rather than a redraw.

Continuity is state-specific. The 116th and 117th Congresses used the same plan in
49 states, while North Carolina changed. Authoritative reported redraw lists, not
small TIGER vertex differences, determine whether the UI says `LINES UNCHANGED`.
Geometry comparison remains evidence and may support the display, but it does not
classify a legal redistricting by itself.

The first navigation pass does not need a side-by-side comparison. When comparison
ships, it compares a selected plan with the preceding actual redistricting, not
blindly with the preceding Congress.

## Edge cases

- A seat may appear or disappear after reapportionment. A Congress-qualified
  district URL may therefore have no counterpart in its neighbor; navigation must
  fall back to the selected state's district index rather than invent continuity.
- At-large districts remain unranked in every cohort. The 114th–117th each have
  428 ranked districts; the 118th and 119th each have 429.
- Composite scores and ranks are cohort-local. A rank change across Congresses is
  context, not a direct measurement of how much the shape changed.
- Historical authorship is not yet curated. Historical pages do not present a
  current authorship fact as though it belonged to the selected map.

## First release surface

Ship the 114th–119th time rail and Congress-qualified routes across district and
state list and detail pages. Preserve each page's current visual hierarchy. The `/atlas` map may
adopt the same route context when its geographic interface is implemented; the
placeholder is not a reason to fabricate historical behavior now.
