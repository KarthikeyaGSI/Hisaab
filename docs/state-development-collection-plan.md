# State development evidence: two-year collection

Owner scope update, 12 October 2026. Collect FY 2025–26 and FY 2026–27 to the source's stated cutoff, in the owner's order from Andhra Pradesh through West Bengal. Preserve earlier holdings; the active acquisition scope is two years. Complete project cards are no longer a prerequisite for collecting useful information.

For each state, research and collect official budget volumes and departmental allocations; monthly/provisional/annual expenditure; projects and sanctions; procurement notices and awarded contracts; agency, contractor and dated documented official/representative roles; project progress and completion where available. Keep maintenance and mixed operating expenditure identifiable. A legislature directory establishes membership, not responsibility for a particular work.

Financial stages remain distinct: budget estimate, revised estimate, release, booked expenditure, reported utilisation, tender estimate, awarded contract and recorded payment. State expenditure may include Union grants; do not add the same transfer again. Department and project children explain a parent total rather than supplementing it. Current-year actual spending is to-date, not a full-year figure. A 2026–27 budget frequently contains 2024–25 actuals and 2025–26 estimates; those are never relabelled as 2025–26 actuals.

The source-discovery and preservation pass is bounded and checkpointed. The initial four-linked-report pass is followed by a deeper pass of up to twenty source-observed PDFs at each selected year-specific budget index; generic portals retain the smaller bound. This preserves departmental/sector originals while avoiding guessed routes or unlimited requests. An original is useful even when only partial fields are extractable. Keep unknown units, inaccessible pages, scanned columns, wrong-year editions, missing award dates and conflicting table totals in the ledger. Public accessibility does not approve republication. Original sources and extracted candidate data remain private until the existing source/evidence/MFA review passes.

Collection entry point: `workers/state_development_collection.py`, using the observed public source inventory in `data/state-development-sources.json`. The private override and per-state originals/extractions/checkpoints are in ignored `data/acquisition/state-development/` and `data/originals/state-development/`. The non-sensitive progress summary is `data/state-development-acquisition.json` and Spending → Evidence progress. Default reruns reuse unchanged URL/hash checkpoints. Explicit `--refresh-indexes` checks for newly listed reports while retaining previous index editions and original hashes; it does not approve changed amounts. Source-table candidates require their own edition reconciliation.

Validation gates:

1. Preserve exact original bytes, URL, retrieval time, source kind and SHA-256. Check actual document headings and columns rather than trusting a filename or landing-page title.
2. Where available, connect work, sanction, contract, bill and payment registers using official IDs. Missing connections do not block collecting or showing separately reviewed facts at their actual scope.
3. Establish an official denominator and reconcile one authority/year before claiming complete coverage. A first source pass through all states is not complete statewide collection.

No new email recipient, RTI filing/fee, paid access, automatic approval, deployment or access-control bypass is authorized by this collection scope. Blocked routes are checkpointed while independent public-source work continues.
