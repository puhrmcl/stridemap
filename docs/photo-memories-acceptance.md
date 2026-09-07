# Photo Memories 1 (b580)

Entry points: Timeline → Memories; activity → Photos → Manage / View photos on map.
The four main destinations remain unchanged.

## Contracts

- Removing a photo rejects that activity/asset association. Automatic scans never override it.
- Undo and Removed → Restore recover it. Explicit manual addition also clears that rejection.
- Hide from Memories is independent of removal: the activity, ordinary Gallery, and original
  Photos asset remain. Restore with Manage Photos → Show selected in Memories.
- Dismissing an activity's memory is reversible in Memories → Hidden memories.
- Anniversary cards use visible history within the activity scope, not temporary browse filters.
  An activity excluded only from totals can still be a personal memory.
- Anniversary dates use the device calendar/timezone. February 29 is not shown as “on this day”
  on February 28; same-year and future records never count. Empty days have an honest empty state.
- Map pins use available photo GPS only. Time-only associations get a strip, not inferred pins.
- These changes do not delete originals, order products, send notifications, or add semantic tags.

## Automated gate

`ETCH_PREVIEW=photo-memory` executes 26 checks against production Swift functions and reopens a
temporary on-disk store to verify persisted rejections and hiding. The PR iOS workflow runs it
alongside existing scope and reveal checks. Missing, incomplete, or failing reports fail the job.
Artifacts: `check-reports/photo-memory-report.txt` plus the existing reports.

## Device acceptance

1. Back up/preserve a store written before the photo-correction fields existed (any build
   up to and including b578); upgrade without reinstalling. Verify activities, covers, and
   original ordering survive the additive SwiftData migration. The disk-reopen unit check does
   **not** replace a historical-schema migration test.
2. Remove a cover, confirm the next photo remains usable, Undo, then bulk rescan and reopen the
   app. Repeat without Undo: the rejected match must stay removed.
3. Give two activities the same asset. Open the second activity's Gallery page and remove it.
   Verify only that association changes; share/cover/hide actions target the page's activity.
4. Remove the last photo in the viewer. Undo remains accessible. Restore multiple photos from
   Manage Photos → Removed; verify no duplicates and originals still exist in Apple Photos.
5. Hide a photo from Memories, then hide the activity's memory. Both have working restore paths.
6. Test an anniversary with photo access allowed, limited, revoked, and an iCloud-only/deleted
   photo. No never-ending image loader or misleading location should be shown.
7. Change browse filters and activity scope. Memories ignore the former and honor the latter.
   Check foregrounding after midnight and a timezone change.
8. Open a photo map with geotagged and time-only photos. Only genuine available coordinates have
   pins. Open, swipe, remove, and return; removed pins/strip items update.
9. Check compact iPhone and accessibility text sizes, especially the photo action bar and batch
   buttons. Verify VoiceOver announces activity ownership and selection state.

## Next increments

Whole-history clustered photo maps; a clearly labeled week-in-history fallback; trip/month
collections; confidence-ranked suggestions and matching against route segments instead of bounding
boxes. Keep these separate from this release so matching accuracy and correction persistence are
established first.
