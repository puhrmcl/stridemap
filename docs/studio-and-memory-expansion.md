# Studio and Memories — b586

## Memories

Discovery tries photographs on this calendar date across all previous years, then within three days of its anniversary (including December/January boundaries), then the same month, then other past history. The heading names the actual match. Today and future activities are excluded. Earlier activities from the current year can appear in the history fallback.

When there are no eligible photo references, date discovery uses activities themselves. Route or distance cards also replace photographs that cannot be loaded. Hidden activities, disabled activity types, dismissed memories and photo corrections retain their existing visibility rules. Browse filters do not narrow discovery. Explicit activity scope still applies.

Near you is a user-triggered, foreground, one-shot Core Location lookup. It matches recorded activity **start coordinates** within 25 km across past history, with or without photos. No reverse geocoding, background tracking, or coordinate persistence is added. Fixes older than five minutes or less accurate than five kilometres are rejected. Permission-denied, timeout and no-match states offer recovery. The in-app location usage explanation is updated.

## Studio

- Strict print cartography now supplies Map/Gallery previews as well as print files. A display-only Apple fallback has a separate cache namespace and cannot satisfy a strict render.
- Photo/route-only Gallery plans do not depend on a map provider. Invalid and legacy plans are handled conservatively.
- Map failure offers retry and an explicit No Map composition. No silent conversion of purchased artwork.
- Gallery map cells fit the full panel instead of cropping routes and credits.
- Large accessibility sizes use horizontally scrolling editor tabs with intact labels.
- Lithograph photograph selection sits alongside its Photo hero choice; the edited title reaches checkout.
- Older aggregate Apple map screens offer a separate Anthology editor using the same activity selection instead of leading into a browse-only shop. This is an explicit alternative, not a migration of those geographic designs to print cartography.

## Map provider decision

Etch already uses MapLibre Native with a self-hosted OpenStreetMap/Protomaps archive. Configuration references a continental-US archive (`basemap-us-20260902.pmtiles`), not worldwide coverage. Public config/tile probes returned HTTP 403 from this environment; this does not establish an outage on a user's device. Satellite/terrain and vector coverage must be checked on actual target routes.

Mapbox is an alternative provider, not an automatic fix. Its official static-map guidance specifies a 1280 × 1280 API maximum (doubled with @2x), and directs users to contact Mapbox to print Studio exports. A 24 × 36 inch print at 300 dpi is 7200 × 10800 pixels. Confirm the account's merchandise rights, attribution and large-format rendering approach before integrating a paid provider.

Sources:
- https://docs.mapbox.com/help/dive-deeper/static-maps/
- https://docs.mapbox.com/help/dive-deeper/attribution/
- https://www.openstreetmap.org/copyright

## Verification and remaining work

The PR simulator check executes 61 photo-memory assertions and 40 Studio assertions, alongside the existing scope, reveal and layout checks. The workflow captures the expanded Memories screen and existing Studio proofs. Execution results belong in the PR body after CI completes; these counts are expectations, not a claim of a passing run.

On-device acceptance still needs real Photos access, unavailable/iCloud assets, permission-denied and approximate-location behavior, nearby history, and large-text editor interaction. No migration or model schema change is introduced.

This patch does not claim physical-release readiness. Global map coverage, final map-panel pixel density (the existing snapshot path uses a fixed scale), source attribution on final printed output, route provenance and print-engine band consistency need their own release evidence. Mapbox credentials, subscriptions, fulfillment settings and checkout eligibility gates are not bypassed. Nothing is merged or distributed by this change.
