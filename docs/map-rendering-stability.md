# Map rendering stability — 18 October 2026

## Failure and repair

The atlas previously combined a terrain-draped opaque outside-country fill with a separate CSS path recomputed on move/resize. Draped fills and screen clipping use different rendering paths. Behind-camera project() coordinates may be MAX_VALUE; direct conversion into a CSS path can create enormous triangles and shapes. Terrain/style frames could also arrive without another move event. The country border contained 30,825 vertices projected on each movement callback.

The outside layer remains as a transparent query/order anchor, preserving existing feature selection and layer identifiers. It no longer paints the dark terrain silhouette. A non-drawing custom map layer updates the CSS silhouette with the exact rendered camera matrix. The pure projection helper clips camera-space geometry against the near plane and viewport before perspective division, retains island/hole subpaths, simplifies subpixel segments and avoids unchanged CSS writes. It never triggers its own repaint loop. The canvas is hidden until its boundary is available; boundary failure reports an error rather than exposing the world view.

Satellite/street changes now update the basemap import instead of replacing the whole serialized root style, retaining evidence sources and custom layers. Pitch is bounded at 55 degrees. Removed the whole-map CSS drop-shadow compositor filter. While a selected asset is loading, state-fit no longer competes with its eventual site fly-to. Raised the source-location halo two metres above terrain to avoid a coplanar surface flicker. No building footprint or payment fact is invented.

## Verification

112 application tests pass, including three camera-space clipping regressions (surrounding viewport, crossing behind the camera, island/hole and entirely hidden boundaries); TypeScript and diff whitespace checks pass.

Real Chrome checks: desktop, repeated desktop and mobile each exercise flat, pitched, zoom/pan, terrain off, streets, satellite, terrain on and return to flat. Final repeated checks report no page errors and no failed HTTP requests. A separate check opens the actual Panchayat HQ source record, switches basemap and terrain repeatedly with the Three.js halo active, and retains its card without page errors. Screenshots and structured results are in output/qa/map-stability. Reproduce with node scripts/check-map-stability.mjs while the local server is running and Chrome is installed.

An earlier live-development run emitted one intermittent Mapbox null-width rendering error; it did not recur in a clean rerun, three repeated device checks or the selected-asset check. This is recorded rather than claiming an unreproduced error is definitively fixed. External imagery/network speed and GPU/browser differences still affect recording. This check is not a guarantee of identical frame timing on every device. No production build was run for this change; source compilation/type checking and browser verification were used.
