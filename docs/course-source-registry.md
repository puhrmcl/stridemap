# Course source registry

This registry tracks where Etch should obtain **verified course geometry** for the Event Library.
It is intentionally stricter than the catalog itself because course geometry can become a physical
product in Studio.

## Trust policy

Use sources in this order:

1. **Organizer-hosted GPX/TCX/FIT** for the exact event/year.
2. **Organizer-linked route map with an exportable course file** (for example, an event's own CalTopo map).
3. **Government/land-manager official trail file** for hikes and summits.
4. **Verified participant file**, only when the race route is stable and it has been checked against the organizer's official course map.
5. **Hand trace** only as an on-screen approximation. Never treat it as print-ready geometry.

A file is not considered verified merely because its distance is close. Before it is promoted to a
print-ready bundled course, record the source, event year, retrieval date, file hash, measured distance,
and a human verification note against the official course map.

## File naming

- `event-id.gpx` — stable course used across years.
- `event-id-YYYY.gpx` — year-specific course. Prefer this whenever an organizer publishes a dated file.

## Verified / official sources identified

| Event | Etch ID | Year | Source | Status | Notes |
| --- | --- | ---: | --- | --- | --- |
| BMW Berlin Marathon | `berlin` | 2025 | Organizer GPX: `https://www.bmw-berlin-marathon.com/fileadmin/media/events/berlinmarathon/gpx/BM25_Marathon-Strecke.gpx` | **Official GPX identified — ingest pending** | Organizer's current course page links the marathon GPX. Store as `berlin-2025.gpx`; do not silently reuse for 2026 until the organizer confirms the course. |
| Hardrock 100 | `hardrock-100` | 2026 | Organizer GPX: `https://www.hardrock100.com/files/course/HR100-Course-Clockwise.gpx` | **Official GPX identified — ingest pending** | Organizer labels it Clockwise 2026 and updates the course annually. Store as `hardrock-100-2026.gpx`. Hardrock alternates direction, so this must remain year-specific. |
| UTMB Mont-Blanc | `utmb` | 2026 | Organizer race page (`montblanc.utmb.world`) | **Official GPX scheduled / acquire when posted** | Organizer states the 2026 GPX is published about two weeks before the event from the race page's Map + GPX tab. Always use a year-specific file. |
| Black Canyon Ultras 100K | `black-canyon-100k` | current organizer map | Aravaipa organizer page → organizer-linked CalTopo map | **Organizer route identified — export/verify pending** | Event page explicitly directs runners to the course map/GPX for navigation. Acquire the latest race-week file and store year-specific because the route can change. |
| Javelina Jundred | `javelina-jundred` | current organizer map | Aravaipa organizer page → organizer-linked CalTopo map | **Organizer route identified — export/verify pending** | Current 100-mile route is one longer first loop plus four shorter loops. Acquire the organizer-linked route export, not a generic Pemberton Trail file. |

## Major road races requiring verified acquisition

These events currently expose an official course map on the organizer site, but Etch has not yet found
an organizer-hosted GPX in the public course page. Do **not** promote a random Strava/MapMyRun file to
print-ready simply because it looks right.

| Event | Etch ID | Current catalog geometry | Next action |
| --- | --- | --- | --- |
| Boston Marathon | `boston` | hand-traced approximation | Seek organizer/partner GPX; otherwise verify a clean participant route against the current B.A.A. course map and preserve the year. |
| TCS New York City Marathon | `nyc` | hand-traced approximation | Seek NYRR/official app export or verified participant GPX checked against the current five-borough course map. |
| Bank of America Chicago Marathon | `chicago` | hand-traced approximation | Seek organizer/official app export or verified participant GPX checked against the current course map. |
| TCS London Marathon | `london` | none | Organizer publishes a detailed annual course map; acquire a year-specific verified route before enabling course-generated prints. |
| Tokyo Marathon | `tokyo` | none | Organizer publishes detailed kilometer-by-kilometer course information and a downloadable map; acquire a year-specific verified route before enabling course-generated prints. |

## Ingest checklist

For every course file added to `Etch/Resources/Courses`:

- [ ] Source is organizer / organizer-linked / land-manager official, or the exception is documented.
- [ ] Year is known; year-specific filename is used when the course can change.
- [ ] GPX parses successfully with Etch's existing activity parser.
- [ ] Route distance is plausible against the catalog's official distance.
- [ ] Start/finish and major turns visually match the organizer's current course map.
- [ ] SHA-256 is recorded below or in the ingest PR.
- [ ] Route provenance is treated as **verified** before Studio can sell it.
- [ ] Approximate/traced geometry remains screen-only.

## Retrieval limitation note

Some organizer sites serve GPX as `application/octet-stream` / `application/gpx+xml`. The research
environment can identify and verify those official download URLs but cannot reliably ingest the raw
attachment bytes directly. Those files should be downloaded from the organizer URL without alteration,
then committed to `Etch/Resources/Courses` and validated with the checklist above.
