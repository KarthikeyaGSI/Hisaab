# Hisaab design direction — concept 01

Prepared 4 October 2026. Status: proposed for Adiram's review. No product implementation has started.

## Recommendation

Use MapLibre GL JS for the map, a custom Hisaab cartographic style, and a replaceable tile provider. MapTiler is the leading managed-provider candidate; OpenFreeMap is the candidate for a prototype without a map account or usage bill. Choose the production provider only after checking Indian city/village labels, local scripts, attribution, boundary presentation, imagery, actual load performance and cost.

Add deck.gl only for layers that need it. Add Three.js only for a specific geographic 3D scene or object that the normal map layers cannot express. GeoLibre is a useful visual reference and potential internal GIS exploration tool; its full GIS workspace is not the proposed citizen interface.

Map engine, basemap data, administrative boundaries and public-work evidence are separate systems. A beautiful basemap does not supply official work locations or spending coverage.

## Visual direction

- Light default: ivory land, pale mineral-blue water, subdued sage terrain, navy text, cobalt action colour.
- The map fills most of the viewport. A floating navigation bar, search control and contextual sheet sit above it.
- Frosted surfaces for small controls; near-solid readable surfaces for evidence, amounts and complaint forms.
- Rounded surfaces and restrained shadows; system typography; colour is always paired with a label or icon.
- Selected areas use fine blue outlines. Unavailable record coverage uses a neutral hatch, not a zero-value colour.
- Dark theme can follow the same hierarchy after the light direction is accepted.

## Interface and interaction

Desktop: national map, area search, year and money-stage filters, area summary, synchronized work list. Selecting a work keeps the map context and opens its evidence receipt.

Mobile: full map with a draggable bottom sheet. The sheet expands from an area summary to works and then a work receipt. Four primary destinations: Map, Works, Report, Track.

Navigation: country → state → district/local body → actual work when location evidence exists. Preserve the selected area and filters when opening or closing sources.

Motion: immediate press feedback; interruptible camera moves; restrained springs for sheets; finger-following drags. Offer reduced-motion transitions, opaque surfaces where needed and a list that remains usable without map rendering.

Data controls: separate sanction, contract and payment views; source/year coverage always available. Time comparisons require comparable records and a visible coverage change notice. Optional 3D view returns easily to flat 2D. Load detailed terrain, imagery or 3D only when selected.

## Work receipt and citizen action

Show title, purpose, original IDs, location precision, source dates, money stages, delivery evidence, authority roles, open questions and corrections. Each fact opens its exact source receipt.

An observation begins with dated evidence. A generated complaint remains reviewable and private. Local preparation, citizen-reported submission, official acknowledgement and verified resolution remain separate states.

The generated concept image contains illustrative values and schematic geography. It is a visual direction, not verified government data, authoritative boundaries or a performance-tested interface.

## Shortlist reviewed

- MapLibre: leading fit for a custom national data map.
- Mapbox: strong managed 2D/3D alternative with commercial service terms and usage pricing.
- CesiumJS: strongest candidate when a precise globe and streamed 3D geospatial scenes become central.
- Google Maps: candidate for familiar places and imagery; exact 3D coverage needs checking.
- ArcGIS: candidate when Esri services and GIS workflows become central.
- Leaflet: straightforward 2D map alternative.
- OpenLayers: strong general 2D GIS alternative.

These are fit judgments, not measured performance rankings. Test the leading providers on the same India views before a production commitment.

## References

- Apple design principles: https://github.com/emilkowalski/skills/blob/main/skills/apple-design/SKILL.md
- GeoLibre gallery: https://geolibre.app/gallery/
- GeoLibre engines: https://geolibre.app/user-guide/rendering-engines/
- MapLibre examples: https://maplibre.org/maplibre-gl-js/docs/examples/
- Three.js map integration: https://maplibre.org/maplibre-gl-js/docs/examples/add-a-3d-model-using-threejs/
- deck.gl: https://deck.gl/
- MapTiler maps: https://www.maptiler.com/maps/
- MapTiler pricing: https://www.maptiler.com/cloud/pricing/
- OpenFreeMap: https://openfreemap.org/
- Mapbox: https://www.mapbox.com/maps
- Mapbox pricing: https://www.mapbox.com/pricing
- CesiumJS: https://cesium.com/platform/cesiumjs/
- Google 3D maps: https://developers.google.com/maps/documentation/javascript/3d/overview
- ArcGIS: https://developers.arcgis.com/javascript/latest/
- Leaflet: https://leafletjs.com/
- OpenLayers: https://openlayers.org/
