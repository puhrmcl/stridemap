# Studio art and editor pass — b584

## Objective

Make Map, Gallery, Anthology and Lithograph feel like considered art products. Open directly into a finished starting composition, keep the artwork visible while editing, make decisions understandable, and make experimentation reversible.

## Changes and acceptance contracts

| Surface | Contract |
| --- | --- |
| Entry | The initial recommendation chooser is removed. A default, collection recipe or kept print opens directly in its editor. Map/Gallery switching and individual layouts remain available in Design. |
| All four editors | Design, Content and Personalize share a resizable tray, a paper-proportioned preview, full-screen inspection, labelled actions, and Undo/Redo. |
| Preview | Every editable value invalidates the render. Older asynchronous results cannot overwrite a newer edit. The last image can remain visible while updating, but Print and export stay disabled until the current image succeeds. A failed render offers Retry. |
| Map | New default compositions use an inset map; existing recipes retain their authored border choice. Layout thumbnails show complete print proportions. |
| Gallery | Feature and triptych secondary rows derive from available height, including landscape and print-band rendering. Photo assignment remains editable per frame. |
| Anthology | Actual composition thumbnails, selectable activity source, brand typography in the optional title block and margin caption, bounded title widths. |
| Lithograph | Editable title and dedication, inset geographic or photographic hero, aligned secondary totals, brand typography and shared city identity across the map and index. Same-name cities in different regions remain distinct. |
| Recovery | Undo/Redo retains at most 60 value snapshots and coalesces rapid edits. Photo-load failure has a retry path. A blank history does not produce an orderable empty Anthology or Lithograph. |

## Automated evidence

The PR workflow runs `ETCH_PREVIEW=studio-quality` against production Swift. Its 29 assertions cover history sequencing and bounds, render-affecting PosterConfig equality, Gallery geometry, title fitting, location identity and empty/output renderer behavior. Existing scope-rule, photo-memory, reveal-diagnostic and smart-layout checks remain enabled. Missing, incomplete or failing reports fail CI.

The screenshot job captures direct entry, all four editors, four full artwork proofs and accessibility-sized text. Proofs use the production rendering path and seeded activities. Harness photos are fixtures, not a buyer's photo library.

## Device acceptance still required

1. Open all four products from Studio. Confirm direct entry, reachable controls and uninterrupted access to Print and Done on a small phone.
2. Change layout, orientation, text, palette and photo assignment. Undo and Redo each change; repeat after switching editor sections.
3. Type quickly and drag a slider. Confirm only the final render lands and Print stays unavailable during an update or failure.
4. Inspect Gallery photo framing in portrait and landscape with real portrait, landscape and iCloud-only photos. Replace a Lithograph photo and test a failed load/retry.
5. Use VoiceOver and larger text to select tabs, adjust the tray, operate controls and inspect the artwork.
6. Follow the print handoff to size/finish selection, verifying the current title, proportions and artwork. Compare a full-resolution print proof before any production order.

Unsigned CI compilation and fixture screenshots do not prove a signed TestFlight build, real Photos behavior or physical print quality. Route provenance and the existing print-engine band-consistency issue remain separate commerce-release work; this pass does not change fulfillment or pricing.
