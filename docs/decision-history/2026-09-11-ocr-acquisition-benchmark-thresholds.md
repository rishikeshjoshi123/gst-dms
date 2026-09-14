# OCR acquisition benchmark thresholds and page eligibility

- **Decision / date:** `AI-ACQUISITION-BENCHMARK-THRESHOLDS-2026-09-03` resolved on **2026-09-11** by the user after reviewing the quality, safety, partial-indexing, latency, and cost consequences.
- **Canonical plans:** [AI Extraction, Provenance, and Model Lifecycle](../plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md#prompt-and-model-evaluation) and [Universal Search and Evidence Retrieval](../plans/features/2026-08-24-universal-search-and-evidence-retrieval.md).
- **Affected outcomes:** D12 acquisition/retrieval and D13 release integration. This record authorises documentation reconciliation only; it does not run a provider benchmark, backfill vectors, cut over Search, deploy, or accept an untested corpus.

## Approved benchmark gate

- The labelled benchmark contains 60–100 unique representative source pages with independent adjudication and the already approved exact Mumbai processor version.
- Every adjudicated GSTIN, official reference, date, amount, material table cell, and evidence anchor must pass exactly. A failed or unknown critical check fails the gate; no aggregate confidence score may conceal it.
- Native/OCR routing requires `100%` recall and at least `90%` precision. Missing a page that needs OCR is not acceptable; limited unnecessary OCR is tolerated because it is safer than silently accepting unusable native text.
- Across all adjudicated OCR pages, mean character accuracy must be at least `98%` and mean word accuracy at least `95%`, with no missing quality label. Hindi, mixed-language, handwriting, poor-scan, table, stamp, and rotation results remain separately visible.
- Mean acquisition latency must be no greater than `10` seconds per source page, and a normal bounded 100-page acquisition must complete within `20` minutes.
- OCR charges must be no greater than `USD 0.01` per billed page or `USD 1.00` for a fully OCR-processed 100-page document, excluding tax and currency conversion. The ceiling applies to the OCR acquisition measured here, not Gemini metadata extraction, embeddings, Storage, or human work. Provider price and billed features must be rechecked at implementation and release time; exceeding the ceiling pauses rollout for explicit tuning or budget review rather than silently disabling pages.

## Page, field, and indexing disposition

- An accepted native page or qualifying OCR page may supply canonical page chunks and embeddings only after its current immutable document-version checks and the remaining Search rollout gates pass.
- A page with unreliable transcription, critical evidence, table structure, or source anchors is excluded from page-body vector indexing and sent to safe retry/reacquisition or disclosed as `source_unreadable`/`metadata_only`. Other reliable pages are not blocked.
- Human Review is ordinarily field-level: the reviewer compares the rendered source and accepts, corrects, rejects, or clears a structured candidate such as a GSTIN, reference, date, or amount. That decision may make the corrected effective metadata eligible for structured search, but it does not certify the rest of the OCR transcript.
- A failed page does not later enter page-body vectors merely because one field was approved. Its body becomes eligible only after successful reacquisition or an explicitly implemented, provenance-bearing whole-page transcript-verification workflow. No such future workflow is implied or implemented by this decision.
- A latency or cost failure blocks benchmark promotion for operational remediation; it does not invalidate otherwise accurate page text. Existing exact, full-text, structured, and active legacy search remain available until the page-aware index passes and cuts over safely.

## Implementation impact

The current evidence harness reports structural completeness but does not enforce this approved quality gate or all page/field dispositions. The next D12 tranche must extend the report, create the external adjudicated manifest, run the authorised corpus, preserve content-safe evidence, and verify partial indexing, retries, metadata-only/unreadable handling, field Review separation, relevance, citation, rollback, and release behavior. Application implementation and provider execution were not started by this discussion.
