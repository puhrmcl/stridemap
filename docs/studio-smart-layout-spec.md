# Studio Smart Layout — implementation spec

## Product intent

Etch should behave like a designer, not a configuration tool. The customer should open Studio and see a finished piece that already uses the route geometry and available data intelligently. Portrait vs landscape should be a recommendation derived from the activity itself, not a guess the customer has to make.

This pass builds on the Studio Pristine Pass. Do not add more controls than necessary.

## 1. Route-aware orientation recommendation

### Current problem
`StudioCurator.bestOrientation(for:)` already inspects route bounds, but:
- it only flips to landscape above a very conservative width/height ratio (> 1.8), and
- Race Edition explicitly forces portrait, which defeats the geometry recommendation on wide point-to-point courses.

### Required behavior
- Keep Portrait and Landscape as the two explicit customer choices. Do **not** add a persisted `Auto` enum case in this pass.
- The curator should choose the recommended orientation for every new curated piece, including Race Edition.
- The Design editor should identify the recommendation clearly and quietly, e.g. `Recommended for this route` beneath Orientation or a small `Recommended` label on the preferred segment/adjacent text.
- Customer overrides always win once they choose another orientation.

### Recommendation inputs
Use deterministic route geometry only:
- Mercator-corrected route bounding-box width vs height.
- Require valid non-zero geometry; otherwise default to Portrait.
- Wide point-to-point / coastline-style routes should prefer Landscape.
- Compact loops and near-square routes should prefer Portrait.
- Tall north-south routes should prefer Portrait.

A threshold around 1.45–1.55 wide:high is a reasonable starting point, but validate visually against seeded routes rather than treating the number as sacred.

### Race Edition
Remove the current unconditional portrait override. If a race route is wide enough to benefit materially from Landscape, its curated Race Edition should open in Landscape. For a landscape Race Edition, data belongs **below** the art, not in a side column.

## 2. Premium Race Edition data hierarchy

The current Nameplate race footer stacks:
1. finish time full width
2. location as another full-width line
3. all selected stats in one equal HStack
4. weather

When 4 data items are enabled, long values (especially coordinates) compress and the panel feels like a dashboard rather than a designed print.

### New race-result hierarchy
For `run.isRace && heroMetric == .time`, use this structure:

### Band A — Result + context
One composed row:
- Left: Finish Time, large
- Right: Place, with Date beneath it

The two sides should feel optically balanced, not 50/50 by force. Finish time remains the hero.

Example:

`4:04:07`                         `SAN DIEGO, CA`
`FINISH TIME`                     `MAR 3, 2024`

On narrow/portrait compositions, allow the context block enough width to avoid awkward wrapping.

### Band B — quiet divider
A single hairline across the content width. This is a structural separator, not decoration.

### Band C — supporting stats
- Up to 4 visible supporting stats.
- Equal visual weight.
- Thin vertical dividers between cells are allowed and preferred when 3–4 stats are present.
- Use consistent value baseline / label baseline.
- Never let values collide or visually touch neighboring cells.
- `Coordinates` must not be forced into one long line. Render latitude and longitude as two compact lines inside its cell when necessary.
- Long-format metrics such as Weather, Place, or Date should not be squeezed into a narrow stat cell if already represented elsewhere. Demote them to a detail line or omit a duplicate presentation.
- Empty/unavailable values do not create placeholder columns.

Default race supporting metrics should remain restrained: Distance, Pace, and optional Finish Place. Additional user-selected metrics must still lay out safely.

### Band D — ambient detail
Standalone weather, when enabled and supported by the selected layout, sits centered beneath the stat row as a quiet finishing line.

Preferred treatment:
- weather value only (for example `66°F · Partly Cloudy`)
- optional small weather glyph if it remains visually restrained
- generous breathing room
- optionally short hairlines to either side, but no box/card treatment

Weather must never appear twice if it is also selected explicitly as a data point.

## 3. Date placement rule

For Race Edition Nameplate:
- Date belongs in the result/context block beside Place.
- Do not repeat the same date again in the upper masthead.

For non-race Nameplate, preserve the existing authored title/date treatment unless there is a clear regression.

## 4. Preserve art priority

The lower data system must never steal enough vertical space to make the map/elevation feel secondary.

Existing renderer auto-fit remains the safety net, but the design should fit naturally before shrink is required.

When content pressure is high:
1. keep the map/artwork area above its design floor,
2. preserve Finish Time hierarchy,
3. preserve Place/Date context,
4. preserve up to 4 supporting stats,
5. reduce spacing/type subtly before shrinking the entire composition aggressively,
6. never clip.

Do not solve overflow by silently hiding customer-selected data unless that field is a duplicate of information already visibly represented elsewhere.

## 5. Design-editor recommendation UX

In `StudioDesignEditor`:
- Keep the existing visual Design section.
- Orientation remains a simple Portrait / Landscape segmented control.
- Add one quiet recommendation line generated from `StudioCurator.bestOrientation(for:)`.

Examples:
- `Landscape recommended for this route`
- `Portrait recommended for this route`

Do not add explanation paragraphs or another modal.

If the customer chooses the non-recommended orientation, do not nag or automatically switch it back.

## 6. Curated picks

Every curated `StudioPick` should begin with the route-aware recommended orientation unless that particular authored product has a real physical/design reason to be fixed.

Race Edition is **not** fixed portrait anymore.

Photo/Gallery pieces may continue to use their existing authored logic unless route geometry is materially part of the composition.

## 7. No new complexity

Do not add:
- a third `Auto` orientation state
- a separate Smart Layout screen
- layout scoring exposed to users
- badges/scores
- more tabs
- extra customization axes
- AI/LLM calls

This is deterministic design intelligence.

## 8. Acceptance scenarios

### A. Wide race course
A route with corrected width:height around 2:1 should:
- open curated Race Edition in Landscape
- show `Landscape recommended for this route`
- keep result/context and stat bands beneath the map

### B. Compact loop race
A near-square loop should:
- remain Portrait
- show Portrait as recommended
- use the same premium race data hierarchy

### C. Four supporting stats
Distance + Pace + Coordinates + Elevation Gain must:
- fit cleanly without overlap
- show Coordinates in a readable compact multiline treatment when needed
- retain consistent labels and alignment

### D. Weather
When standalone weather is enabled in a supported layout:
- weather appears once, beneath supporting stats
- Gallery/Minimal/Full Bleed remain governed by the Studio Pristine Pass truth rules

### E. Customer override
A wide route recommended for Landscape can be switched to Portrait and stays Portrait until the customer changes it again.

### F. Sparse data
If only two supporting stats are available, they remain centered/balanced and do not leave empty columns.

## 9. Regression boundaries

Do not change:
- bottom app navigation
- map/cartography pipeline
- print aspect/size math
- fulfillment/checkout
- saved-poster schema unless absolutely required
- Studio home/product chooser
- Meaning Engine

## 10. Definition of done

- Simulator build passes.
- Release no-signing build passes.
- Existing Studio renderer checks remain green.
- Add/extend deterministic preview/diagnostic coverage for at least one wide route and one compact route if the existing preview harness makes that practical.
- Provide screenshots/renders for:
  1. wide Race Edition in Landscape,
  2. compact Race Edition in Portrait,
  3. all-data race panel with Coordinates + Elevation + Weather,
  4. the Orientation recommendation UI.

The visual target is the approved second concept from the Sept. 7 Studio discussion: large result on the left, place/date on the right, a quiet structural divider, a disciplined supporting-stat row, and restrained weather beneath.