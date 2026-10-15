# State development evidence — continuation methods

Scope is FY2025–26 and FY2026–27 to explicit source cutoffs. Source fiscal columns are private candidates, not unique schemes, payments, or publication approvals.

## Repeatable collection

`workers/state_development_collection.py` preserves original response bytes/checksums, source links, edition hints and failures. A budget index can select at most twenty observed PDF links per request. `linkedReportOffset` advances to subsequent stable link ranks; it does not silently stop the source inventory at twenty. Paths containing spaces are encoded, and PDF downloads with a trailing document identifier are validated as PDFs. HTML error responses are not financial evidence.

`workers/state_development_inventory.py` records every observed same-host or permitted official-storage PDF link in saved budget indices. Older/unrelated documents remain marked as fiscal membership unverified. Its counts are an observed-link backlog, not a census of missing current-year government publications.

`workers/state_development_full_text.py` resumes local extraction in batches of at most 250 pages for AP and Haryana demand books. The saved supplement is tied to the original checksum; extraction never changes original bytes. Complete text processing does not mean complete financial review.

`workers/state_development_hp_reports.py` uses the observed anonymous report form, its selected fiscal year and its explicit viewer result. Only the reviewed official host is accepted. No private analytics, authentication, guessed report API or CAPTCHA bypass is used. Failed reports stay unavailable.

## Scans and legacy text

English scan OCR uses local Apple Vision through the existing Swift collector; bundled Python needs pdfplumber. The Tamil Nadu AFS has 42 OCR-processed pages but only nine visually transcribed revenue heads in this continuation. A newer website heading never changes an older source cover year.

Hindi/English OCR uses an isolated Tesseract.js **7.0.0** runtime under the ignored private acquisition folder. Install there with `npm install --prefix data/acquisition/state-development/ocr-runtime --save-exact --ignore-scripts --no-audit --no-fund tesseract.js@7.0.0`. App dependencies are unchanged. The wrapper recognizes private local page images; only language/runtime models are downloaded. Recognition quality is insufficient for automatic monetary acceptance on the inspected Chhattisgarh scans. Native numeric PDF cells are used where available, and legacy-language labels remain unresolved.

## Source-specific normalization

`workers/state_development_programme_tables.py` documents each accepted source layout and unit. AP is lakh; Haryana absolute rupees; Assam and Himachal lakh; Chhattisgarh and Maharashtra targeted outlays thousand; Karnataka regional portions crore; Goa lakh; Tamil Nadu inspected heads thousand. Original/revised estimates remain alternatives. Previous-year actuals are excluded when outside the requested scope. Empty cells remain unknown; negative adjustments remain negative. Beneficiary counts, geographical components and targeted subsets are not added as extra money.

`workers/state_development_remaining_tables.py` retains Meghalaya voted/charged rows only under an explicitly unfunded parent in the same physical table; it does not count that placeholder parent or attach an unanchored child.

`workers/state_development_reconcile.py` preserves printed differences. A rounding bound is explanatory context only, never a correction or approval. Missing Manipur capital components are not filled by subtracting other tables. Jharkhand's overview needs an official monetary-unit definition before normalization.

Classification suggestions and source-local accounting paths support owner review. They do not establish source reuse permission, unique programme identity, exact project geography or a bill-to-project allocation. All originals, OCR and newly normalized monetary evidence remain private. No automatic publication or relaxed MFA is introduced.

## Refresh order

Run source retrieval/checkpointing first, then wait for it to finish. Complete local text/OCR batches and inspect originals before adapting numeric layouts. Run normalization to completion before reconciliation, classification and the public count summary. Update the in-app progress tasks and current-status document from that coherent summary. Verify checksums and parser/application tests before committing. Do not run dependent summaries against a partially rewritten normalized catalogue.

The current state list and unresolved source/review work are in `docs/state-development-current-status.md`. This method does not claim all28 states complete, or complete national contractor-payment coverage.
