# Cinematic asset cards — 18 October 2026

Implemented one shared Obsidian-inspired receipt system for selected project and historical-location records. No per-asset card generation, manual image assignment, database publication or fictional project facts are required.

## Selection and geography

AtlasMap focuses the recorded coordinate with the shared bounded-pitch camera. AssetMapConnection projects that same coordinate into a screen-space leader line that follows map rendering and the card entrance/resize. The connector hides when the anchor is offscreen or covered by the card. A shared Three.js ring highlights a point. Existing road/line geometry is highlighted directly; Polygon/MultiPolygon geometry or a supplied buildingFootprint can be filled/outlined. Coordinates do not infer a building or campus boundary. Current historical assets still have no verified building footprints.

## Header image precedence

AssetVisual uses the first source-photo media record when supplied by a reviewed project or asset response. It retains the photo caption and source link. A failed photo falls back to the map preview; failure is keyed by asset identity and photo URL so a rapid image-error event cannot be overwritten by a reset effect.

useLocationPreview captures only the selected location, in the browser, from a rendered map frame after camera motion and tile loading. It crops the current map around that coordinate to a 720×400 JPEG and retains attribution. It does not enable preserveDrawingBuffer, spin a second map or call a new paid imagery API. Blank/placeholder frames are rejected; a bounded timeout reports unavailable rather than freezing a blank terrain texture. Nothing is uploaded or stored as source evidence. The preview is explicitly labelled Map context, with a building-identity warning and visible Mapbox/source attribution. It is contextual imagery, not a site photograph, a verified building identity or proof of development.

## Card and themes

Compact amount rows distinguish sanction, contract and payments. Missing values remain em dashes with Funding not linked and explicit evidence labels. Existing payment/source/role/reports functionality remains available. Primary source and issue actions stay visible as the card scrolls. The mobile card is a scrollable bottom sheet with an expand/collapse handle. Dark is the selected design default; a header sun/moon button changes day/dark surfaces and map lighting, and saves the preference locally. Reduced-motion, reduced-transparency and increased-contrast preferences are supported.

No funding record, project, person, photograph or amount was fabricated or approved. Live publication remains unchanged. Browser-only fixtures exist solely in tests.

## Validation

112 application tests and TypeScript checks pass. Four desktop/mobile browser checks cover source-photo priority, broken-photo fallback, unknown financial values, theme persistence, demo complaint warning, captured map context and a connector endpoint that moves with a pan. Real point and road locations were also checked with reduced motion. QA images are in output/qa/asset-card. A final map stress pass also checks terrain/style transitions; its detailed result is saved separately in output/qa/map-stability/browser-results.json.

The stress run reproduced the earlier Mapbox sprite-atlas null-width worker error during rapid style transitions. Basemap updates now wait for the current style, camera and tile work to be idle, keeping only the latest requested style. This does not use private Mapbox internals or suppress worker errors. Source policy references: https://docs.mapbox.com/mapbox-gl-js/api/map/ and https://docs.mapbox.com/help/dive-deeper/attribution/ .

Final repeat: desktop, repeated desktop and mobile map checks each confirmed both actual basemap selections, terrain toggles, pitch, pan and return to flat with zero page errors and no failed HTTP responses. Card and real road checks pass with reduced motion. Full shared-card UI tests passed on both desktop and mobile after correcting the failed-photo reset race and blank terrain-frame capture. The expanded mobile sheet was checked at 599px height in an 844px viewport.

Final production verification: hosted-environment Webpack production build completed successfully; no data publication or deployment was performed.
