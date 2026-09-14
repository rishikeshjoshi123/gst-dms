---
title: AI Extraction, Provenance, and Model Lifecycle
status: in-progress
created: 2026-08-24
updated: 2026-09-14
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

## Reading guide

Use the [shared reading rules](../../README.md#reading-a-large-plan). Read the scope/security links first, then relevant operations and their interfaces/acceptance. Expand dependencies when needed; recorded checkpoints require current-code reconciliation.

- **Read first:** [Quality gates](#review-to-delivery-quality-evidence) · [Release scope](#design-partner-intelligence-boundary) · [Usage and security](#usage-security-and-observability).
- **Source and extraction:** [Provider baseline](#provider-and-model-baseline) · [Acquisition and language](#page-content-acquisition-and-language-authority) · [Schema](#schema-and-prompt-contract) · [Candidates](#append-only-extraction-and-candidates).
- **Validation and retrieval:** [Acceptance policy](#validation-and-acceptance-policy) · [Evaluation](#prompt-and-model-evaluation) · [Index lifecycle](#embedding-and-search-index-lifecycle) · [Recorded next action](#canonical-next-action).
- **Checks and contracts:** [Interfaces](#interfaces-and-data-changes) · [Acceptance](#testing-and-acceptance-criteria) · [Assumptions](#assumptions) · [Open questions](#open-questions).

## Summary

Make CaseChain AI output source-grounded, schema-validated, field-addressable, versioned, measurable, and replaceable without corrupting canonical legal data or search indexes. Acquire authoritative page text through deterministic native-PDF extraction plus selective Google Document AI Enterprise OCR, use Gemini only for structured GST/legal metadata extraction, and migrate retrieval embeddings from legacy `text-embedding-004` to a versioned 768-dimensional multilingual `gemini-embedding-001` representation only through a measured side-by-side rollout.

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

### Review-to-delivery quality evidence

- [D12](../../delivery-ledger.md) distinguishes a working evaluation harness or provider diagnostic from corpus acceptance. Resolve the recorded OCR thresholds and run only the authorized labelled corpus before Search cutover; do not infer quality from source tests, model confidence or a small successful smoke call.
- Report native/OCR routing, exact critical-field errors, page/region/table correctness, failures, latency and provider usage separately. Also measure human correction/placement effort and retain difficult cases as regression fixtures. A passing sample is not a zero-error promise for future documents.
- Preserve immutable source/version and human-decision identity through consumers. Historical source views must not silently present current effective metadata as an interpretation of that older PDF. This integrity work remains required while replacement UI and Brief generation are deferred.

### Design-partner intelligence boundary

- The first production release has no agents, autonomous legal workflows,
  generated answers, workspace-wide memory, Note/chat distillation, or
  system-wide context assembly.
- Source-grounded PDF metadata extraction and its efficient human-reviewed candidate/provenance workflow are mandatory for the October release. The ordinary journey is AI extraction followed by review-by-exception; a workflow that normally requires lawyers to hand-type each PDF's metadata does not pass product or release acceptance. Extraction must pass the approved acquisition/extraction gates. Manual metadata entry/correction, manual placement and human-confirmed relationship creation remain exceptional recovery/repair paths for provider failure, unreadable pages and incorrect candidates, not the expected throughput path.
- Embeddings serve only the Search plan's cited, matter-scoped retrieval over meaningful chunks from current PDF versions; they are derived indexes, not facts or memory. That cited retrieval consumer is conditional and may be cut without disabling mandatory extraction.
- Case Brief generation/automatic refresh, agent tools, and additional embedding families remain disabled for the design-partner release. Case Brief cannot be enabled later until its required product rethink revises the owning plan; retrieval quality alone is insufficient. Other later intelligence still requires its owning rollout gate plus measured retrieval quality, citation coverage, provider cost and human-control evidence.

### Provider and model baseline

- Google Cloud remains the production document-intelligence boundary for this phase: local deterministic PDF parsing supplies native text, Google Document AI Enterprise OCR supplies selective scanned-page OCR, and Vertex AI supplies structured legal extraction and embeddings. Provider-neutral CaseChain interfaces remain so later provider changes do not alter domain services, but general multi-provider runtime routing is out of scope.
- Use `gemini-2.5-flash` only for source-grounded GST/legal metadata extraction from the immutable PDF. It must not create the canonical page transcript or return `page_text`, OCR words, or a replacement OCR layer. No Case Brief model call or latent synthesis configuration is enabled until the required Case Brief rethink approves a new contract.
- Retain `gemini-2.5-flash` as the first-release extraction baseline while its budget and quality gates hold. A later switch to another vision-capable model/provider requires separately billed API access, provider/privacy and India-processing review, strict schema/structured-output compatibility, representative quality/latency/cost comparison, version pinning and rollback; development-agent model access is not application inference capacity.
- Use a pretrained Google Document AI Enterprise `OCR_PROCESSOR` only for pages rejected by the versioned native-text quality gate. No custom extractor, labelled training set, or prompt-driven OCR is required for the initial page-acquisition contract.
- For the bounded design-partner production release, pin the Mumbai processor to exact version `pretrained-ocr-v2.1.1-2025-01-31`. Its Google release-candidate label is an explicitly accepted pilot risk because it outperformed the available `stable` alias in the diagnostic run. Never use a mutable processor alias in production. A later equivalent stable Mumbai version is preferred, but promotion remains a recorded configuration change with an availability check, bounded smoke test, relevant regression evidence, and rollback readiness.
- Use `gemini-embedding-001` at 768 output dimensions for the rebuilt retrieval index. Corpus inputs use `RETRIEVAL_DOCUMENT`; submitted user queries use `RETRIEVAL_QUERY`.
- Run Gemini document extraction and Document AI OCR in Mumbai (`asia-south1`). Configure the embedding endpoint independently and verify the selected model in Mumbai before rollout; do not use one shared location variable or silently fall back to `us-central1`/`global` when India residency is required.
- Use Google's current `@google/genai` SDK for Gemini structured-generation paths before production backfill or cutover. The live Mumbai smoke call through the legacy `@google-cloud/vertexai` package proves regional availability only; it does not approve carrying Google's deprecated SDK into production.
- Model/processor, endpoint/region, dimensions, task type, safety settings, page-quality policy, and effective pricing are versioned operational configuration. Domain rows record the effective model/processor and version used.
- PDF content, OCR output, imported text, notes, and matter context are untrusted inputs. Prompts explicitly prohibit following instructions found inside source content.

### Page-content acquisition and language authority

- Extract the native PDF text layer, text-item geometry, page size, and rotation locally for every page before any paid OCR call. Apply a deterministic, versioned page-quality policy covering absent/sparse text, invalid or replacement characters, implausible density, broken encodings, and suspicious image-heavy mixed pages.
- Retain accepted native text exactly as the source page layer. Render rejected pages at ordinarily 300 DPI and send only those pages to Enterprise OCR, retaining OCR text, word/region coordinates, detected language, processor/version, and available page-quality evidence. Provider image-quality scores are optional telemetry, not a routing dependency: the current Mumbai processor rejects that option, so routing remains deterministic from native-text coverage/encoding, visible-image coverage, rotation, hidden-layer suspicion, and other locally reproducible signals.
- Merge native and OCR pages into one private, immutable-asset/version-bound page artifact in 1-based PDF order. Record acquisition method and quality per page. A limited or unreadable page is disclosed and remains metadata-searchable; the worker never invents missing text.
- Page-text eligibility is separate from field Review. An accepted native page or an OCR page that satisfies the approved acquisition gate may supply page chunks and embeddings after the document/version and Search rollout gates pass. A page with unreliable transcription, critical evidence, table structure, or source anchors is excluded from page-body chunking and marked for safe retry or `source_unreadable`/`metadata_only` handling. Accepting or correcting an extracted GSTIN, reference, date, amount, or other candidate in Review changes effective structured metadata only; it does not certify the whole page transcript. The page body becomes eligible later only after successful reacquisition or an explicitly implemented, provenance-bearing whole-page transcript verification workflow.
- Native text and OCR are transcription, not translation. Original Hindi, English, or mixed-language text remains the authoritative citation and passage-index source. Full document-body translation is not created merely to make embeddings or the English UI work.
- Native pages with image-only stamps, marginalia, handwriting, or material table regions are part of the evaluation corpus. The policy may conservatively OCR those pages when the native layer does not represent visible material content; apparent non-empty text alone is not sufficient quality evidence.
- Enterprise OCR word/layout output is authoritative for OCR selection anchors, but it is not assumed to provide a legally perfect relational table. Retain structured table blocks, cells, reading-order cues, and geometry separately from the flattened page string. Gemini may interpret a table for source-grounded metadata while the source cells and coordinates remain the citation layer; a specialized table parser requires measured corpus need and a later contract.

### Schema and prompt contract

- Zod is the authoritative CaseChain runtime schema. Generate the provider response schema from the same contract through a tested compatibility adapter; do not maintain semantically independent handwritten schemas.
- Vertex structured generation requests set `responseMimeType: application/json` and provide the compatible response schema derived from the canonical Zod contract. Regex or substring extraction from conversational prose is not a supported canonical recovery path.
- The adapter removes or transforms constructs Vertex structured output does not support, and CI tests parity with representative payloads. A provider accepting JSON does not replace post-response Zod validation.
- Version prompt semantics, response schema, normalization rules, and document-type catalogue independently. Store every effective version on the extraction run.
- The Gemini document extraction response contains structured legal metadata only. It includes source language; identity/classification; client identifiers, parties, issuer, direction, periods and financial years; relationships; normalized legal references; explicit deadlines; typed financial facts; and short page/quotation evidence for each material candidate. It contains no full-page transcript or OCR word stream.
- The synopsis/summary and all user-facing descriptive metadata are written in English. Proper named entities are transliterated to an English display form rather than semantically translated; institutional and role terms may be translated where useful. Preserve the exact original entity spelling/evidence separately, mark the English form as derived and correctable, and never rewrite GSTINs, reference numbers, provision identifiers, dates, or amounts.
- The English synopsis remains concise, neutral, and source-grounded and distinguishes allegations, taxpayer submissions, authority/court findings, relief, and final operative directions. It must not fill missing facts or convert OCR uncertainty into certainty.
- Extract only source-supported facts. Do not calculate statutory limitation dates during extraction. Relative periods may be stored as unresolved textual candidates but never as calendar deadlines.
- Do not let the model perform uncertain aggregation. Preserve source-stated components and totals separately; domain validation may check arithmetic but does not invent a missing total.
- Keep quotations short and evidentiary. Before placement, source evidence binds to the immutable `file_asset_id`, page/OCR content version, and 1-based PDF page. When the analysis is bound to a document version, every user-facing evidence locator binds to the exact `document_version_id` and page from the File Lifecycle plan.

#### Approved normalization contract (2026-09-11)

- The [September 11 Matter-identity and extraction decision](../../decision-history/2026-09-11-matter-identity-and-extraction-normalization.md) governs this schema revision. Each material fact preserves its raw/source wording and evidence alongside a typed normalized value, precision, catalogue/normalizer version, field-level confidence, and deterministic validation state. A single document-wide confidence score never authorises or conceals a critical field.
- Replace a single human-readable `tax_period` value with an ordered array of typed periods supporting month, quarter, exact-date range, financial year, multi-financial-year, non-contiguous, and unclear source expressions. Retain source precision: `JAN 2020 – JAN 2020` normalizes as one month, while a month-only source must not acquire invented first/last-day dates. Compare derived financial years with printed financial-year labels and route disagreement to focused Review.
- Document/form type uses a versioned catalogue and retains the printed label. Title retains raw wording plus a correctable display value and is never identity. Client identifiers are typed (`gstin`, `pan`, `tan`, `cin`, or catalogued `other`); GSTIN is uppercased and format/checksum validated, while client-name aliases are search evidence only.
- Dates are separate candidates classified by legal meaning, including issue, filing, communication/service, order, hearing, due, and source-unknown date; one document may contain several. Financial years are normalized arrays with raw labels and must not be inferred from a document date when the source concerns an earlier period.
- Direction is derived from typed issuer/recipient roles. Issuer retains raw text plus normalized authority, office, and jurisdiction where source-supported. Parties use typed procedural roles; unknown roles stay unknown rather than being guessed.
- Official self identifiers and outbound document references retain raw/display values, typed kind, issuer/system namespace, normalized components, role, and page evidence. Legal provisions use their own normalized legal-reference catalogue and are not conflated with proceeding/document identity.
- Deadlines distinguish explicit source dates from later calculated dates; extraction cannot make a calculated deadline authoritative. Money uses decimal strings or integer paise with currency, component, applicable period, and legal posture such as alleged, demanded, confirmed, paid, refunded, or disputed; it never uses floating-point values or collapses unlike amounts into an invented total.
- The canonical Zod/domain schema owns these meanings. The Vertex-compatible schema is generated through the adapter and parity-tested, so prompt, provider, persistence, and consumer contracts cannot drift independently.

### Append-only extraction and candidates

- `source_analysis_runs` is append-only and immutable-asset scoped. It stores request identity, source `file_asset`, page/OCR content version, model/prompt/schema/catalogue versions, state, validated payload or validation errors, safe provider metadata, token/billable usage, latency, and timestamps. It can run while the source is an unassigned Intake item.
- Raw provider output may be retained encrypted and access-restricted for audit/debugging subject to retention policy; ordinary application clients and platform metadata views cannot read it.
- A successful source run materializes field-addressable immutable rows in `source_field_candidates`. Each records field path/type, raw/source display value where applicable, typed normalized JSON value and precision, source run/asset, page/quote/region evidence, field-level confidence, deterministic validation state, and semantic key.
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

#### Source-span/cell verification for critical facts

- Do not compare two whole-document strings. Gemini supplies a typed candidate, a normalized value, a 1-based page, and a short verbatim evidence quote; canonical native/OCR acquisition supplies page text plus token/word offsets, boxes, and structured table cells.
- For critical identifiers and facts, a deterministic comparator normalizes only comparison syntax while preserving the raw display/evidence: for example GSTIN/reference spacing and punctuation, Indian number separators, and supported source-date formats. It verifies that the quote occurs on the stated canonical page, that the candidate value resolves inside that quote or one retained table cell, and then stores the matching character/token identifiers and normalized regions on the candidate.
- “Metadata matches evidence” therefore means source-grounded semantic equality, not raw string equality and not agreement with Gemini's own payload. For example, Gemini's normalized date `2025-01-29` may match source text `29.01.2025` after a real calendar parse; a GSTIN must resolve to the same normalized 15-character source value and pass its deterministic syntax/checksum rule.
- Apply source-span/cell verification to GSTIN/PAN, official and parent reference numbers, document dates, explicit deadlines, monetary facts, and client/matter assignment keys before they can be automatically eligible. Amount validation preserves source-stated components and totals and may flag inconsistent arithmetic; it never invents a missing total.
- No match, multiple plausible matches, invalid syntax/checksum/calendar value, table ambiguity, handwriting or OCR conflict, or a source/Gemini digit difference is a field-level exception. The system does not guess or require users to re-enter every clean field; it groups only flagged facts into Review, while consequential Tier C actions still require their existing explicit decision.
- The comparator detects unsupported or conflicting metadata; it cannot prove truth when both OCR and Gemini make the same plausible error. Scanned handwriting, low-quality source regions, and other unreliable critical evidence therefore remain Review/sampling candidates even when normalized values agree. The rendered original PDF remains authoritative.
- The completed verifier compares candidates against the persisted canonical page acquisition rather than Gemini's payload: it requires a unique bounded normalized source value inside the submitted quote and page (or one retained table cell), validates supported calendar dates and GSTIN checksum, and persists canonical character, token/region, or cell/box anchors. Missing, repeated, malformed, mismatched, or unavailable critical evidence becomes a field-level exception without converting the document into a field-by-field approval workflow.

### Prompt and model evaluation

- Maintain a versioned, anonymised, access-controlled GST evaluation corpus with adjudicated expected fields and evidence. Development fixtures contain no client secrets or production legal documents.
- The initial extraction gate contains at least 25 representative PDFs and at least 100 adjudicated material facts across SCN/DRC notices, replies, OIO/OIA, appeals, hearing/communication documents, multi-year records, poor scans, regional-language or mixed-language sources, multiple monetary figures, relative versus explicit deadlines, and adversarial embedded instructions.
- Record per-field precision/recall, document-type/classification accuracy, amount exactness, deadline exactness, legal-reference normalization, evidence-page/quotation accuracy, invalid-response rate, abstention, latency, tokens, and cost.
- No single aggregate score can hide a critical deadline, amount, GSTIN, or evidence regression. Maintain per-domain minimums and a critical-fixture zero-regression gate.
- A prompt/model/schema change runs in shadow against the frozen corpus. Promotion records evaluator, metrics, cost/latency comparison, rollout scope, and rollback version.
- Sample production-like runs may be manually reviewed only with authorised anonymised documents. Provider calls require an explicit evaluation run and usage record.
- Evaluate page acquisition separately from legal extraction. Record native-page acceptance/rejection, unnecessary OCR and missed-OCR rates, character/word accuracy on adjudicated scan pages, Hindi/mixed-language accuracy, reading order and word-box quality, tables/stamps/handwriting behavior, latency, pages billed, and safe failure output.
- The secured local OCR evaluation command may process explicitly supplied test PDFs page by page or as a bounded whole-document request and write raw provider JSON plus extracted review text to a local ignored/output directory. It never writes credentials or source PDFs to the repository and is not a production ingestion bypass.
- The 2026-09-02 diagnostic corpus contained 311 discovered PDFs, 117 unique files, and 194 exact duplicates. A first 12-page representative run plus focused diagnostics found strong Hindi/English body OCR and useful table detection, but also a consequential handwritten-date digit error (`29.01.2025` read as `29.01.2015`) despite high aggregate confidence. Flattened text also lost important table structure. This validates selective OCR and preserved geometry, but does not approve automatic critical-field acceptance or Search cutover.
- In Mumbai, the exact stable v2.1 processor identifier tested was unavailable, the `stable` alias behaved like the older v1.0 family, and deployed `pretrained-ocr-v2.1.1-2025-01-31` produced the best diagnostic output but is labelled a Google release candidate. On 2026-09-03 the user approved this exact pin for the bounded design-partner production release and authorised the representative-corpus testing needed to validate it. The labelled benchmark, critical-field Review controls, monitoring, and rollback remain release gates; the version decision itself is resolved in the [approval record](../../approval-based-blockers.md#2026-09-03--mumbai-ocr-processor-promotion).
- The release-quality page-acquisition benchmark labels 60–100 unique representative pages across native English, scanned English, Hindi, mixed language, handwriting, stamps, tables, rotation, and poor scans. Report routing precision/recall, missed and unnecessary paid OCR, character/word accuracy, exact GSTIN/reference/date/amount accuracy, table-cell and evidence-anchor correctness, latency, billed pages, and cost separately; no aggregate confidence score may conceal a critical-field error.
- The approved acquisition gate requires: no failed or unknown GSTIN, reference, date, amount, table-cell, or evidence-anchor check; `100%` routing recall and at least `90%` routing precision; at least `98%` mean character accuracy and `95%` mean word accuracy across every adjudicated OCR page, with no missing OCR quality label; mean acquisition latency no greater than `10` seconds per source page and a normal bounded 100-page acquisition no greater than `20` minutes; and OCR charges no greater than `USD 0.01` per billed page or `USD 1.00` for a fully OCR-processed 100-page document, excluding tax and currency conversion. Report Hindi, mixed-language, handwriting, poor-scan, table, stamp, and rotation results separately even when the combined gate passes.
- Critical/source-integrity failure sends only the affected fact or page to the appropriate safe path. Field Review may accept, correct, reject, or clear a structured candidate against the rendered source; it does not approve an OCR transcript. A failed page remains out of page-body vector indexing until successful reacquisition or a future explicit whole-page transcript-verification workflow. Pages with accepted native text or qualifying OCR may proceed independently once the document/version and Search rollout gates pass. Latency or cost failure blocks rollout for tuning/capacity review but does not label accurate page text as false.
- The local benchmark evidence harness requires exact pinned evaluator provenance, 60–100 unique source pages, independent adjudication, and content-safe reports. It must apply and report the approved numeric gate without treating structural evidence, a field correction, or an aggregate confidence score as approval for page-body backfill or Search cutover. The decision and rationale are recorded in [the September 11 acquisition-threshold decision](../../decision-history/2026-09-11-ocr-acquisition-benchmark-thresholds.md).

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
- For embeddings, record organisation, source/index run, model/config/chunking version, actual provider units where returned, chunks created/skipped/rebuilt, active vector count, estimated raw vector bytes, latency, and safe success/failure state. Retrieval analytics records aggregate result/no-result/citation-open outcomes without raw query text.
- Provider totals remain internal cost accounting. The design-partner client is not charged per token, vector, egress byte, CPU, or memory sample; those commercial decisions wait for reconciled usage and value evidence.

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

### Completed: effective-metadata relationship re-evaluation consumer slice (2026-08-30)

- Migration `00077` introduces bounded service-only, current-valid matter relationship projections and effective-reference fuzzy/cross-matter helpers. The live additive `reevaluateMatterLinks` caller now authorises the active matter before consuming corrected type/reference values; it no longer parses `raw_metadata`.
- Empty, cleared, rejected, ambiguous, stale, invalid, or missing cited relationship values fail closed and do not trigger progression inference. Exact/fuzzy/cross-matter/pending paths retain their existing additive/deduped behaviour for valid cited values.
- Clean local replay through `00077`, focused SQL authority fixtures, generated type parity, targeted tests, migration checks, and fresh independent QA passed. The legacy processing-time `placeDocument` path remains a separate consumer migration.

### Completed: processing-time relationship placement consumer slice (2026-08-30)

- Migration `00078` replaces the dormant legacy `placeDocument` adapter with an atomic, service-only `place_document_processing_relationships` command. It consumes only the current valid effective relationship projection and preserves the approved exact, fuzzy, cross-matter, and pending-review policy through an idempotent version-scoped effect ledger.
- The live `processDocument` worker now invokes that typed command after both newly validated and replayed already-validated provenance work. Snapshot contention returns a retryable fence result, which the worker throws into Trigger's bounded retry path without a second model invocation; browser roles retain no table or RPC access.
- Local replay through `00078`, the relationship fixture, a two-session provenance/placement deadlock harness, generated-type parity, focused TypeScript tests, type checking, targeted lint, migration checks, and fresh independent QA passed. Automatic assignment remains a prerequisite without a connected production caller.

### Completed: Matter Wiki effective-context consumer slice (2026-08-30)

- The live authenticated Matter Wiki trigger and `generateMatterWiki` worker now select only active documents within the exact matter and organisation, then obtain their bounded context through the existing service-only current-effective-metadata reader. The worker no longer selects, stringifies, or falls back to `raw_metadata`.
- A deterministic allow-list formatter admits only valid current automatic, accepted, or corrected document, legal-reference, deadline, and financial values. Cleared, rejected, missing, malformed, wrong-type, duplicate, forged, and mixed-version rows fail closed; an empty projection gives the model a deliberate neutral context while preserving the existing generation and upsert workflow.
- Focused shaping and worker-boundary tests, TypeScript checking, targeted lint, migration checks, and fresh independent QA passed. No schema change was necessary; the existing reader remains the sole projection authority.

### Canonical next action

The Inbox staged-document adapter deliberately nulls `raw_metadata`, so its card is not a connected provenance consumer and must not receive unused projection plumbing. The remaining raw-metadata references are compatibility writes or uncalled legacy actions, not live readers. Keep automatic assignment as a prerequisite until a real caller exists. Commit `aa13669` delivered reusable private artifact/chunk storage, lineage, lease, tenant, lifecycle, and replay fences; migrations `00115`/`00116` independently verify the corrected native-first/selective-Mumbai-Document-AI producer, Gemini transcript removal, English metadata boundary, delivery-lease dispatch, rotated anchors, and legacy-Gemini source exclusion. The 2026-09-02 diagnostic OCR run is complete and records strong multilingual output alongside a high-confidence critical-date error and table-flattening limits. The exact v2.1.1 Mumbai release-candidate pin is approved for the bounded pilot; no Search backfill/cutover has occurred.

Completed 2026-09-02: migrations `00117`–`00121` make verified candidates source-span/cell grounded against the same canonical page artifact that `processDocument` persists. The service-only writer enforces tenant/version/current-page/lease fences, idempotent replay, unique quote/page/cell resolution, canonical token/region or table-cell geometry, exact bounded code/decimal/date matching, and the same supported 1000–9999 calendar-year rule as the runtime verifier. All Gemini structured-generation callers, including Matter Wiki, use `@google/genai`; embeddings remain separately scoped. Focused developer checks, clean local reset and SQL fixture, generated-type parity, and fresh read-only adversarial QA passed. Existing repository-wide TypeScript nullability-test failures remain a recorded unrelated baseline.

The exact next tranche is the labelled 60–100-page acquisition benchmark using the approved exact Mumbai processor version and the September 11 numeric gate: assemble the representative native/OCR corpus, extend the evidence report for the approved thresholds and page/field dispositions, and report routing, quality, critical facts, structures, multilingual behavior, latency, billed pages, and cost separately. Do not backfill or cut over Search until that benchmark passes. Keep Client, Matter, Task, Note, chat, Case Brief, Activity, arbitrary-row embeddings, generated answers, and workspace-wide memory out of the first release.

1. **Resolve the blocking migration defect.** Assign the embedding migration the next unused monotonically ordered prefix and add a CI migration-version uniqueness check before applying it anywhere. Do not apply the duplicate `00024` file.
2. **Freeze and test the canonical schema.** Make Zod authoritative, add the Vertex compatibility adapter, and add parity fixtures for valid, invalid, optional, unknown, array, enum, and null behavior.
3. **Add provider-contract tests and controlled failure handling.** Mock Vertex structured-generation and embedding responses to cover JSON MIME/schema configuration, strict parsing, unknown keys, malformed/non-JSON/truncated output, one controlled regeneration, capped transient retries with backoff/jitter, token statistics, dimensions, task type, safe restricted evidence, and content-safe logging. Keep these tests credit-free.
4. **Introduce append-only provenance storage.** Add asset-scoped source-analysis runs/candidates, document-version bindings, document candidates, field decisions, effective metadata projection/recompute, RLS, immutability constraints, semantic candidate keys, and source locators.
5. **Migrate the processing write path.** Store the run first, validate, materialize candidates, run domain validation, create Review items for material issues, and recompute effective metadata. Transitional `raw_metadata` may dual-write until consumers migrate.
6. **Normalize high-use consumers.** Move assignment, inspector, legal references, deadlines, financials, relationships, and search indexing from ad hoc JSON parsing to typed candidates and effective projections.
7. **Complete prompt and page-acquisition separation.** Remove full-page transcription/OCR words from Gemini; add English-only synopsis and descriptive metadata, proper-noun transliteration with retained original evidence, the finalized financial-event/per-candidate evidence contract, catalogue versioning, allegation/finding qualification, and explicit relative-deadline abstention.
8. **Build the evaluation harness and corpus.** Provide a local Document AI page/whole-document evaluator, native-quality routing fixtures, anonymised extraction manifests, expected candidates/evidence, deterministic graders, human adjudication workflow, comparison report, and a secured live-evaluation command that records usage without storing credentials or source PDFs.
9. **Create index-version rollout state.** Add the version registry, per-organisation coverage/cutover/rollback state, durable checkpoints, dual-write control, and safe operational reporting.
10. **Backfill first-release document chunks in shadow.** Reindex only current PDF-owned page-aware chunks without changing the active search version. Do not embed Notes, chats, Matters, clients, Tasks, Case Brief blocks, Activity, or arbitrary rows. Verify coverage, relevance, and cost per organisation, then atomically cut over and monitor before retiring legacy vectors and excess rollback versions.
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

The canonical response uses field-specific contracts rather than a flat bag of strings. Representative shared shapes are:

```ts
type SourceValue<T> = {
  raw: string
  normalized: T | null
  precision: 'exact' | 'month' | 'quarter' | 'financial_year' | 'unclear'
  confidence: number
  validationState: 'valid' | 'provisional' | 'conflicting' | 'invalid'
  evidence: SourceEvidenceLocator
}

type NormalizedTaxPeriod =
  | { kind: 'month'; year: number; month: number }
  | { kind: 'quarter'; financialYear: string; quarter: 1 | 2 | 3 | 4 }
  | { kind: 'date_range'; from: string; to: string }
  | { kind: 'financial_year'; financialYear: string }
  | { kind: 'multi_financial_year'; financialYears: string[] }
  | { kind: 'non_contiguous'; members: NormalizedTaxPeriod[] }
  | { kind: 'unclear'; reason: string }

type NormalizedOfficialReference = {
  role: 'self_identifier' | 'outbound_mention'
  kind:
    | 'proceeding_case_id'
    | 'notice_reference'
    | 'order_reference'
    | 'appeal_reference'
    | 'court_case_number'
    | 'other_official_reference'
  issuerOrSystemNamespace: string | null
  displayValue: string
  normalizedValue: string | null
  components: Record<string, string>
}
```

Recursive provider-schema compatibility is an adapter concern: the authoritative Zod/domain contract may emit a provider-safe bounded equivalent while runtime validation restores the canonical shape. `other_official_reference` and `unclear` remain non-identity/non-automation outcomes.

### Core provenance storage

- `source_analysis_runs`: source asset and organisation; page/OCR content version; idempotency key; provider/model and prompt/schema/catalogue/normalizer versions; state; current attempt; validated payload reference; safe error category; usage/cost; latency; timestamps; and supersession.
- `source_analysis_attempts`: append-only provider/model/prompt/schema versions, provider request/run identity, start/end and latency, token/billable usage and cost, retry reason, failure category, and access-restricted raw-response evidence reference where retention permits. The outbox and ordinary logs never store the raw response.
- `source_field_candidates`: source run/asset/organisation; semantic key; field path/type; raw/display value; typed normalized value and precision; page/quote/region evidence; field-level confidence; validation errors/state; normalizer/catalogue versions; timestamps.
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
- Normalization fixtures cover tax-period month, quarter, date range, one FY, multiple FYs, non-contiguous periods, `JAN 2020 – JAN 2020`, alternate separators/order/case, and unclear text. They preserve source precision, never invent day boundaries, and create focused Review when printed and derived financial years conflict.
- Contract fixtures cover every audited field family: catalogued document/form type with printed label; raw/display title; typed GSTIN/PAN/TAN/CIN with GSTIN checksum; multiple legally typed dates; issuer/recipient direction and authority/jurisdiction; typed parties; self identifiers and outbound references; explicit versus calculated deadlines; decimal/paise money with component/period/posture; and normalized legal references with raw evidence.
- Every material candidate has its own confidence, validation state, evidence, and raw/normalized representation. Tests prove that a high aggregate-quality document cannot make one incorrect or ambiguous GSTIN, official reference, date, period, or amount effective.
- Mocked provider tests cover document analysis, the disabled/gated Case Brief boundary, embedding shape/dimensions/tokens/task types, JSON MIME/schema configuration, provider failures, timeouts, throttling/5xx responses, malformed/non-JSON/truncated payloads, controlled regeneration, retry exhaustion, and content-safe logs without spending Vertex credits.
- Invalid structural output writes an `invalid_model_output` attempt and no candidate/effective metadata or partial domain effects. Only one fresh controlled generation follows invalid output; a second invalid result creates Review/recovery. Transient failures retry no more than twice with the same run/document-version identity and capped exponential backoff with jitter.
- Strict parsing does not use regex recovery. Unknown keys fail Zod validation, access-restricted raw evidence never leaks to outbox/logs/client payloads, and every attempt records provider/model/prompt/schema version, usage/cost, latency, and failure category.
- Structurally valid responses with isolated uncertain or contradictory values preserve valid candidates and route only the affected fields to provisional/conflicting/Review states. Domain-invalid candidates remain auditable but cannot become effective.
- Re-extraction preserves previous runs and human decisions. A conflicting new value creates Review and does not silently replace the effective value.
- A clean high-confidence document completes without requiring a field-by-field approval pass. Tier A auto-applies, Tier B remains visibly provisional where appropriate, and Review contains only exceptions or Tier C decisions.
- Deadline fixtures never produce an effective date from only a relative period. Amount fixtures preserve stated components/totals exactly in paise without uncertain aggregation.
- Intake evidence resolves against the authorised immutable asset/page. After binding, user-facing evidence locators resolve against the exact document version and reject out-of-bounds pages. Replacement tests preserve old citations, and assignment does not invoke a duplicate extraction call.
- Assignment, legal references, deadlines, financials, relationships, inspector, and search consumers no longer require arbitrary `raw_metadata` paths at cutover.
- Prompt-injection fixtures cannot alter the output contract, request external actions, expose secrets, or turn source instructions into system instructions.
- Gemini provider-contract tests prove the response schema has no transcript, `page_text`, or OCR-word field; the English synopsis is source-grounded; named entities retain an English display form plus exact original evidence; and exact identifiers/numbers are unchanged.
- Native-page fixtures prove accepted text and geometry are deterministic. Selective-OCR fixtures cover empty, broken-encoding, image-heavy mixed, Hindi/mixed-language, stamp, handwriting, table, low-quality, unreadable, rotated, and long-document cases; only rejected pages incur OCR and every OCR page retains processor/version, quality, and normalized anchors.
- Critical-field fixtures prove source-span/cell verification rather than payload-internal equality: normalized date formats compare as calendar values, GSTIN/reference punctuation does not create a false mismatch, table-cell values retain their cell/box anchors, one-digit collisions and ambiguous repeated values fail closed, and a high-confidence OCR/Gemini conflict creates one focused Review exception.
- Official-reference fixtures preserve issuer/system namespaces and self-versus-mention roles, reject unknown or partial values as identity, and give placement/relationship consumers the same normalized key regardless of which related document arrived first.
- A clean document requires no field-by-field confirmation. The Workbench can bulk accept safe unflagged values, while missing/ambiguous source matches, invalid GSTIN/date/amount facts, handwriting, and consequential Tier C effects remain visibly reviewable.
- Region tests prove Gemini document extraction and Document AI OCR address `asia-south1`, embedding location is independently configured, and no India-residency path silently falls back to `us-central1` or `global`.
- Provider tests and one bounded Mumbai smoke call prove the `@google/genai` structured-generation path preserves the existing strict Zod/schema, safety, usage, retry, and safe-error contracts before production cutover.
- Multilingual retrieval evaluation embeds original-language chunks without full-body translation and covers English queries retrieving relevant Hindi/mixed passages. Exact/entity search covers both original names and correctable English aliases without replacing the source spelling.
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
- The design-partner release intentionally measures a narrow retrieval index before any agent, generated-answer, Case Brief synthesis, or workspace-memory expansion is reconsidered.

## Open Questions

None.
