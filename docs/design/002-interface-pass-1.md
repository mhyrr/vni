# VNI Interface Pass 1

**Status:** accepted for implementation as a visual prototype (2026-07-13).
**Purpose:** make the product tangible before production data is loaded. Every value shown in the prototype is labeled illustrative and must not be treated as published analysis.

---

## 1. The user journey

The public product is one argument that becomes progressively personal:

1. **The Case** — incumbency survives because every district treats its own incumbent as the exception.
2. **The Atlas** — the national geographic view: maps, authorship, compactness, and partisan context.
3. **The Districts** — a 538-style directory for comparing and sorting all 435 districts across distinct dimensions.
4. **The District** — the shareable unit: one district's geography, map context, electoral history, and incumbent tenure compared with nearby districts and the country.
5. **Act** — answer the Fenno question, explain the exception, then make a conditional pledge once that mechanism exists.

The Atlas and the district directory share data but answer different questions. The Atlas asks, "What does the national map reveal?" The directory asks, "Which districts stand out, and by which measure?"

---

## 2. Routes

```text
/                       The Case — long-form editorial homepage
/atlas                  National map and chart overview
/districts              Sortable district directory
/districts/:slug        District profile and history
/methodology            Definitions, formulas, sources, and caveats
/act                    Non-persisting Fenno survey prototype
```

Phase 3 adds the verified pledge and management routes. It should not require a conventional user account; email confirmation and a management link remain the preferred mechanism.

---

## 3. District comparison model

There is no single district score. The directory exposes independent attributes, each sortable and each compared with nearby districts and the national distribution:

- **Geographic compactness:** district-level shape metrics. This is geometry, not proof of intent.
- **Map bias:** statewide/map-level partisan distortion. The production label and formula remain unsettled; the prototype uses illustrative values only.
- **Party turnover:** how often the seat changed party over a defined historical window.
- **Incumbent tenure:** years the current officeholder has served.

Last-election margin, partisan lean, map authorship, litigation, and redraw history provide context but are not collapsed into a synthetic entrenchment rating. The product earns trust by keeping unlike measurements unlike.

---

## 4. Visual direction

The design is editorial, confrontational, and deliberately unresolved.

- Republican red and Democratic blue are the **evidence colors**.
- Acid yellow is the **editorial color**: headlines, annotations, warnings, and interruptions.
- Signal green is the **action color**: crossing the party boundary and doing something new.
- Black and warm newsprint hold the system together.
- Purple is avoided. It reads as compromise or partisan blending; the thesis is coordinated disruption.

The graphic grammar uses collisions, hard rules, oversized type, offset blocks, district silhouettes, and dense data labels. It should feel closer to an independent newspaper, campaign broadside, and public data terminal sharing a desk than a polished nonprofit landing page.

Motion is restrained to useful provocation: a slow evidence ticker, directional hover shifts, and responsive metric bars. Reduced-motion preferences are honored.

---

## 5. Copy direction

The homepage follows one large Ogilvy-style argument rather than a sequence of product-feature cards:

> You hate Congress. You'll re-elect your part of it.

The recurring doctrine line is **Policy should win. Not power.** It punctuates the argument and anchors the action flow; it does not replace the more specific Fenno hook above the fold.

The argument proceeds from Fenno's paradox, to the machinery of entrenchment, to visible evidence, to the coordination mechanism. The primary CTA is **Find your district**, not **Sign up**. Registration is an implementation detail; seeing one's exception is the user motive.

---

## 6. Prototype boundary

This pass proves hierarchy, rhythm, color, density, sorting behavior, and the district-page anatomy. It does not prove factual data, production map rendering, mobile table performance, or the final gerrymandering methodology. Preview values live in an explicitly named web-layer module and are removed when the ingestion work lands.
