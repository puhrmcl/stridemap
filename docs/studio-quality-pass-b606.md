# Studio quality pass — b606

Implemented against f564203e20b2435a40dbbab458b922ef9ccffd16 after the September 2026 Studio review.

## Delivered
- Resolve Nameplate's effective data placement once in the renderer request. Measurement, panels, image export, banded print export and composition use it. Landscape no longer measures a stacked composition as a side column.
- Honor requested map pixel resolution through snapshot and route compositing. Keep the logical camera/line styling stable; cap the longest raster edge at 5000 pixels. High-resolution panels are not retained in the thumbnail cache.
- Strict Studio maps omit their baked-in panel credit only when the composition provides a sheet-level footer. All standalone/default panels retain attribution. The whole artwork fits uniformly above the footer, preserving output aspect and keeping the credit out of crops. Printed OSM credit includes its source URL.
- Map Photo multi-image frames use explicit widths, preventing intrinsic image sizes from overflowing the landscape sidebar. New configurations start with one photo; saved selections remain unchanged.
- Larger layout previews and descriptions distinguish deliberately minimal layouts from layouts with results.
- Eight additional simulator checks, including Vision recognition of the title and finish-time label in actual landscape Nameplate renders at both supported aspects. Added network-backed landscape map/photo proof captures.

## Still required before a premium physical launch
This is a rendering/editor patch, not a claim that the full offering is now a $200 finished piece.
- Inspect the new CI proof images and TestFlight interaction, then order physical samples at small and large sizes: frame, glazing, paper, trim, route sharpness, photo crops and packaging.
- Audit raster DPI at the actual panel's physical dimensions. A 5000-pixel source is not 300 DPI at every offered size; routes on basemaps share that raster ceiling.
- Finish a consistent product/proof flow for Map, Gallery, Anthology and Lithograph. This pass changes the shared Map/Gallery editor, not every multi-activity renderer.
- Complete source manifests and point-of-sale/packaging attribution. Existing terrain/imagery source strings are not a completed global licensing audit.
- Commercial elevation fetching needs review: the current Open-Meteo free endpoint is described as noncommercial. Do not infer commercial clearance from attribution alone.
- Carry route provenance into physical-sale eligibility; resolve the separate banded-print consistency issue before production orders.

## Design direction
Keep the current MapLibre/Protomaps stack while validating its corrected output. A provider migration has not been justified by the observed defects.

Make three strong product compositions legible to buyers: route/achievement; one photograph with supporting map; restrained story with photos and caption. Preserve explicit user choices and saved designs. Before further template expansion, improve the exact final proof, crop controls, material presentation and fulfilled sample quality.

Competitor benchmarks, storefront observations (not equivalent framed-size quotes):
- Trackstar: https://www.trackstar.art/products/cim — Details / Photo / Frame & Size / Review; result lookup, photo personalization, archival material positioning.
- Run Ink: https://www.runink.net/products/custom-marathon-map — personalized race details, recognizable map art and emailed proof.
- Map Medal: https://mapmedal.com/products/custom-poster-send-your-event-info — photo/route storytelling and approval before production.
- Mapiful: https://www.mapiful.com/us/our-customizable-street-map-prints/ — focused place/text/color customization and decor presentation.

Source requirements verified September 2026:
- https://osmfoundation.org/wiki/Licence/Attribution_Guidelines — legible credit and printed source URL; merchandise also needs point-of-sale and packaging attribution.
- https://open-meteo.com/en/terms — distinguish API service usage terms from data attribution.
