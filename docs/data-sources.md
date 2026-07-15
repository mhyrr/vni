# Data sources

The registry of record for every dataset VNI ingests. Doctrine: all
ingested data comes from government or non-partisan sources, cited with a
source URL on every row it feeds; the one exception is noted inline and
carries its own justification. Update this file in the same commit as any
new or changed ingest. A public `/sources` page will render this list
(TK-014).

| Source | Feeds | Publisher | License / terms |
|---|---|---|---|
| [Census TIGER/Line 2025, CD119](https://www2.census.gov/geo/tiger/TIGER2025/CD/) | District geometry, land area, perimeter | U.S. Census Bureau | Public domain |
| [unitedstates/congress-legislators](https://unitedstates.github.io/congress-legislators/legislators-current.yaml) | Incumbent name, party, first House year, bioguide id | community-maintained from official sources | Public domain (CC0) |
| [Census ACS 5-year API](https://api.census.gov/data/2024/acs/acs5) | District population, voting-age population; place populations (ranking input only) | U.S. Census Bureau | Public domain; free API key required |
| [MEDSL U.S. House 1976–2024](https://doi.org/10.7910/DVN/IG0UN2) | Last general-election margin, cycle, winner party | MIT Election Data + Science Lab | CC0; Dataverse guestbook on download (see below) |
| [MEDSL U.S. President 1976–2024](https://doi.org/10.7910/DVN/42MVDX) | National two-party presidential shares (lean normalization) | MIT Election Data + Science Lab | CC0; Dataverse guestbook on download |
| [The Downballot pres-by-CD, 2024 lines](https://docs.google.com/spreadsheets/d/1ng1i_Dm_RMDnEvauH44pgE6JCUsapcuu8F2pCfeLWFo) | District two-party presidential shares (lean input) | The Downballot (formerly Daily Kos Elections) | Reuse permitted with citation and link; no wholesale reproduction |
| [Loyola, All About Redistricting](https://redistricting.lls.edu/) | Map authorship: authority + controlling party per state (hand-curated, one state page cited per row) | Loyola Law School | Reference site; cited per row |
| [Census CD119 relationship files](https://www2.census.gov/geo/docs/maps-data/data/rel2020/cd-sld/) | Counties and places per district | U.S. Census Bureau | Public domain |

## Notes

**MEDSL guestbook.** The Harvard Dataverse gates MEDSL downloads behind a
guestbook (name/email/institution — their usage-tracking mechanism; the
data itself is CC0). There is no API bypass, so those two files are
fetched manually once through a browser and cached under
`priv/repo/data/medsl/` (gitignored). Fetch instructions live in the
`VNI.Politics.Results` moduledoc. Despite the dataset's `.tab` display
name, the House file's original format is comma-separated.

**The Downballot exception.** MEDSL publishes no president-by-CD product,
and no government source aggregates presidential results to district
lines. The Downballot's dataset is arithmetic on official returns,
published on the district lines used in 2024 (our CD119 set), and is the
standard reference for this quantity — but its publisher is a partisan
outlet, which sits in tension with the sourcing doctrine above. The
ingest is source-pluggable: if a strictly non-partisan chain matters
more than provenance convenience, swap in a Redistricting Data Hub /
VEST precinct aggregation and update this row.

**Never used.** Cook PVI (licensed; partisan lean is our own published
formula — see `/methodology`). Any dataset that would put challenger
information into the system.

**Local caches.** `priv/repo/data/tiger/` (TIGER archives),
`priv/repo/data/medsl/`, `priv/repo/data/downballot/`,
`priv/repo/data/census-rel/` — all gitignored; every cache's URL and
expected contents are pinned in the owning module.
