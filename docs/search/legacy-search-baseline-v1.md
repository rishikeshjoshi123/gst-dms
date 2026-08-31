# Legacy Search Baseline v1

**Evaluation corpus:** `search-evaluation-v1` in `scripts/search/evaluate-legacy-search-baseline.ts`
**Recorded from:** `src/lib/actions/search.ts` on 2026-09-01
**Purpose:** frozen, offline acceptance fixture and synthetic legacy-contract model for the approved Search rebuild; it is neither a production query log nor a migration/cutover.

## What the legacy action does

`searchAll(query, semantic = false)` returns an empty list for trimmed queries shorter than two characters or when no current organisation is available. For other queries it runs organisation-scoped, active, non-deleted `ilike` lookups (each limited to ten rows) over client name/GSTIN, matter title/code, and document display title/storage path/reference number, then returns navigation items in client, matter, document order.

When explicitly passed `semantic = true`, it best-effort embeds the query with `RETRIEVAL_QUERY`, records usage after an embedding is returned, calls `match_all_documents_v2` with the current organisation and embedding model/version, fetches matching active documents, and appends missing documents after lexical matches. Provider or vector errors are caught and lexical lookup continues. The default caller path does not enable this branch.

`LEGACY_CONTRACT_RECORD` and `runLegacySearch` model those rules over synthetic rows: minimum length, absent-current-organisation handling, tenant/active/deleted filtering, per-kind ten-row caps, lexical ordering, default-disabled semantic behavior, a no-embedding lexical fallback without usage logging, a post-embedding RPC/fetch failure fallback with usage logging, and a five-document vector candidate cap before active-document append/deduplication. This is an offline behavioral model, **not** captured production/DB results and not a substitute for future RLS/runtime QA.

## Explicit legacy limitations

The legacy record asserts only the modeled legacy cases above. The legacy action has no typed intent, legal-reference normalisation, full-text passage retrieval, amount/date/FY comparisons, page citation, metadata-only availability contract, scoped workspace, reciprocal-rank fusion, or result-level non-disclosure proof. The corpus’s `expected.resultIds` therefore describes the approved **future target** and is kept distinct from `LEGACY_CONTRACT_RECORD`; it must never be reported as current legacy behavior.

The corpus uses opaque synthetic IDs and no legal text, names, valid personal identifiers, filenames from clients, credentials, or external calls. `isolation` cases require a zero-result response and prohibit disclosure of a denied title, filename, snippet, count, vector, or existence signal. Numeric labels exercise paise-safe boundaries and Indian units; their fixture values are decimal integer paise strings (`139999999`, `140000000`, and `140000001`), so later implementations must not use JavaScript floating point.

## Running the baseline validator

`npx tsx scripts/search/evaluate-legacy-search-baseline.ts`

The validator is deliberately offline. It verifies the legacy model record, corpus versioning, at least 100 unique cases, allowed source/constraint shapes, all required coverage categories, source-derived target candidates, integer-paise ranges, date/FY ranges, expected-result references and tenant consistency, and a public isolation output with only IDs (no count or details). Mutation checks prove that duplicate denied IDs, unknown tenants, local denied references, missing source-derived expected results, and missing sources fail validation. Cross-tenant assertions model the required no-disclosure shape only; runtime RLS remains future QA.
