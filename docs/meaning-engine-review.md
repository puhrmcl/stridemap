# Meaning Engine — independent architecture review

Review of PR #11 (`chatgpt/meaning-engine-v1`, `Etch/ViewModels/MeaningEngine.swift`, 257 lines)
and of the proposed V2 direction. Written as an adversarial review: the objective is not
validation.

Companion to `docs/yearbook-strategy.md`. Where the two disagree, this document is newer.

---

## 0 · Verdict

V1 has the **right skeleton and the wrong epistemology.**

The skeleton is genuinely good: a deterministic, local, evidence-carrying interpretation layer
that is separate from presentation, with significance held internal. Keep all of that.

The epistemology is broken in a way the codebase has *already diagnosed and rejected once*.
Eight commits before this PR, `c997ffa` ("b567: no duplicate numbers, no guessed firsts")
removed every "new state" claim from the Year Book, with this rationale:

> Whether a state is a "first" depends on when the history was imported, and a superlative
> the reader knows is wrong discredits the honest ones beside it.

MeaningEngine V1 reintroduces exactly that claim as a core primitive — `placeFirsts()` emits
"A new state etched" at significance 76 and "A new country etched" at 88 — and generalises it:
"Your first race", "Where your running story begins", "N years in motion". Every one of these
is a statement about **the database**, presented as a statement about **the person's life.**

The tell is inside the PR itself. The evidence strings are honest:

- `"Earliest activity marked as a race"`
- `"First located activity in \(country)"`
- `"Elapsed years since earliest imported activity"`

…and the titles are not: *"Your first race."* The gap between the evidence and the story is
precisely the failure the architecture exists to prevent, and it is currently one line wide.

This is not a bug in one detector. **The engine has no model of what it does not know.**
Fixing that is the whole of V2's foundation, and it is cheap: `Run.importedAt` already exists.

---

## 1 · Meaning taxonomy

### The category error to fix first

V1 assigns its highest significance to Achievement: race PR 96, non-race best 90, first race 88,
furthest 86, biggest climb 80. That is backwards for the stated positioning.

Achievement is the one territory where Strava, Garmin, Nike and Apple Fitness are *already
excellent*. It is table stakes, it is commoditised, and Etch cannot win there. "See where you've
been. Remember what it meant." promises something else entirely.

**Recommendation: Achievement should carry the lowest base weight of the five families, not the
highest.** It should appear because it is rare for *this person*, not because it is an
achievement.

### Five families

| Family | Question it answers | Data | Etch advantage |
|---|---|---|---|
| **Achievement** | What did you accomplish? | distance, time, pace, elevation | none — commoditised |
| **Endurance** | What have you kept doing? | dates, gaps, ritual, span | high |
| **Territory** | Where has your life happened? | place clusters, lifespan, range | very high |
| **Accumulation** | What does it add up to? | sums, counts, thresholds | high |
| **Memory** | What was that day like? | photos, weather, race context | very high |

Endurance, Territory and Memory are where the differentiation lives. All three are
under-represented in V1 (Endurance and Memory are absent entirely).

### Missing categories worth having

- **Ritual** — "the Thanksgiving morning run, seven years running." Identity, not performance.
  Fully closed-world (same week-of-year, repeated). Nobody surfaces this.
- **Endurance of place** — a route that has outlasted addresses, jobs, phones. Strongest
  Etch-shaped insight available and it needs no inference at all.
- **Adverse conditions** — the weather fields (`weatherTemperatureC`, humidity, wind) are
  already backfilled and almost entirely unused. Effort under heat/cold is viscerally
  remembered and structurally invisible to competitors, who do not retroactively join weather.
- **The ordinary** — the median activity of a year, named as such. The anti-highlight.
- **Companionship (photo-derived, non-identifying)** — "you weren't alone that day," from a
  face *count*, never an identity.

### How they relate

Not a flat list. Two axes worth modelling explicitly:

- **Scope**: a moment (one activity) · a season (a window) · a life (the whole record).
  V1 only has moments, which is why "years in motion" feels wrong — it is a life-scope fact
  crammed into a moment-shaped `Insight`.
- **Register**: *proud* / *fond* / *surprised*. Cross-cuts family; a Territory insight can be any
  of the three. V1's `Emotion` is currently a static per-detector lookup, i.e. decoration.

### Pseudo-psychology to avoid

No motivation inference, no discipline scoring, no "you're a morning person" personality
claims, no wellbeing/mood inference. Etch describes what a person did. It does not tell them
who they are.

---

## 2 · Signal architecture

V1 collapses six layers into one function. `insights(limit:)` generates, dedupes, ranks and
formats prose in a single pass, which is why every problem below is entangled with every other.

The pipeline should be six explicitly separated layers, each independently testable:

```
L0  ACTIVITIES        Run (SwiftData, source of truth, never written by the engine)
L1  DERIVED FACTS     per-run + per-window scalars: comparability class, grade-adjusted
                      pace, place cluster, week bucket, rolling volume, cumulative totals.
                      Deterministic, incremental, persisted, versioned. No language.
L2  RELATIONS         entities with lifespans: places, routes, distance classes, events,
                      seasons. "This cluster: 340 runs, 2016-06 → 2025-08."
L3  CANDIDATES        detector output: a claim + subject + evidence refs + world-class
                      (see §3). No prose. No ranking. Cheap to add, cheap to delete.
L4  APPRAISAL         significance × confidence, computed against this person's own
                      distribution. Still no prose.
L5  SELECTION         context-aware: surface, diversity caps, history of what was shown,
                      user feedback. Ephemeral.
L6  LANGUAGE          template + slot rendering. A pure function of L3/L4. Cannot
                      introduce a fact.
```

The hard boundary is **L4/L6: no layer above L6 may contain a string that a user will read,
and L6 may not contain a number that did not arrive from L3.** V1 violates this in every
detector (prose is constructed inside the detector, next to the arithmetic that justifies it).

Practical consequence: detectors become ~15 lines of arithmetic returning a struct, which makes
them reviewable, testable, and safe for another agent to add without touching voice.

---

## 3 · Significance and confidence

### They must be separate. They answer different questions.

- **Significance** — *if this is true, how much would it matter to this person?*
- **Confidence** — *how likely is it to be true, given what Etch can and cannot see?*

V1 has significance only, as hardcoded constants (62, 76, 80, 86, 88, 90, 96), with two
structural defects:

1. **It is absolute, not personal.** A marathon PR scores 96 for everyone. For a person with
   one marathon, "Marathon PR" is not an achievement, it is *a definition* — their only
   marathon is necessarily their best. V1 will confidently tell them so. One insight like
   that costs more credibility than ten good ones earn.
2. **It has no rarity term.** Significance should be driven substantially by **surprise
   relative to this person's own distribution** — a 14-mile run is enormous for someone whose
   median is 3, and a Tuesday for someone whose median is 12. Both are computable from L1.

### Proposed significance model

Score in [0,1], composed from named, inspectable terms — never a single tuned magic number:

| Term | Meaning | Notes |
|---|---|---|
| `rarity` | percentile of this event within the person's own distribution | the dominant term |
| `effort` | duration × relative intensity vs their baseline | |
| `culmination` | does this close a long arc (a build, a threshold, a return)? | |
| `recency` | mild recency preference | must NOT dominate — the point is deep history |
| `scarcity` | how few other candidates share this subject/kind | |
| `memoryContext` | photos exist / adverse weather / race | |
| `userAffinity` | learned family preference (§8), bounded ±25% | |

`significance = weighted_sum(terms)` with weights in one visible table, not scattered literals.

### The claim-world taxonomy (the important part)

Every candidate is classified by **what missing data can do to it**:

| Class | Definition | Examples | Safe? |
|---|---|---|---|
| **Closed-world** | true *within* the record, and the record is the stated subject | furthest recorded activity, count of runs on a route, sum of miles, place lifespan | **Yes — assert plainly** |
| **Floor claim** | monotone in missing data: unseen data can only make it *larger* | cumulative-mile thresholds, states counted, years spanned, "at least N times" | **Yes — assert as a floor** |
| **Open-world** | unseen data can *falsify* it | first X, new place, "never before", "after 3 years away", comeback | **No — hedge, scope, or ask** |

This single classification resolves the b567 problem generally rather than case by case:

- ❌ "A new state etched. Arizona became part of your map."
- ✅ *(floor)* "Arizona is one of 14 states in your record."
- ✅ *(scoped)* "The earliest Arizona run Etch has is March 2019."
- ✅ *(asked)* "Was this your first time running in Arizona?" → one tap → permanent fact.

### Confidence drives language, not just ranking

This is the mechanism that makes open-world claims usable at all:

| Confidence | Behaviour |
|---|---|
| High | Assert. "Your furthest run." |
| Medium | Scope explicitly. "The furthest in your Etch history." |
| Low | **Do not assert — ask.** "Was this your first marathon?" |

**Low confidence is not a reason to discard a candidate. It is a reason to convert it into a
question.** And a question the user answers becomes a permanent, high-confidence fact — which
means the engine gets *more* certain over time instead of guessing forever. This also merges
cleanly with the "♡ This matters" interaction (§8): one interaction pattern, two jobs —
preference learning *and* epistemic resolution.

### Confidence inputs

- **Horizon distance** — how far `startDate` sits above the earliest record. A "first" three
  weeks after the horizon is nearly worthless; ten years after, it is strong.
- **Provenance** — `importedAt − startDate`. Runs Etch witnessed (imported within days of
  happening) support far stronger claims than a bulk backfill spanning eight years.
- **Coverage/gaps** — a 14-month hole means "first since" claims are unreliable.
- **Field dependence** — claims resting on `isRace` (user-tagged) or `paceSeriesRaw`
  (only present on newer imports) inherit that field's patchiness.
- **Measurement margin** — a PR by 0.4% is inside GPS error (§5).

---

## 4 · Training arc detection

### The trap

A person who runs 40 miles a week forever, then runs a marathon, did not "train for" it in any
sense they would recognise — but every naive window detector will announce *"18 weeks. 612
miles. It led here."* The claim imputes **intent**, which is not in the data.

### Two products, not one

**Descriptive (always safe, closed-world, no intent):**
> "In the 18 weeks before Mesa: 612 miles, 73 runs, longest 22.4."

This is a sum over a stated window. It cannot be wrong. Ship this as the default — it is
already 80% of the emotional payload, because the payload is *the volume of forgotten work*,
not the causal claim.

**Interpretive ("a training block") — requires structural evidence:**

Require ≥3 of these, all measured against the person's own 12-month baseline, not absolutes:

1. **Ramp** — positive trend in weekly volume across the window, significantly above baseline
   variance.
2. **Peak** — a maximum weekly volume in the final third, ≥1.3× baseline median.
3. **Taper** — volume drop of ≥25% in the last 1–3 weeks, race at the terminus.
   *Highest-signal marker: tapers do not happen by accident.*
4. **Long-run progression** — longest-run distances trending toward race distance.
5. **Specificity** — appearance of efforts at or near race distance/pace not present in baseline.
6. **Density** — activity count meaningfully above the person's baseline rate.

Taper + ramp + long-run progression is the strong signature. Absent that, do not use the word
"training."

### Correlation vs. confirmed intent

- Never claim a block for a race the person ran *inside* another block (a parkrun mid-build).
- Never claim overlapping blocks for two races two weeks apart — attribute to the terminal race.
- When structure is ambiguous (2 of 6 signals): **ask.** "Were you training for Mesa?" Confirmed
  intent is then stored as fact with confidence 1.0 and never re-derived.
- Store the arc as an L2 relation with explicit window bounds, so the Studio can render it and
  the user can correct the start date.

---

## 5 · Progression detection

The prompt's hazard list is right and incomplete. The three it misses are the dangerous ones:

- **Selection bias / regression to the mean.** Comparing "best 5K of 2019" to "best 5K of 2024"
  compares maxima of samples of *different sizes*. 200 runs produce a better max than 40 by
  chance alone. **Compare distributions (median, or a fixed quantile), never maxima**, when the
  claim is about change over time.
- **Age.** A 10-year progression window crosses real physiological change. Etch must never
  editorialise decline — no "your slowest year," no implied falling off.
- **Grade.** Pace without grade adjustment is not comparable across terrain. `elevationSeriesRaw`
  exists; at minimum bucket by elevation-gain-per-mile and only compare within bucket.

Plus the ones named: elapsed-vs-moving (races are chip time, training runs have pauses — never
compare across that boundary), GPS error (1–2% typical, worse in cities; require effect size
beyond it), weather (heat costs roughly 2–3% per 10°F above ~60°F — either normalise or compare
only within condition bands), activity type, race-vs-training.

### The governing rule

**Progression claims must compare like with like. Where they can't, they become context, not
claims.** Define an explicit `ComparabilityClass` in L1 (activity type × distance band × grade
band × race/training × time-basis) and forbid cross-class comparison at the type level, so it is
a compile-time-ish guarantee rather than a reviewer's vigilance.

Prefer robust framings over fragile ones:

- Robust: "you have run more halves each year for four years" (counts, volume, range)
- Fragile: "you got faster" (confounded six ways)

---

## 6 · Place intelligence

Place is Etch's strongest and most dangerous territory.

### The line

Describe **what the person did**. Never infer **who they are or where they live.**

### Do not name home. Ever.

Not "your home route," not "home." Call it **"your most-run route"** or let the user name it.
Two reasons:

1. It is the creepiest available output — the moment an app announces it knows where you live.
2. **It is a safety problem specific to Etch: this app prints and ships posters.** A poster
   captioned "home loop" with a precise start marker, posted to Instagram, discloses a home
   address to strangers. This is a real product risk, not a hypothetical.

**Hard requirement: no shareable artifact may render a most-frequent start point at full
precision.** Snap to cluster centroid, or offset, or omit the marker. (The endpoint markers were
already removed from prints in b556 for aesthetic reasons — that decision should now be recorded
as a *safety* decision too, so it is not casually reverted.)

### What to build

`RunStatistics.geohashLabel` already buckets starts to ~1.1 km. Promote that to a real L2 entity:

```
PlaceCluster: centroid, radius, first seen, last seen, count, distance sum,
              years spanned, density curve, associated races, photo count
```

That single record yields, all closed-world and all safe:

- most-run route (count)
- **endurance of place** (years spanned — the best insight in the system)
- exploration / range (distinct clusters, convex hull area)
- seasonal or annual returns (recurrence in the density curve)
- "the one you came back to" (long gap then resumption *within the record* — scoped, not
  claimed as absolute)

### Keep out

Workplace inference, commute pattern inference (`isCommute` exists — use it as a *filter*, never
as a subject), school/gym/medical proximity, anything about a *second* person's location, and
any narrative that requires knowing why someone stopped going somewhere.

---

## 7 · Photo and memory intelligence

### Responsible inferences

From timestamp + coordinate proximity to an activity window only:

- **presence** — "there are photographs from this day"
- **count** — a rough intensity-of-memory signal
- **span** — photos across the activity's duration vs. a single frame at the finish

That is enough. **You do not need to look at the photographs to know the day mattered.**
Forty-seven photos on one Saturday is a complete signal by itself.

### Optional, with care

Face **count** via on-device Vision, to support "you weren't alone." No identity, no matching, no
persistence of any face data. Honestly: worth deferring — the marginal emotional gain over
photo-count is small and the inference-risk gradient is steep.

### Never

Identity or relationships · emotion or expression · body, appearance, health, pregnancy,
injury · scene classification used to characterise a person's life · **any transmission of a
photo, thumbnail, embedding, or derived descriptor off the device** · retention of photo-derived
data after Photos access is revoked.

### Access architecture

Design **limited-access-first**. Full-library authorisation to scan every asset's metadata is a
large ask and a large liability; an app that requests it in order to "find your memories" is
indistinguishable, at the permission sheet, from an app that wants everything.

Preferred: per-activity opt-in ("add photos from this day"), which is also how the existing
`PhotoLibrary.importImage` / `photoReferences` path already works. Bulk correlation, if ever
built, must be an explicit, separately-explained, revocable choice — and must degrade
gracefully to zero when declined, because most users will decline.

Photo-derived signals are **counts and booleans in L1**, recomputable and disposable, never the
only copy of anything.

---

## 8 · Personalisation

### What "♡ This matters" should teach

Not *"show me more of this item"* — items never recur. The signal must generalise to **kinds**:
`(family × register × subject-type)`. The proposed reason taxonomy (Achievement / People / Place
/ Memory / Personal) is close to right; align it with the five families in §1 so feedback lands
on the same axes the engine ranks by.

### Design constraints that keep it non-manipulative

1. **Explicit signal only.** No dwell time, no scroll depth, no open rate, no impression
   counting. Not merely unused — **not collected.** That is what makes it a promise rather than
   a policy, and it is the fork in the road between Etch and an engagement product.
2. **Small-data statistics.** A user will produce 5–50 signals in their life, not millions. Use
   strong priors (Beta/Dirichlet per family) so a single tap moves ranking slightly and ten taps
   move it meaningfully. No gradient anything.
3. **Bounded influence.** Personalisation may adjust significance by at most ±25%. This prevents
   both the opaque-algorithm failure and the filter bubble where one tap on "Place" means the
   person never sees a race again.
4. **Inspectable and editable.** A plain sentence in Settings: *"You've told Etch that places and
   memories matter most."* With controls. An engine whose learned model can be read and corrected
   in ten seconds cannot become the thing people fear.
5. **Negative feedback is precise and permanent.** "Not this" suppresses *that claim* forever
   (never re-shown) and downweights its kind slightly. Never re-litigate a dismissal.
6. **Dual-purpose interaction.** The same tap resolves epistemics (§3): "Was this your first
   marathon?" is both a confirmation and a preference signal. This is the highest-leverage
   interaction in the system — it makes the engine's *facts* better, not just its *ranking*.

---

## 9 · Story generation

**Answer: hybrid (D), but with an unusual split that most implementations get wrong.**

### The invariant

> Language is a pure function of a validated structure. No user-visible string may contain a
> fact that is not present in that structure.

### Layer ownership

| Concern | Owner |
|---|---|
| every number, date, place name, distance, time | **template** |
| the claim verb and its hedging ("is" vs "the earliest Etch has") | **template**, selected by confidence |
| which of N approved phrasings, clause order, length for the surface | **model or deterministic chooser** |
| anything that could introduce a noun | **nobody** |

### The recommended use of Foundation Models

Not "write a story about this run." Instead: **constrained selection with guided generation.**
Define the `@Generable` output as a *choice among approved templates plus slot assignments* —
an enum and some indices — never free text. Constrained decoding then makes an unapproved
sentence **physically unrepresentable**: the model cannot emit a token that the schema does not
permit. Variety without a hallucination surface.

This is the strongest available argument for using the framework at all, and it is a use almost
nobody implements.

### If free text is ever permitted

Add a **fact gate**: extract every number and proper noun from the generated string, verify each
appears in the evidence structure, reject and fall back to the template on any mismatch. Cheap,
deterministic, and it fails safe.

### Cloud LLM: no

The input is the most sensitive data in the app. Cloud inference forfeits the privacy moat,
adds latency and per-user cost, breaks offline, and buys phrasing quality users cannot perceive.
The only defensible "cloud" use is **authoring the phrase library at build time** — a human and
a model writing good sentences that ship in the binary. That is not runtime, and it is where the
literary quality should actually come from.

### Hard requirement

Foundation Models must be **optional**. It is gated on Apple-Intelligence-capable hardware and a
user-enabled setting. The deterministic template path must be complete and good on its own — the
model is a garnish, never a dependency.

---

## 10 · Apple platform assessment

Verified against current documentation (Sept 2026); iOS 26 shipped Foundation Models, WWDC 2026
extended it.

### Genuinely helps

- **SwiftData** — already the store. Needs a versioned derived-fact schema (§12).
- **HealthKit** — already the source of truth for import.
- **WeatherKit** — already integrated (`weatherBackfilled`) and badly underused. The single
  highest ratio of emotional payoff to remaining work in this review.
- **Core Location / MapKit** — already used; reverse geocoding happens at import; `MKPolygon`
  boundary work already exists for states/countries.
- **PhotoKit** — yes, limited-access-first (§7).
- **BGTaskScheduler** (`BGProcessingTaskRequest`) — the correct home for incremental and full
  rebuilds. Currently absent and needed (§12).
- **Foundation Models** — yes, for constrained selection only (§9). iOS 26+, on-device ~3B
  model, `@Generable` guided generation with constrained decoding, streaming, tool calling.
  WWDC 2026 added a public `LanguageModel` protocol allowing third-party/cloud providers behind
  the same `LanguageModelSession` API — **which Etch should deliberately decline to use**, since
  the value here is precisely that inference never leaves the device.

### Unnecessary complexity

- **Core ML / Create ML custom models** — training a "meaningfulness" model requires labels that
  do not exist, at a scale that does not exist, producing an unexplainable ranking that cannot be
  debugged or corrected. **The rules are the product.** Revisit at six figures of users, if ever.
- **LoRA adapters for the on-device model** (WWDC 2026 toolkit) — real, but wildly premature:
  it presumes a phrasing problem Etch does not yet have and a training corpus it does not own.
- **NaturalLanguage** — sentiment/embeddings over activity *titles* is noise; people name runs
  with jokes. Possible future use for clustering user `notes`. Not now.
- **Vision** — only if the face-count signal is built (§7). Nothing else.

---

## 11 · Privacy as architecture

Etch already has the right doctrine written down for commerce, in `docs/launch-checklist.md`:

> Etch does not upload a workout. It uploads a picture the customer made and asked us to print.

**Extend that doctrine to meaning, as a stated invariant:**

> Etch does not upload a life. Interpretation happens on the device that holds the data, and
> stays there.

### Boundaries to establish before V2, not after

1. **No derived meaning leaves the device.** Not insights, not evidence, not embeddings, not
   counts, not aggregates. Enforce with a test that asserts no network symbol is reachable from
   the engine module, so a future contributor cannot quietly cross the line.
2. **No insight telemetry.** Not collected at all (§8.1).
3. **Photos: least access, revocable, forgettable.** Revocation must delete derived photo facts,
   not merely stop reading.
4. **Location precision discipline in outputs**, especially printable and shareable artifacts
   (§6).
5. **A visible meaning store.** The user can see everything the engine believes about them and
   delete any of it. "Forget this" must actually forget — including from caches and from the
   feedback model.
6. **Deletion propagates.** Deleting or hiding a run must invalidate every derived fact and
   insight that references it. `isHidden` / `excludedFromTotals` are already respected in V1's
   `init` — good, and that must survive into the persisted layer, which is harder.
7. **No account required for any of it.** Meaning must work with zero server, forever.

This is a real moat: a social, cloud-dependent, data-monetising competitor cannot copy
"it never leaves your phone" without dismantling its own business.

---

## 12 · Computational architecture

### The failure this repo has already had once

`insights(for run:)` calls `insights(limit: 100)`, which runs **every detector across the entire
history** and then filters to one run. From a detail view. In a list.

This is the same shape as `b564`, three weeks ago, where `BookStudioView.plan` was a computed
property re-running the story engine per page child — seconds of frozen UI, then a watchdog
kill, on Collections. The fix then was to build once and cache. The engine must not re-learn
this lesson on a 50,000-activity library.

**Rule: the UI reads only precomputed rows. Cost per view is O(shown), never O(history).**

### Storage layers

| Layer | Persisted | Rebuild cost |
|---|---|---|
| L0 `Run` | yes (existing) | — |
| L1 `DerivedFact` | yes — small, immutable, keyed, versioned | incremental |
| L2 `Relation` (place clusters, arcs, classes) | yes | incremental + windowed |
| L3/L4 `MeaningCandidate` | yes — stable id, significance, confidence, evidence refs, engineVersion | per-detector |
| L5 selection | no — ephemeral, cheap | per view |

### Incremental computation

Most facts are **monotone accumulations** — cumulative distance, maxima, place first-seen,
counts — which update in O(1) per new activity. Only windowed facts (rolling volume, arcs)
need a bounded recompute, and their window is known.

**The subtle part: a newly imported *old* activity can invalidate historical interpretations.**
Importing a 2019 run changes "your first race." So invalidation must be **dependency-based, not
recency-based**: each derived fact records which runs and which windows it depends on. A bulk
backfill (many runs, wide `startDate` span, single `importedAt`) should simply trigger a **full
rebuild** — rare, backgroundable, and far safer than incremental patching.

### Versioning

`engineVersion` on every derived fact and candidate. A bump marks rows stale for lazy rebuild.
This is also why **ids must be structural, never prose**: `kind + subject-key + parameters`.
V1's `id = "\(kind)-\(runID)-\(title)"` embeds generated copy, so a wording change silently
orphans every user's feedback and re-shows dismissed insights. Fix before any feedback ships.

### Scheduling

- Import completes → enqueue `BGProcessingTaskRequest`, chunked and cancellable.
- App foreground → read L3 only; if stale, show what exists and refresh behind.
- Never compute on `body`. Never compute synchronously in `onAppear`.
- Off the main actor; a dedicated `ModelActor` background context.

### Budget targets

| Library | Full rebuild | Incremental | View read |
|---|---|---|---|
| 1,000 | < 1 s | < 50 ms | < 5 ms |
| 10,000 | < 5 s (background) | < 50 ms | < 5 ms |
| 50,000 | < 30 s (background, chunked) | < 100 ms | < 5 ms |

---

## 13 · What not to build

Aggressively:

1. **`raceMoments()` — the "Race 2 / Race 3" enumerator.** It emits one insight per race
   ("Another finish added to your story") at significance 68–82. A 40-race history floods the
   candidate pool with 39 identical non-insights that crowd out genuinely rare things. This is
   the exact "badge" behaviour the positioning rejects. **Delete in V2's first commit.**
2. **Any visible significance score, streak, level, or badge.** Correctly internal today; keep it
   that way permanently.
3. **Life-event inference** — injury, illness, pregnancy, bereavement, job loss, divorce, moving
   house. The data *will* suggest these. Never say them. "Welcome back after your injury" when it
   was a death in the family is an unrecoverable product moment. **This is the single largest
   reputational landmine in the concept.**
4. **Emotion or expression inference from photographs.**
5. **Cloud LLM story generation.**
6. **A learned meaningfulness model.**
7. **Social comparison** ("faster than 78% of runners") — that is Strava's register and it
   destroys the private, personal voice Etch is building.
8. **Predictions and coaching** ("on track for a 3:45") — instantly converts Etch into the
   training app it says it is not.
9. **Notifications on meaningful moments** — the road to engagement mechanics. At most: one rare,
   opt-in, high-confidence moment. Default off.
10. **Decline narratives.** No "slowest year," no implied falling off, ever.
11. **Naming a person's home.**
12. **"N years in motion" as a standing insight** — it is a fact that is true every day, not a
    moment. It will surface forever and mean nothing.
13. **Sentiment analysis of activity titles.**

---

## 14 · Five magic experiences

Each grounded in fields that exist today.

### 1. The Loop That Stayed
> "You have run this same half-mile of sidewalk 340 times across nine years. It has outlasted
> two phones, one job, and every pair of shoes you've owned." *(last clause: only if user-supplied)*

**Data:** place cluster count + first/last seen. Fully closed-world. Zero inference risk.
**Why it matters:** nobody has ever told them this, and it reframes the most boring thing in
their history as the most constant. It is also *already a print* — one route, nine years.

### 2. The Day It Was 104°
> "14.2 miles. 104°F. August 3rd, 2023. You did that on purpose."

**Data:** `weatherTemperatureC` (already backfilled), distance, date.
**Why it matters:** adverse-condition efforts are remembered in the body. No competitor
retroactively joins weather to a decade of history, so this is *proof Etch was paying
attention* — and it costs almost nothing to build.

### 3. The Ordinary Tuesday
> "This is what 2025 actually looked like: 4.8 miles, 9:12 pace, 6:40am, Gilbert. You did this,
> or something close to it, 180 times."

**Data:** median activity of a year + count within a similarity band.
**Why it matters:** the anti-highlight. Every other product shows the peak; the truth of a life
in motion is the repetition, and naming it is the most literal possible delivery of "remember
what it meant."

### 4. It Led Here
> "18 weeks. 612 miles. 73 runs. Longest: 22.4. Then: Mesa Marathon, 3:54:54."

**Data:** descriptive window aggregate (§4), rendered as a race spread with the long-run
progression as a small chart.
**Why it matters:** the race is the memory, but the *cost* is the story, and it is invisible in
every other product. Phrased descriptively it cannot be wrong.

### 5. Before It Was Home
> "Your first 46 runs in Denver were in 2019 — two years before it became the place you run
> every week."

**Data:** place cluster density curve — sparse early presence, later sustained density.
**Why it matters:** it detects a life transition from movement alone. This is the "I never
realised that" insight.
**And it is the most dangerous one here** — it is open-world and it edges toward inferring
residence. Included deliberately to show the discipline: it must be phrased about *runs*, never
about living ("became the place you run every week", never "moved to"), gated on high density
evidence, and offered as a question before it is asserted. If that constraint makes it
unshippable, it does not ship.

---

## 15 · Competitive moat

### Not defensible

- **The detection rules.** PRs, firsts, milestones, streaks — Strava and Garmin already have most
  of them, and any of them could ship the rest in a quarter.
- **On-device phrasing.** The same framework is on every competitor's device.
- **Year-in-review.** Everybody has one; Spotify made it table stakes.

### Genuinely defensible

- **Retroactive depth.** Strava's insights begin at signup. Etch imports the *whole life* from
  HealthKit — a person's first eight years exist in Etch and simply do not exist in a
  competitor's product surface. This is a structural asymmetry, not a feature.
- **Privacy stance.** A social, cloud-dependent, ad/subscription-analytics competitor cannot
  credibly say "it never leaves your phone." Etch can, and it is already architecturally true.
- **The artifact and the spine behind it.** R2-frozen production assets, the D1 ledger, Etch
  order numbers, Prodigi, the layflat book, the framed print. **This is the actual moat.** An
  insight is a tweet; a framed print of nine years on one loop is a purchase and an object in a
  home.

### The strategic conclusion

**Do not compete on insight breadth. Compete on insight → object conversion.**

The Meaning Engine's job is not to be the smartest recap. It is to raise the rate at which a
person discovers something *worth making permanent* — and it should be measured that way
(discovery → Studio → proof → order), never by engagement.

---

## KEEP

- Deterministic, local, evidence-carrying interpretation as a distinct layer. Correct and rare.
- Significance held internal and never shown. Correct instinct; make it permanent policy.
- "Facts first, language second" as a stated principle.
- Explicit `evidence` on every insight — the single best thing in the PR.
- Respecting `isHidden` / `excludedFromTotals` at the engine boundary.
- The emotional-lens *concept* (needs to become derived rather than a static lookup).
- Reuse of `RunStatistics` PR guards (distance window, run-type-only, plausible-speed).

## CHANGE

1. **Classify every claim as closed-world / floor / open-world**, and forbid open-world
   assertions without horizon evidence or user confirmation. This is the b567 ruling, generalised.
2. **Add confidence as a first-class dimension**, separate from significance, and let it
   **choose the sentence**, not merely the rank.
3. **Make significance personal** — rarity against this person's own distribution, not global
   constants. Fix the one-marathon "Marathon PR" embarrassment specifically.
4. **Invert the family weighting** — Endurance / Territory / Memory above Achievement.
5. **Split generation from selection from language** (§2). Detectors return structs, not prose.
6. **Structural ids.** Never embed generated copy in an identity.
7. **Persist and version** derived facts and candidates; never recompute on view.
8. **Fix `insights(for:)`** — it currently recomputes the entire history to filter one run.
9. **Inject a reference date** — `anniversaries()` uses `Date()`, which breaks determinism,
   testability and caching.
10. **Add diversity constraints in selection** — per-subject and per-kind caps, so one
    exceptional activity cannot occupy five of twelve slots.
11. **Scope-aware insight shapes** — moment / season / life are not the same object.

## ADD

- **Provenance and horizon model** from `importedAt` vs `startDate` — witnessed vs backfilled,
  coverage gaps. Cheap, already in the schema, and it unlocks honest firsts.
- **`PlaceCluster` as a first-class entity** with a lifespan. Highest emotional yield per line.
- **Weather as meaning**, not just metadata. Already backfilled, nearly free.
- **Ritual detection** (same week-of-year recurrence).
- **The ordinary / median activity** as a surfaced shape.
- **Comparability classes** to make progression claims structurally safe.
- **Confirmation interactions** that upgrade confidence permanently.
- **A visible, editable meaning store** (privacy as a feature people can see).

## KILL

`raceMoments()` enumeration · visible scores/badges/streaks · life-event inference ·
photo emotion inference · cloud LLM stories · learned meaningfulness model · social comparison ·
predictions/coaching · engagement notifications · decline narratives · naming home ·
"N years in motion" as a standing insight · title sentiment analysis.

---

## V2 architecture (recommended)

```
                    ┌──────────────────────────────────────────┐
   Run (SwiftData)  │ L0  activities — source of truth         │
                    └───────────────┬──────────────────────────┘
                                    │ import / edit / delete
                    ┌───────────────▼──────────────────────────┐
                    │ L1  DerivedFact (persisted, versioned)   │
                    │     comparability class · grade-adj pace │
                    │     place cluster · week bucket          │
                    │     rolling volume · cumulative totals   │
                    │     provenance: witnessed vs backfilled  │
                    └───────────────┬──────────────────────────┘
                    ┌───────────────▼──────────────────────────┐
                    │ L2  Relations (persisted)                │
                    │     PlaceCluster · TrainingArc · Season  │
                    │     DistanceClass · Event series         │
                    └───────────────┬──────────────────────────┘
                    ┌───────────────▼──────────────────────────┐
                    │ L3  Candidates — claim + subject +       │
                    │     evidence + world-class. No prose.    │
                    └───────────────┬──────────────────────────┘
                    ┌───────────────▼──────────────────────────┐
                    │ L4  Appraisal — significance × confidence│
                    │     rarity vs this person's distribution │
                    └───────────────┬──────────────────────────┘
                    ┌───────────────▼──────────────────────────┐
                    │ L5  Selection — surface, diversity caps, │
                    │     seen-history, bounded user affinity  │
                    └───────────────┬──────────────────────────┘
                    ┌───────────────▼──────────────────────────┐
                    │ L6  Language — templates; confidence     │
                    │     chooses the verb. Optional on-device │
                    │     model selects among approved forms.  │
                    └───────────────┬──────────────────────────┘
                                    │
                    ┌───────────────▼──────────────────────────┐
                    │ PROPOSAL — insight + composed artifact   │
                    │ recipe → StudioCurator → Made for You    │
                    └──────────────────────────────────────────┘
```

Background: `BGProcessingTask` for rebuilds; dependency-based invalidation; `engineVersion` on
every persisted row. No network egress anywhere in the diagram.

---

## V2 implementation priority — first five tasks

1. **Provenance & claim-world foundation.** Add the horizon/coverage model from `importedAt`,
   classify every existing detector as closed/floor/open, and re-voice or gate the open ones.
   Delete `raceMoments()`. *This is the credibility fix and it blocks everything else.*
2. **Split significance and confidence**, with confidence selecting the sentence form
   (assert / scope / ask). Make significance personal (rarity term). Fix the single-instance PR.
3. **Persist L1 + L3 with structural ids and `engineVersion`**; move all computation off the
   view path into a background task; fix `insights(for:)`. *Prevents the b564 failure at scale.*
4. **`PlaceCluster` with lifespan** → ship "The Loop That Stayed" end-to-end as the first new
   insight family, including its Studio proposal.
5. **Confirmation interaction** ("Was this your first marathon?" / "Were you training for
   this?") — one component serving both epistemics and preference, with the bounded, inspectable
   affinity model behind it.

Deliberately *not* in the first five: training arcs (needs 1–3 first), photos (needs a permission
strategy), and any use of Foundation Models (needs the template layer to be complete first).

---

## One big idea

**The Meaning Engine's output type should not be a story. It should be an object proposal.**

Today the engine terminates in `Insight { title, story, symbol }` — content for a feed. But a
feed is a game Etch cannot win: an insight that arrives as a card is competing for attention with
Instagram, and it is measured in engagement, which is the exact gravity that turns products into
the thing this one is positioned against.

Etch's business is manufactured objects. There is already a fulfilment spine (R2, D1, Etch order
numbers, Prodigi), already a composition engine (`StudioCurator` turning a run into a
`PosterConfig`), and already a surface built to receive a personalised recommendation — Pass 2's
**"Made for you"** hero, which currently chooses its subject heuristically.

So invert it. The engine's terminal type becomes:

```
Proposal {
    insight        // what was noticed, with evidence and confidence
    artifact       // a composed, ready-to-view recipe — not a prompt to go design one
    format         // the object it wants to be: print, spread, book page, wall piece
}
```

Three consequences, all good:

1. **"Made for you" becomes true.** It stops being "here is a nice run of yours" and becomes
   "here is the thing we noticed, already made." The hero already renders a real composed
   artwork (PR #6) — it just needs a better reason for choosing *that* one.
2. **It disciplines the taxonomy for free.** Any insight that cannot become an object is
   probably a statistic in disguise. "Race 2" cannot be a print. "Nine years, 340 runs, one
   loop" obviously is. **The engine cannot drift back into fitness analytics if its output type
   is a framed print.**
3. **It gives the engine an honest metric.** Not opens, not taps, not time-in-app —
   *discoveries that became objects.* A meaning engine measured in engagement eventually
   optimises for compulsion; one measured in prints optimises for genuine resonance, because
   nobody buys a framed poster of a moment that did not actually matter to them.

The Meaning Engine is not Etch's recap feature. It is Etch's **demand generator**, and it should
be architected, prioritised, and measured as one.
