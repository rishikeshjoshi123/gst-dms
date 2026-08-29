---
title: AI Extraction, Provenance, and Model Lifecycle
status: in-progress
created: 2026-08-24
updated: 2026-08-30
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ./2026-08-24-document-record-and-file-lifecycle.md
  - ../features/2026-08-24-universal-search-and-evidence-retrieval.md
  - ../features/2026-08-25-document-hub-ingestion-and-workbench.md
---

# AI Extraction, Provenance, and Model Lifecycle

## Summary

Make CaseChain AI output source-grounded, schema-validated, field-addressable, versioned, measurable, and replaceable without corrupting canonical legal data or search indexes. Continue using Vertex AI, retain Gemini 2.5 Flash for current multimodal PDF extraction, and migrate retrieval embeddings from legacy `text-embedding-004` to a versioned 768-dimensional `gemini-embedding-001` representation only through a measured side-by-side rollout.

An immutable asset-scoped source-analysis run produces source candidates with page/quotation evidence, including while a global Intake item has no matter or logical document. Placement binds that source analysis to the created document version and materializes document-level candidates without calling the model again. Domain validation determines whether a candidate is usable. Human decisions and corrections are append-only, remain authoritative across re-extraction, and feed an effective metadata projection. Deadlines, financial events, legal references, assignments, relationships, and Case Brief updates consume these provenance-bearing candidates rather than parsing `raw_metadata` independently.

## Context and Goals

The original AI implementation uses minimally specified prompts, TypeScript casts rather than runtime validation, one aggregate confidence score, weak page evidence, hardcoded model constants, and unversioned document vectors. Query and corpus text were embedded with the same task type, usage accounting treated character count as token count, and model pricing seeds were stale.

The first hardening pass introduced strict Zod and Vertex schemas, a GST-specific prompt, versioned embedding metadata, correct retrieval task types, and a matter reindex job. The read-only QA audit on 2026-08-24 confirmed compilation but found architectural and rollout gaps:

- the embedding migration reused the existing `00024` prefix and cannot be applied until assigned the next unique migration number;
- enriched deadlines, amounts, legal references, evidence, and document title are still stored only inside `raw_metadata` rather than normalized candidates/projections;
- application search selects only the new embedding version while existing vectors are labelled legacy, producing incomplete semantic results until backfill;
- mocked provider-contract tests and durable reindex progress are missing;
- current document-level embedding text cannot satisfy the planned page-aware legal/numeric Search scope and must remain transitional.

The target system must preserve source evidence and prior runs, prevent incompatible vectors from being compared, expose incomplete indexing honestly, and allow Google model changes without redesigning domain callers. Model upgrades must pass a frozen CaseChain GST evaluation rather than relying on catalogue freshness or price alone.

## Decisions

### Provider and model baseline

- Vertex AI remains the only production AI provider for this phase. Provider-neutral CaseChain interfaces remain so later provider changes do not alter domain services, but multi-provider runtime routing is out of scope.
- Use `gemini-2.5-flash` for PDF extraction and transitional Case Brief synthesis until a cheaper Google model passes the same frozen CaseChain evaluation thresholds.
- Use `gemini-embedding-001` at 768 output dimensions for the rebuilt retrieval index. Corpus inputs use `RETRIEVAL_DOCUMENT`; submitted user queries use `RETRIEVAL_QUERY`.
- Model, endpoint/region, dimensions, task type, safety settings, and effective pricing are versioned operational configuration. Domain rows record the effective model/version used.
- PDF content, OCR output, imported text, notes, and matter context are untrusted inputs. Prompts explicitly prohibit following instructions found inside source content.

### Schema and prompt contract

- Zod is the authoritative CaseChain runtime schema. Generate the provider response schema from the same contract through a tested compatibility adapter; do not maintain semantically independent handwritten schemas.
- Vertex structured generation requests set `responseMimeType: application/json` and provide the compatible response schema derived from the canonical Zod contract. Regex or substring extraction from conversational prose is not a supported canonical recovery path.
- The adapter removes or transforms constructs Vertex structured output does not support, and CI tests parity with representative payloads. A provider accepting JSON does not replace post-response Zod validation.
- Version prompt semantics, response schema, normalization rules, and document-type catalogue independently. Store every effective version on the extraction run.
- The document extraction contract includes source language and supported English translations while retaining original text; identity/classification; client identifiers, parties, issuer, direction, periods and financial years; relationships; normalized legal references; explicit deadlines; typed financial facts; and page/quotation evidence for each material candidate.
- Summaries and facts distinguish allegations, taxpayer submissions, authority/court findings, and final operative directions.
- Extract only source-supported facts. Do not calculate statutory limitation dates during extraction. Relative periods may be stored as unresolved textual candidates but never as calendar deadlines.
- Do not let the model perform uncertain aggregation. Preserve source-stated components and totals separately; domain validation may check arithmetic but does not invent a missing total.
- Keep quotations short and evidentiary. Before placement, source evidence binds to the immutable `file_asset_id`, page/OCR content version, and 1-based PDF page. When the analysis is bound to a document version, every user-facing evidence locator binds to the exact `document_version_id` and page from the File Lifecycle plan.

### Append-only extraction and candidates

- `source_analysis_runs` is append-only and immutable-asset scoped. It stores request identity, source `file_asset`, page/OCR content version, model/prompt/schema/catalogue versions, state, validated payload or validation errors, safe provider metadata, token/billable usage, latency, and timestamps. It can run while the source is an unassigned Intake item.
- Raw provider output may be retained encrypted and access-restricted for audit/debugging subject to retention policy; ordinary application clients and platform metadata views cannot read it.
- A successful source run materializes field-addressable immutable rows in `source_field_candidates`. Each records field path/type, typed JSON value, source run/asset, page/quote/region evidence, confidence, validation state, and semantic key.
- Placement or later attachment creates a `document_version_analysis_binding` between the immutable source run and document version, then materializes document-level rows in `document_field_candidates` referencing that source candidate/binding. This permits an intentional same-organisation Copy to reuse source analysis while each logical document retains independent effective values and human decisions.
- Arrays such as parties, legal references, deadlines, financial events, and relationships use stable semantic candidate keys so re-extraction can compare the same fact without depending on array order.
- `document_field_decisions` is append-only. A decision accepts, corrects, rejects, or clears a candidate/field path and records actor, reason, replacement value where applicable, and timestamp.
- `document_effective_metadata` is a secured projection, not a second user-edited source. For each field it resolves the latest applicable human decision first, then an eligible automatically accepted candidate, and retains the winning provenance.
- Mirror approved high-use effective fields onto typed `documents` columns or a maintained projection for filtering and sorting. `raw_metadata` remains a temporary compatibility payload and is not the long-term query interface.
- Re-extraction never mutates a prior source run, source/document candidate, binding, or decision. It creates a comparison set. Existing human corrections remain effective until a human explicitly changes them.
- If a replacement PDF version becomes current, new candidates are evaluated against that version. Prior decisions carry forward only when their field/value remains applicable; otherwise Review receives a version-change comparison.

### Validation and acceptance policy

- Validation has three layers: provider response-schema guidance, strict Zod validation with unknown-key rejection, then deterministic domain validation and normalization.
- Domain validation covers real ISO dates, valid financial years, GSTIN/PAN syntax and checksum when available, non-negative INR values, page bounds, catalogue membership, relationship consistency, semantic deduplication, and allegation/finding qualification.
- Structurally invalid, truncated, or non-JSON responses write an `invalid_model_output` extraction attempt with safe errors and no candidates, effective metadata, or partial canonical domain writes. The raw response may be preserved only as access-restricted extraction evidence under retention policy; it never enters the outbox, ordinary application payloads, or operational logs.
- Transient transport, timeout, throttling, and provider 5xx failures may retry at most twice with capped exponential backoff and jitter, using the same run/document-version identity. Concurrency is smoothed through the shared dispatcher rather than creating an unbounded retry burst.
- Invalid model output receives at most one fresh controlled generation attempt. If that attempt is still invalid, the run enters `Review required` or an operator recovery state with a safe failure category; the system does not repeatedly ask the model until a parse happens.
- Domain-invalid candidates are retained for audit but cannot become effective. Material uncertainty or conflict creates a typed Review item with candidate and evidence.
- A response that is structurally valid but contains uncertain or contradictory fields does not fail the entire document. Valid fields become field-level candidates, while only the affected fields become provisional, conflicting, or Review-required according to the fixed acceptance policy.
- CaseChain uses **review by exception**, not approval of every extracted field. Valid extraction should reduce work rather than create a second data-entry pass.
- Tier A candidates apply automatically and remain editable: display title, language, document type, reference number, document date, issuer, direction, and financial year when structurally/domain-valid, page-evidenced, non-conflicting, and unopposed by a human decision. Automated acceptance is fully audited and can be sampled for quality review.
- Tier B candidates appear immediately as provisional facts without blocking the document: parties, legal references, stated monetary components, and exact calendar dates. They require human attention only when confidence/evidence is weak, validation fails, another source conflicts, or a consequential action depends on them.
- Tier C always requires an explicit decision before consequence: creating a client/matter, ambiguous placement, inferred/conflicting relationships, activating a deadline reminder, treating a financial event as verified current exposure/payment, or overriding a prior human value.
- Confidence alone never authorises automation. Candidate type, deterministic validation, evidence quality, conflicts, existing human decisions, and downstream consequence all participate in the fixed initial policy.
- Review groups related exceptions into one document-level decision flow with bulk accept/correct controls where safe; it does not create one queue row per harmless field.
- Human corrections remain authoritative. A later extraction can confirm them silently but cannot replace them; a genuine source-version conflict becomes one focused Review item.
- The initial automation policy is fixed and evaluated centrally. Organisation-configurable strictness is deferred until pilot evidence shows a real need, preventing inconsistent legal behavior between organisations.
- Exact cited relationships may auto-confirm only under the approved relationship policy. Extracted deadlines and financial facts may display provisionally, but reminder and verified-exposure consequences follow Tier C.
- AI never creates a client or matter without explicit user confirmation. It may provide a prefilled proposal and evidence.

### Prompt and model evaluation

- Maintain a versioned, anonymised, access-controlled GST evaluation corpus with adjudicated expected fields and evidence. Development fixtures contain no client secrets or production legal documents.
- The initial extraction gate contains at least 25 representative PDFs and at least 100 adjudicated material facts across SCN/DRC notices, replies, OIO/OIA, appeals, hearing/communication documents, multi-year records, poor scans, regional-language or mixed-language sources, multiple monetary figures, relative versus explicit deadlines, and adversarial embedded instructions.
- Record per-field precision/recall, document-type/classification accuracy, amount exactness, deadline exactness, legal-reference normalization, evidence-page/quotation accuracy, invalid-response rate, abstention, latency, tokens, and cost.
- No single aggregate score can hide a critical deadline, amount, GSTIN, or evidence regression. Maintain per-domain minimums and a critical-fixture zero-regression gate.
- A prompt/model/schema change runs in shadow against the frozen corpus. Promotion records evaluator, metrics, cost/latency comparison, rollout scope, and rollback version.
- Sample production-like runs may be manually reviewed only with authorised anonymised documents. Provider calls require an explicit evaluation run and usage record.

### Embedding and search-index lifecycle

- Every vector records provider, model, dimensions, task type, content hash, embedding version, source/extraction version, token usage, and created time.
- Never compare vectors from different model, version, or dimension spaces in one similarity query.
- Maintain an `embedding_index_versions` registry and per-organisation `organisation_search_index_state` with building, ready, active, rollback, coverage counts, failures, timestamps, and active version.
- An organisation continues querying its active legacy index while the new index builds. Do not switch application search to the new version merely because the migration exists.
- During cutover, new or changed searchable content is written to both active and building versions when required. Query embedding uses the organisation's active version.
- Cut over atomically per organisation only after all active sources are indexed or explicitly classified `metadata_only` or `source_unreadable`, evaluation passes, and rollback remains available.
- A later page-aware Search index replaces transitional whole-document vectors. The current enriched metadata-summary vector supports only limited navigation/summary matching and must not be presented as numeric, exact legal-evidence, or body-text search.
- Reindex work is organisation-orchestrated and matter/source-scoped, resumable, idempotent, rate-limited, and durably checkpointed. Operators can see counts and failures without document content.
- Embedding provider failure degrades to exact, full-text, and structured search. It does not make already indexed content unavailable.

### Usage, security, and observability

- Record provider-reported tokens and billable units. Character count is never stored as token usage.
- Pricing uses model, unit, currency, and effective-date configuration. Historical cost calculation uses the price effective at execution time.
- Logs use run IDs, safe error codes, model/version, stage, duration, and tenant-safe counts. Do not log PDFs, extracted legal text, prompts containing tenant content, raw responses, embeddings, access tokens, or signed URLs.
- RLS prevents tenant clients from reading another organisation's runs, candidates, decisions, vectors, evaluation samples, or usage. Platform operations sees metadata, usage, and health by default, not legal content.
- Retention and purge follow the asset, Intake, binding, and source document/version lifecycle. A source run may be deleted only when no surviving Intake/version/hold requires it. Human decisions and required audit metadata survive reprocessing and are deleted only through authorised retention workflow.

## Implementation Plan

### Completed: immutable source-analysis run and attempt foundation (2026-08-29)

- Migration `00063` establishes asset-scoped AI extraction run identity and append-only provider-attempt provenance while preserving the completed asset-validation worker contract. Run identity records versioned safe provider/model/prompt/schema/catalogue/normalizer metadata, idempotency, safe error category, usage/cost/latency, and same-asset supersession; it stores no raw model output or legal-content payload.
- The database enforces forced RLS with no direct browser or service-role table authority, immutable identities and terminal rows, tenant-scoped assets/runs/attempts, bounded/ordered retry reasons, and self/cycle/cross-asset/older supersession fences. An expired AI lease can only requeue through the controlled replay path and cannot terminal-complete stale work.
- A rollback-only acceptance fixture, generated type parity, clean local replay, existing processing-orchestration regression, type checking, and independent QA passed.

### Completed: immutable source-field candidate authority (2026-08-29)

- Migration `00064` adds asset-scoped `source_field_candidates` for terminal validated AI runs. Each candidate has a stable semantic key, field path/type, bounded typed scalar normalized value, 1-based validated PDF page, short quotation, optional normalized regions, confidence, and terminal validation state with safe error codes only.
- Candidate rows are append-only, source-run/asset/tenant constrained, idempotently materialized through a service-only command, and protected by forced RLS with no browser or direct service table authority. No document-version binding, effective metadata, raw-output retention, or consumer migration is included.
- A rollback-only candidate fixture, generated type parity, clean local replay, the source-run foundation regression, the processing-orchestration regression, migration checks, and type checking passed.

### Completed: immutable document-version analysis bindings (2026-08-29)

- Migration `00065` upgrades the earlier lifecycle binding table with logical-document identity and a service-only command that binds one validated extraction to an exact valid current or superseded document version, then materializes its existing source candidates without accepting model output or invoking a duplicate model call. Same-organisation logical copies may intentionally reuse immutable asset analysis while retaining independent bindings and candidate rows.
- Document candidates snapshot the source candidate's typed value and page/quotation evidence, enforce asset/page-count compatibility with the exact immutable version, and remain append-only. Binding/candidate tables use forced RLS with no browser or direct service table authority; later decisions and effective metadata remain out of scope.
- A rollback-only compatibility, idempotency, cross-tenant, historical-version/copy, immutability, and authority-surface fixture accompanies generated type parity.

### Completed: processing provenance write path (2026-08-29)

- Migration `00067` makes the existing processing worker persist validated extraction runs, attempts, source candidates, document-version bindings, and Review exceptions through the immutable provenance authorities. Provider output is validated before it can materialize candidates; structurally unsafe output reaches a safe terminal/recovery path rather than partial canonical writes.
- Completion is fenced to the owned processing lease and exact source/version identity. Typed service-only commands, generated types, and focused lifecycle/provenance fixtures cover terminal, replay, tenant, and safe-payload boundaries.

### Completed: effective-metadata Search consumer slice (2026-08-29)

- Migrations `00068`–`00073` introduce a service-only current-version effective-metadata reader and move the transitional Search-index worker and matter reindex path from ad hoc `raw_metadata` reads to that bounded projection. Corrected, cleared, rejected, and multi-financial-year values are represented without stale typed fallback.
- Transitional vectors are version- and projection-fenced: only active, non-deleted documents with an exact current valid version and matching `embedding_document_version_id` can match. Direct vector/provenance column writes are denied to both browser and service roles; only the fenced service commands may write them. A metadata change clears the old vector, queues one durable successor, and a projection fingerprint prevents an in-flight same-version worker from restoring stale content. Terminal `not_indexable` clears all vector provenance.
- Clean local migration replay through `00073`, focused SQL fixtures, TypeScript worker tests, type checking, targeted lint, generated-type parity, migration checks, and independent read-only QA passed. The active-legacy/multi-index Search rollout, coverage gates, and page-aware retrieval remain separate later plan work; this slice does not claim that cutover.

### Completed: effective-metadata inspector consumer slice (2026-08-30)

- Migrations `00075`–`00076` provide a service-only current inspector projection and an atomic current-winner correction command. The command locks the active exact current valid document version, verifies the winning candidate at commit time, and delegates to the append-only idempotent decision authority; browser and direct-table access remain denied.
- The production document-detail and Matter Timeline inspector callers, including desktop graph, mobile chronological list, and linked-document rows, now consume the current effective projection. Corrected values render; cleared, rejected, missing, stale, and cross-tenant values never revive legacy metadata. Tier-A and uniquely resolved financial-year values remain correctable; ambiguous financial years explicitly require Review. `tax_period`, relationship dialogs, and realtime refresh remain separate consumer work.
- Clean local migration replay through `00076`, focused SQL authority fixtures, generated type parity, targeted TypeScript tests, type checking, migration checks, and fresh independent QA passed. The slice does not claim live automatic assignment migration: `00074` remains a tested prerequisite until a production assignment caller adopts it.

### Completed: effective-metadata relationship-dialog consumer slice (2026-08-30)

- The live graph link-creation and link-deletion dialogs now receive the server-authorised current effective-metadata map from their `TimelineGraph` caller. Corrected type and reference values render; cleared, rejected, missing, or absent entries show only neutral structural identity and `Type unavailable`, never legacy metadata.
- The slice preserves the existing relationship mutation and authorisation commands. It does not claim realtime freshness or relationship inference migration.
- Focused dialog/caller tests, TypeScript checking, diff validation, and fresh independent QA passed. Existing shared dialog/select accessibility debt and authenticated-browser-fixture limits are recorded baseline/environmental limits rather than hidden by this slice.

### Canonical next action

Implement the next smallest approved high-use relationship consumer slice: migrate the live relationship re-evaluation path from legacy `raw_metadata` parsing to typed current effective relationship/reference values, while preserving its additive and non-destructive link behaviour. The automatic-assignment projection remains a prerequisite until a real assignment caller is connected. Preserve the completed transitional Search fence; do not implement index-version rollout, legacy-index cutover, page-aware retrieval, raw-output retention, or UI redesign in this tranche.

1. **Resolve the blocking migration defect.** Assign the embedding migration the next unused monotonically ordered prefix and add a CI migration-version uniqueness check before applying it anywhere. Do not apply the duplicate `00024` file.
2. **Freeze and test the canonical schema.** Make Zod authoritative, add the Vertex compatibility adapter, and add parity fixtures for valid, invalid, optional, unknown, array, enum, and null behavior.
3. **Add provider-contract tests and controlled failure handling.** Mock Vertex structured-generation and embedding responses to cover JSON MIME/schema configuration, strict parsing, unknown keys, malformed/non-JSON/truncated output, one controlled regeneration, capped transient retries with backoff/jitter, token statistics, dimensions, task type, safe restricted evidence, and content-safe logging. Keep these tests credit-free.
4. **Introduce append-only provenance storage.** Add asset-scoped source-analysis runs/candidates, document-version bindings, document candidates, field decisions, effective metadata projection/recompute, RLS, immutability constraints, semantic candidate keys, and source locators.
5. **Migrate the processing write path.** Store the run first, validate, materialize candidates, run domain validation, create Review items for material issues, and recompute effective metadata. Transitional `raw_metadata` may dual-write until consumers migrate.
6. **Normalize high-use consumers.** Move assignment, inspector, legal references, deadlines, financials, relationships, and search indexing from ad hoc JSON parsing to typed candidates and effective projections.
7. **Complete prompt hardening.** Extend the current GST prompt to the finalized financial-event/per-candidate evidence contract, catalogue versioning, allegation/finding qualification, source-language preservation, and explicit relative-deadline abstention.
8. **Build the evaluation harness and corpus.** Provide anonymised fixture manifests, expected candidates/evidence, deterministic graders, human adjudication workflow, comparison report, and a secured live-evaluation command that records usage.
9. **Create index-version rollout state.** Add the version registry, per-organisation coverage/cutover/rollback state, durable checkpoints, dual-write control, and safe operational reporting.
10. **Backfill embeddings in shadow.** Reindex without changing the active search version. Verify coverage/relevance per organisation, then atomically cut over and monitor before retiring legacy vectors.
11. **Integrate File Lifecycle, Document Hub, and Search.** Key pre-placement page/OCR/extraction to immutable assets, bind it to immutable document versions on placement/attachment, key user-facing quotes/chunks to those versions, then replace transitional whole-document vectors with page-aware chunks.
12. **Contract legacy paths.** After candidate/effective consumers and search cutover are verified, stop writing legacy AI JSON/vector contracts and remove obsolete RPCs/columns in separate rollback-bounded migrations.

## Interfaces and Data Changes

### Extraction provider contract

```ts
type ExtractionRequest = {
  fileAssetId: string
  intakeItemId?: string
  sourceUri: string
  mimeType: 'application/pdf'
  modelConfigVersion: string
  promptVersion: string
  schemaVersion: string
  catalogueVersion: string
}

type ExtractionRunResult = {
  runId: string
  state: 'validated' | 'invalid_response' | 'provider_failed'
  candidateCount: number
  reviewItemIds: string[]
  usage: {
    inputTokens: number
    outputTokens: number
    billableUnits?: number
  }
}
```

### Core provenance storage

- `source_analysis_runs`: source asset and organisation; page/OCR content version; idempotency key; provider/model and prompt/schema/catalogue/normalizer versions; state; current attempt; validated payload reference; safe error category; usage/cost; latency; timestamps; and supersession.
- `source_analysis_attempts`: append-only provider/model/prompt/schema versions, provider request/run identity, start/end and latency, token/billable usage and cost, retry reason, failure category, and access-restricted raw-response evidence reference where retention permits. The outbox and ordinary logs never store the raw response.
- `source_field_candidates`: source run/asset/organisation; semantic key; field path/type; typed and normalized value; page/quote/region evidence; confidence; validation errors/state; timestamps.
- `document_version_analysis_bindings`: organisation/document/version/source run; binding reason and actor/time; compatibility and uniqueness constraints.
- `document_field_candidates`: binding/source candidate/document/version/organisation; semantic key; field path/type; applicable normalized value; validation/lifecycle state; timestamps.
- `document_field_decisions`: document/organisation; field path/semantic key; candidate; action (`accepted`, `corrected`, `rejected`, `cleared`); optional replacement; actor/reason/time. Rows are append-only.
- `document_effective_metadata`: secured winning-value/provenance projection. High-use scalar fields mirror to typed columns through one recompute boundary.
- `embedding_index_versions`: provider/model/dimensions/task configuration, status, evaluation reference, and lifecycle timestamps.
- `organisation_search_index_state`: active/building/rollback versions, expected/indexed/failed/unindexable counts, state, checkpoint, and cutover timestamps.

### Candidate provenance

```ts
type SourceEvidenceLocator = {
  source:
    | { kind: 'file_asset'; fileAssetId: string; contentVersion: string }
    | { kind: 'document_version'; documentVersionId: string }
  pageIndex: number
  quote: string
  regions?: Array<{ x: number; y: number; width: number; height: number }>
}

type CandidateState =
  | 'eligible'
  | 'provisional'
  | 'conflicting'
  | 'invalid'
  | 'accepted'
  | 'rejected'
  | 'superseded'
```

Domain-specific deadline, financial, relationship, and legal-reference schemas are referenced by candidate type and owned by their domain plans.

### Embedding provider contract

```ts
type EmbeddingTask = 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY'

type EmbeddingResult = {
  vector: number[]
  provider: 'vertex-ai'
  model: string
  version: string
  dimensions: number
  taskType: EmbeddingTask
  tokenCount: number
  truncated: false
}
```

The adapter rejects unexpected dimensions, missing token statistics where required, silent truncation, malformed predictions, and unsupported task types.

## Testing and Acceptance Criteria

- TypeScript compilation, repository unit tests, targeted lint for touched code, and migration uniqueness/schema-drift checks pass before application.
- Zod/provider-schema parity tests prove canonical fixtures accepted by provider guidance are accepted at runtime and unsupported or unknown shapes are rejected safely.
- Mocked provider tests cover document analysis, Case Brief generation, embedding shape/dimensions/tokens/task types, JSON MIME/schema configuration, provider failures, timeouts, throttling/5xx responses, malformed/non-JSON/truncated payloads, controlled regeneration, retry exhaustion, and content-safe logs without spending Vertex credits.
- Invalid structural output writes an `invalid_model_output` attempt and no candidate/effective metadata or partial domain effects. Only one fresh controlled generation follows invalid output; a second invalid result creates Review/recovery. Transient failures retry no more than twice with the same run/document-version identity and capped exponential backoff with jitter.
- Strict parsing does not use regex recovery. Unknown keys fail Zod validation, access-restricted raw evidence never leaks to outbox/logs/client payloads, and every attempt records provider/model/prompt/schema version, usage/cost, latency, and failure category.
- Structurally valid responses with isolated uncertain or contradictory values preserve valid candidates and route only the affected fields to provisional/conflicting/Review states. Domain-invalid candidates remain auditable but cannot become effective.
- Re-extraction preserves previous runs and human decisions. A conflicting new value creates Review and does not silently replace the effective value.
- A clean high-confidence document completes without requiring a field-by-field approval pass. Tier A auto-applies, Tier B remains visibly provisional where appropriate, and Review contains only exceptions or Tier C decisions.
- Deadline fixtures never produce an effective date from only a relative period. Amount fixtures preserve stated components/totals exactly in paise without uncertain aggregation.
- Intake evidence resolves against the authorised immutable asset/page. After binding, user-facing evidence locators resolve against the exact document version and reject out-of-bounds pages. Replacement tests preserve old citations, and assignment does not invoke a duplicate extraction call.
- Assignment, legal references, deadlines, financials, relationships, inspector, and search consumers no longer require arbitrary `raw_metadata` paths at cutover.
- Prompt-injection fixtures cannot alter the output contract, request external actions, expose secrets, or turn source instructions into system instructions.
- The frozen corpus meets approved per-domain thresholds with no critical regression. Every promoted version has metrics, cost/latency, approver, rollout, and rollback records.
- Query embeddings use `RETRIEVAL_QUERY`; corpus embeddings use `RETRIEVAL_DOCUMENT`; dimensions and model/version filters match stored vectors.
- Existing organisations continue using the complete active legacy index while the new index builds. No cutover occurs before coverage/evaluation gates; rollback restores the prior version without recomputation.
- Reindex resumes after timeout, reports per-organisation/matter progress, skips current content hashes, records actual usage, and never mixes vector versions.
- Cross-tenant tests deny runs, candidates, decisions, effective projections, embeddings, evaluation data, and usage through tables, RPCs, locators, and direct IDs.

## Assumptions

- Google continues to make the selected Vertex models available during migration; model identifiers remain configuration rather than domain constants.
- The existing strict schemas, prompt, and document-vector migration are transitional hardening, not the finished normalized provenance or page-aware Search architecture.
- An authorised anonymised corpus of at least 25 representative PDFs will be provided before live extraction quality is approved.
- PostgreSQL and Supabase remain the provenance and embedding store for the initial scale.

## Open Questions

None.
