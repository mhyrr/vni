# VNI Design Pass 4 — The Voter Commitment

**Status:** accepted as the build spec (2026-07-24, design walk with Greg).
**Supersedes for Phase 3:** design 001 §5's assurance-contract sketch, in the
narrow sense described in §2 — the schema and the "no accounts, magic link"
posture carry forward; the activation state machine does not ship in v1.

---

## 0. What changed in the walk

TK-020 was written as a **candidate signature ledger** — a public list of
officeholders and candidates who put their name to all four demands. The walk
moved the center of the product:

> It isn't about which politicians sign. It's about the voters. "103 people in
> your district have committed to this. Will you join them?"

That is Fenno's paradox answered at district granularity. Not an argument that
your incumbent is beatable — a **count of neighbors who already said so**.

The candidate ledger is deferred to its own ticket. Nothing here blocks it, and
the "Watch who won't" line on the landing page stays a promise the ledger will
later keep.

---

## 1. The funnel

```
Find your seat  →  your district page (facts + the count)  →  the ask
                →  the three questions  →  email  →  confirm  →  the count moves
```

The commitment lives on `/districts/:slug`. It is the only screen where "your
seat" and "the ask" are the same view, and the district page is already the
shareable unit the whole site is built around.

**Find your seat** is a ZIP field in the hero and site chrome — no modal.
Interface pass 002 §5 is binding here: *"The primary CTA is Find your district,
not Sign up."* A modal firing before the reader has read a word is the
newsletter-popup pattern this site's voice exists to reject.

**The prompt never fires** on `/methodology` or `/sources`. Those are where
hostile readers go to check our work; asking there converts a skeptic into an
ex-visitor. Nor on repeat visits, after dismissal (permanent), after
committing, or to crawlers.

---

## 2. Count, not contract

Design 001 §5 specified an assurance contract: pledges activate when K
districts each hold X confirmed pledges, evaluated nightly, broadcast on
trigger. **v1 does not build that.** It ships the count and a published goal.

The reason is honesty, not scope. `/act` currently promises *"The assurance
pledge is built for exactly that."* If the copy claims a pledge activates at a
threshold and no threshold exists, we have made a promise we are not keeping —
on a site whose entire asset is not doing that. So v1 states a **goal**, which
is a target, and not an **activation**, which is a trigger. `/act`'s copy is
edited to match what the mechanism actually does.

The activation machinery remains a clean later addition: `status` is on the
schema, and the transition is additive.

---

## 3. The goal number

**Goal = the margin, in votes, of the seat's last election.**

> Marcy Kaptur won this seat by 2,382 votes. That's the goal.

District-specific, sourced from data we already publish, and it is the number
that would have decided the last race. A uniform "500 everywhere" was the
alternative; it is legible but arbitrary, and arbitrary is the one thing this
site does not do with numbers.

**The explicit non-claim.** We do not claim that N commitments flip a seat.
Flipping requires switching votes, and a switched vote moves a margin by two;
modelling that would be a turnout claim we would then have to defend. The
margin is a *goal* — legible, sourced, district-specific — and the copy says
exactly that and nothing more.

**A safe seat shows an enormous goal, and that is the argument.** A bar reading
"103 of 184,000" is what "your vote doesn't matter here" looks like rendered as
a progress bar. Handled in copy, not by capping the number.

### Data consequence

`district_profiles.last_margin_pct` is a **percentage**. The raw counts exist
in the MEDSL House file we already parse — `lib/vni/politics/results.ex:171-191`
computes `winner.votes`, `runner_up_votes`, and the denominator, then discards
them at line 206. Two new columns keep them:

- `last_margin_votes` — winner minus runner-up
- `last_votes_cast` — the race denominator

`margin_source_url` already exists and covers both.

Edge cases, each of which must be explicit rather than silently smoothed:

| Case | `last_margin_votes` | Goal |
|---|---|---|
| Normal contested race | winner − runner-up | that number |
| Unopposed (design 001; FL/OK code as 100%) | winner's total | that number, copy reads "ran unopposed" |
| MEDSL degenerate 1-of-1 (FL-24 2016) | 1 | floor applies |
| No prior race (new district after redraw) | `nil` | fall back to the uniform default |

Floor and fallback are named constants in `VNI.Pledges`, published on
`/methodology` alongside every other rule this site computes.

---

## 4. The ask

**One sentence, not four checkboxes.** "Sign all four or none" was a rule for
*politicians* signing the ledger — it stops an incumbent cherry-picking the
demands that cost them nothing. For a voter, four checkboxes turn a commitment
into a terms-of-service. The four demands are what the site stands for and are
shown as such; the voter agrees to one thing.

The ask is personalised from facts we already hold — no survey answer needed to
make it specific, because we know the incumbent:

> **Marcy Kaptur (D) has held this seat since 1983.**
> **Will you vote against her in November, whoever runs?**

### The three questions, in this order

1. **Will you vote against [incumbent] in November, whoever runs?**
   Yes / Only if others do / No
2. **Did you vote for her last time?** Yes / No / Don't remember
3. **What party are you in now?** Republican / Democrat / Independent / Other /
   Rather not say
4. *(optional, free text)* **What would it take for her to keep your vote?**

Commitment first because it is the most important thing; you do not qualify
someone before asking it. Question 2 asked *after* the yes is Fenno's paradox
catching them in the act.

**Maybe and no are captured anonymously, without an email.** `/act` already
collects yes/maybe/no and it is the most interesting data on the site. A
yes-only form lets every "only if others do" walk away uncounted — and that
bucket *is* the assurance-contract demand, measured.

### Cross-pressure copy: recognition, not setup

Because the commitment comes first, the party answer arrives after the yes.
The four cases therefore land on the **confirmation** screen as recognition
rather than as a warning that might scare someone off mid-form:

| Voter | Incumbent | What the screen says |
|---|---|---|
| D | D | "You're a Democrat who committed to vote out a Democrat. That's the entire project." |
| R | R | Same, mirrored. |
| D | R / R | D | "This one costs you nothing. The commitment that counts is the other 434." |
| Ind / other / declined | either | Neutral. |

Row three is the doctrinal risk and it is half the potential signups. A
Democrat committing to vote out a Republican is not anti-entrenchment; it is
voting Democrat. If signups skew that way, the published data is an opposition
turnout operation wearing a nonpartisan hat. The copy names it, and §5 measures
it.

---

## 5. The number that proves the project

> **X% of the people who committed are agreeing to vote out their own party's
> incumbent.**

This is the headline statistic and it falls out of questions 2 and 3 for free.
It is Fenno's paradox broken, measured, publishable — and it is a falsifiable
check on the site's own nonpartisanship. If it is low, the project has become
the thing it says it isn't, and we would know before anyone else did.

Published nationally. Per district only above a minimum cell size, so a count
can never identify an individual.

---

## 6. Data model

New context `VNI.Pledges` — the name design 001 §2 reserved.

```
pledges
  email             citext, not null
  district_id       references districts (map-version-scoped)
  commitment        :yes | :conditional | :no
  voted_for_incumbent  :yes | :no | :unsure | nil
  party             :republican | :democrat | :independent | :other | :declined | nil
  keep_vote_answer  text, nil
  token_hash        binary, not null, unique     — magic link, sha256 of the raw token
  confirmed_at      utc_datetime_usec, nil       — nothing counts until this is set
  withdrawn_at      utc_datetime_usec, nil
  timestamps

  unique index (email, district_id)              — one commitment per email per seat
  index (district_id) where confirmed_at is not null and withdrawn_at is null
```

**Decisions inside that:**

- **Double opt-in is absolute.** An unconfirmed row is invisible to every
  public count, aggregate, and statistic. The credibility of a number that says
  "103 people" rests entirely on it being 103 people.
- **One token per pledge, no expiry, serving confirm *and* manage.** It is the
  magic link and the unsubscribe link. Design 001 §5's "no accounts" posture,
  and Phoenix 1.8's generated auth is passwordless anyway
  (`deps/phoenix/priv/templates/phx.gen.auth/context_functions.ex.eex:213`) —
  the light option and the account option have converged. Raw token in the URL;
  only its SHA-256 is stored.
- **`district_id` is map-version-scoped**, per CLAUDE.md. A commitment is to a
  seat *under a map*. Consequence, accepted deliberately: a mid-decade redraw
  starts the new district's count at zero. That is honest — the seat changed —
  and the alternative silently migrates a commitment to a district the person
  never agreed to.
- **Identities are never public.** Counts and aggregates only, always.
- **Fraud posture v1** is design 001 §5's, unchanged: double opt-in, one pledge
  per email per district, disposable-domain blocklist. Not over-engineered; the
  dashboard being directionally honest is enough at crawl scale.

---

## 7. Surfaces

```
/districts/:slug        + the count, the goal, the ask          (existing page)
/districts/:slug/join   the three questions and email
/commitment/:token      confirm, then manage / withdraw
/                       + find-your-seat ZIP field
/act                    copy corrected to match the mechanism
/methodology            + the goal rule, the floor, the fallback
```

**ZIP → district.** Not 1:1, and this is a credibility surface. Every other
number here is sourced and reproducible; a crosswalk that silently picks the
largest district in a ZIP would be the one unsourced guess in the building.

We ingest Census ZCTA polygons through the same TIGER pipeline that already
loads districts and compute the crosswalk ourselves with `ST_Intersects` —
same provenance discipline, our own methodology, citable. When a ZIP spans
multiple districts we **show the choices and make the reader pick**, ordered by
overlap area, each rendered with its silhouette
(`DistrictPresenter.svg_path/1`). Picking your district by looking at its shape
puts the gerrymander in front of them before we have said a word about it.

Never auto-pick.

---

## 8. Build order

Layered commits, each green on its own (AGENTS.md).

1. **`VNI.Pledges` context** — migration, schema, changesets, create / confirm /
   withdraw / count. Tests. No UI.
2. **Margin in votes** — two columns, `results.ex` keeps what it already
   computes, re-ingest backfills. Goal calculation with floor and fallback.
3. **The join flow** — LiveView for the three questions, confirmation email,
   `/commitment/:token`.
4. **District page integration** — count, goal, progress, the ask, the
   recognition copy.
5. **Find your seat** — ZCTA ingest, resolution, disambiguation picker.

---

## 9. Deferred, deliberately

- **Candidate signature ledger** (TK-020 as originally written) — its own
  ticket. When it lands, its sharpest risk is already known: a ledger reads as
  an endorsement surface, and "my incumbent signed, so I can keep him" breaks
  demand one on the way to enforcing it. That is a copy and IA problem, to be
  solved there.
- **U.S. Term Limits seed.** A USTL signer has not signed our four demands, and
  seeding from a largely-Republican list makes the ledger look partisan on day
  one. Factual precision and strategic cost point the same way: no.
- **The assurance-contract activation machinery** — §2.
- **Production mail adapter.** `VNI.Mailer` is on `Swoosh.Adapters.Local`
  (`config/config.exs:46`); production is unconfigured. Blocks launch, not
  build.
