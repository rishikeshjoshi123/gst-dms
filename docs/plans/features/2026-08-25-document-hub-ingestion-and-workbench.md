---
title: Document Hub, Ingestion, Placement, Relationships, and Workbench
status: approved
created: 2026-08-25
updated: 2026-09-08
owners:
  - product
  - engineering
related:
  - ../platform/2026-08-24-product-architecture-portfolio.md
  - ../platform/2026-08-24-document-record-and-file-lifecycle.md
  - ../platform/2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
  - ./2026-08-24-universal-search-and-evidence-retrieval.md
  - ./2026-08-25-work-review-activity-notifications.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Document Hub, Ingestion, Placement, Relationships, and Workbench

## Reading guide

Use the [shared reading rules](../../README.md#reading-a-large-plan). Read the scope/security links first, then relevant operations and their interfaces/acceptance. Expand dependencies when needed; recorded checkpoints require current-code reconciliation.

- **Read first:** [Scope](#scope-boundaries) · [Current corrections](#september-review-closure-and-pilot-scope) · [Security](#permissions-and-security).
- **Ingestion and placement:** [Ingestion contract](#end-to-end-ingestion-contract) · [State boundaries](#state-separation-and-orchestration) · [Duplicates](#exact-duplicates-and-intentional-reuse) · [Placement](#placement-engine-overhaul).
- **Relationships and workspace:** [Relationships](#reference-and-procedural-relationship-overhaul) · [Hub](#document-hub-experience) · [Workbench](#shared-document-workbench) · [Approved visuals](#visual-approval-boundary-approved-2026-09-05).
- **Checks and contracts:** [Interfaces](#interfaces-and-data-changes) · [Acceptance](#testing-and-acceptance-criteria) · [Assumptions](#assumptions) · [Open questions](#open-questions).

## Summary

Rebuild document intake as one durable path from file selection to an evidence-backed document inside a matter. Global uploads, matter uploads, later file attachment, replacement versions, and future external acquisition all enter through the same upload-session, immutable-asset, validation, analysis, placement, and projection contracts. The pipeline extracts a unique PDF once, never copies it merely to assign it, records every consequential automated decision, and can resume individual failed stages without a user-facing `Sync` action.

Replace the current reference-first assignment function with a versioned placement engine that separates human-declared destination, deterministic evidence, ranked suggestions, conflicts, and effective assignment. Organisation placement defaults to manual: an explicit intended matter is a human-declared destination, while evidence-inferred automatic placement remains inactive unless an Owner/Admin opts into `strong_evidence_auto_place`. Even then, it is limited to one unique, high-authority matter anchor with no contradictory evidence. GSTIN plus financial year, fuzzy references, names, filenames, and semantic similarity can rank suggestions but cannot silently file a document.

Replace the current `document_links` algorithm with two layers: source-grounded reference mentions and effective procedural relationships. An ordinary citation does not automatically become a timeline edge. Exact, unique, same-matter, procedurally explicit relationships may auto-confirm; fuzzy or progression-only inference becomes a Review candidate. Manual decisions remain authoritative, rejected suggestions do not recur, self-links are impossible, and event-driven reevaluation replaces the ordinary-user `Re-evaluate links` button.

Make Document Hub the operational queue and create one shared `DocumentWorkbench` for intake, matter, Search, Activity, Review, and Trash routes. The Workbench uses a continuous, searchable PDF viewer; a structured inspector; page-accurate text/OCR/region quotations; stable desktop split panes; and mobile-equivalent document, details, notes, and decision flows.

## Context and Goals

### Historical audit at plan creation

This describes the original paths, not the current completion state. Use [delivery outcomes D04–D09](../../delivery-ledger.md) and the implementation checkpoints below for the current handoff; reverify the actual checkout before changing a completed foundation.

The current application has two partially independent ingestion paths:

- `uploadToInbox` writes a browser-uploaded file to the `staging` bucket, inserts `staged_documents`, and schedules `analyze-staged-document` with a best-effort post-response callback.
- `uploadToMatter` writes directly to a matter-named path in the `documents` bucket, immediately creates a `documents` row, and schedules the separate `process-document` job.
- Global assignment downloads the staged file and uploads another copy under a matter path. Copy-to-matter duplicates the binary again. Partial failure can leave storage and database state out of sync.
- The staged job analyzes the PDF before placement and the document job conditionally skips a second analysis by checking mutable `raw_metadata`. There is no durable, asset-scoped analysis contract.
- Processing state, legal-record state, review state, placement state, and indexing state are combined in `staged_documents.status` and `documents.status`. Queue dispatch is not transactionally durable.
- Duplicate checks cover only some active `documents`; they do not consistently include Intake, historical versions, or Trash. Limits are hardcoded at 50 MB instead of using the approved 25 MB pilot entitlement and organisation/platform reservations.
- Routine processing and assignment create noisy notifications even though the approved notification policy assigns these events to inline status and Activity.

The current placement algorithm also encodes assumptions that are unsafe as a long-term legal filing policy:

- an exact referenced-document number may auto-place without a verified client identifier;
- client plus financial year is treated as matter identity, and the database currently prevents multiple active matters for the same client/year even though separate proceedings can exist in one year;
- multiple extracted financial years force manual placement even when an exact proceeding anchor exists;
- fuzzy reference results and a numeric confidence value are mixed with deterministic evidence without a persisted candidate/evidence ledger;
- reevaluation updates suggestions broadly and cannot explain which source version, extraction run, or rule version produced a result;
- an already placed document has no safe `possible reassignment` flow when later evidence conflicts.

The current relationship algorithm conflates mentions, citations, inferred procedure, and effective graph edges:

- an unrecognised document-type pair defaults to `responds_to`, inventing semantics;
- an exact raw reference creates a confirmed edge without field-level evidence or a sufficiently specific reference identity;
- type-progression and fuzzy guesses create pending edges and direct notifications;
- a missing target is represented as a link with a null endpoint;
- broad reevaluation reads mutable `raw_metadata`; there is no immutable run, candidate, decision, or rejection memory;
- service and database protections are incomplete beyond the original self-link check and endpoint uniqueness;
- the timeline cannot distinguish a document merely cited in text from a document that procedurally leads to, answers, decides, or modifies another document.

The present PDF experiences are also inconsistent. Document Hub opens a PDF-only modal, while the nested Matter route shows one PDF page beside a separate details component. The shared viewer renders one page at a time, relies on next/previous controls, dispatches global browser events for quotations, and stores only selected text plus a page number. It cannot reliably restore a highlight after zoom/rotation, identify the immutable PDF version, handle image-only scans, or provide one consistent inspector.

### Goals

- Give every accepted byte stream one immutable organisation-scoped asset identity and one durable processing history.
- Make file selection immediate and low-friction while keeping validation, quotas, duplicate handling, and failures honest.
- Let explicit user context win without allowing AI to silently reroute a matter upload.
- Automate high-certainty placement and relationships without turning every harmless extracted field into manual work.
- Explain every suggestion or automated decision with typed, page-linked evidence and a versioned policy.
- Ensure corrections and rejections survive reprocessing, model changes, replacement PDFs, reassignment, and retries.
- Let users inspect the PDF, extracted/effective facts, deadlines, amounts, parties, legal references, relationships, notes, processing, and provenance in one reusable workspace.
- Make scanned-document quotation possible through OCR-backed text boxes or a region anchor when text selection is unavailable.
- Provide implementation boundaries, migrations, commands, events, permissions, failure behavior, observability, and acceptance tests without requiring another architecture pass.

### Scope boundaries

- Original uploads remain PDF-only in this phase. Images and Office files require a later acquisition plan.
- Spreadsheet rows without PDFs use the approved metadata-only document contract and do not pass through binary validation until a PDF is attached.
- GST portal, email, API, and spreadsheet acquisition are future producers of the same intake commands; this plan does not design their authentication or mapping UI.
- Search consumes page/OCR artifacts and source locators but remains owned by the Search plan.
- Notes owns message/thread behavior; this plan owns creation and resolution of PDF quotation locators used by Notes.
- Deadlines and Financials own their canonical facts and verification; this pipeline only produces candidates and events for those domains.

## Decisions

### September review closure and pilot scope

- D04/D05: use the File Lifecycle plan's bounded direct resumable upload and **Attach PDF** contract. Show real transferred bytes separately from validation/processing. After reload, durable status is recoverable but incomplete file transfer may require reselection; do not promise background or cross-device upload. No replacement/version-management interface is required for the pilot.
- D06: readers return explicit success/error results. A successful empty snapshot clears stale rows; only a genuine read failure preserves the last successful view with honest freshness. Sign requests and PDF results are fenced by selected subject/version and request generation; a late result for A cannot render beside B's metadata.
- D06: collections use bounded server pagination and true count projections; destination lookup is bounded/searchable. Fetch the selected inspector and necessary relationship context instead of every document in the matter. Invalidation reconciles selected effective metadata as well as rows through the approved Realtime contract.
- D06/D07: validate the shared production viewer and its real consumers at 320px/360px, short desktop heights, dark mode, keyboard/touch and 200% zoom. Use fit-to-width, responsive toolbar layout and gap-aware split sizing; the approved 460px concept is not evidence that a different production component passed.
- D07: pass selected immutable version/page through loader, viewer, inspector and quote persistence. Label any current interpretation alongside historical evidence explicitly; do not offer misleading current-metadata editing from that historical context. Version-bound citations are required even while replacement UI is deferred.
- D09: replace client-plus-financial-year uniqueness with the approved proceeding/matter identity safeguards only after audit/backfill. Update manual creation, placement and Trash Restore together. Similar metadata may suggest a candidate but never merge documents; two distinct matters for the same client/year must be representable.
- Fix labels in touched real flows: consistent CaseChain naming, descriptive visible verbs, `Move to Trash` for recoverable deletion, and explicit unavailable capability states. Do not create another concept round for settled shared patterns.

### Product vocabulary, routes, and ownership

- The user-facing capability is **Document Hub**. Use `/documents` as its canonical collection route and `/documents/intake/{intakeItemId}` for an unassigned item. Keep `/inbox` as a compatibility redirect after cutover.
- Use `/documents/{documentId}` as the canonical assigned-document route. Legacy `/matters/{matterId}/documents/{documentId}` routes redirect while preserving version, page, highlight, and return-context query state.
- `Document Hub` owns upload sessions, active Intake, placement, duplicate/failure recovery, recent assignment handoff, and the intake form of the Workbench. It is not a second document database and is not the organisation Review queue.
- `DocumentWorkbench` owns document/PDF inspection everywhere. Matter Timeline, Files, Search, Activity, Notes quotations, Review evidence, and Trash open the same component with a typed subject and capabilities.
- Ordinary unplaced Intake stays in Document Hub. A conflict between strong placement evidence, a possible reassignment of an already filed document, or another typed consequential exception creates Review under the approved Work/Review plan.
- Routine processing completion and ordinary auto-placement update Hub, the destination matter, and Activity. They do not create personal Notifications.

### End-to-end ingestion contract

Every binary source follows this sequence. Stages use durable rows and idempotency keys; they are not one long transaction or one monolithic worker.

| Stage | Authoritative behavior | User-visible result |
| --- | --- | --- |
| 1. Select and reserve | The client requests an upload session for file name, declared bytes/MIME, origin, and optional intended matter/class. The server checks capability, matter liveness, 25 MB/default quota, organisation reservation, and platform guard before issuing a bounded asset-key upload contract. | A stable queue row appears immediately as `Queued` with real transfer progress only while bytes upload. |
| 2. Transfer and finalize | Bytes upload directly to the private organisation asset key. Finalization verifies object existence and server-observed bytes; it commits/ensures an `intake_item` and an outbox event. Browser disconnect does not lose the durable item. | The row becomes `Validating`; refresh or another device can resume its state. |
| 3. Validate and fingerprint | Validate PDF signature/readability, encryption, page limits, detected MIME, suspicious-content policy, SHA-256, and quota accounting. Never trust extension, browser MIME, declared size, or client hash. | Valid files continue. Password-protected/malformed/oversize/quarantined files show a safe reason and exact recovery action. |
| 4. Resolve exact duplicate | Match the server hash against active, historical, Intake, and Trash asset references in the organisation before a paid AI call. | Open existing, view/restore Trash, return to the active intake item, or cancel. Ordinary upload cannot create a duplicate logical record. |
| 5. Acquire page content | Extract native PDF text and geometry locally page by page. Apply the versioned quality gate, then send only absent, low-quality, or suspicious mixed pages to the Mumbai Google Document AI Enterprise OCR processor, retaining acquisition method, original-language text, page/word boxes, language, and quality. | The row is `Extracting` with a real `Reading document` or `OCR processing {N} pages…` substage; limited/unreadable pages are disclosed rather than hidden. A provider batch exposes its truthful page scope, not invented page-by-page progress. |
| 6. Extract and validate | Send the immutable PDF to the versioned Mumbai Vertex Gemini contract for structured GST/legal metadata only, validate with Zod and domain rules, and persist source-grounded candidates. Gemini returns an English synopsis and English display metadata but no transcript/OCR layer. | Key facts populate progressively; structural failure becomes retryable without losing the file. |
| 7. Classify and place | Resolve human intent, class candidate, placement candidates, evidence, contradictions, and policy. Matter-intended uploads can be placed after validation; global Intake waits for a valid automatic or human placement decision. | The row becomes `Matching`, `Needs placement`, `Conflict`, or `Assigned`. |
| 8. Materialize document/version | In one domain transaction, create or attach the logical document and immutable version, bind reusable source-analysis artifacts, apply eligible metadata, record placement/classification decisions, append Activity/outbox, and close Intake. No binary move/copy occurs. | The assigned document appears immediately in the matter with remaining stages inline. |
| 9. Build domain projections | Independently evaluate reference mentions/relationships, deadline and financial candidates, page-aware Search chunks/embeddings, and other derived projections. Each stage has its own run/failure state. | The document can be viewed while later projections say `Indexing`, `Relationship review`, or another real partial state. |
| 10. Complete or recover | A processing coordinator derives the combined display state from stage runs. Failed stages retry within policy and can be retried by scope. | `Ready` means usable source plus eligible effective metadata, not that every optional projection succeeded. |

- Matter-intended upload is human-declared context. If the matter is still active and the user retains permission, assignment occurs after binary validation without waiting for AI placement. Later identity conflict creates one placement-conflict Review item and a visible warning; it never silently moves the document.
- Global Intake remains independent of a logical `documents` row until placement. Base page/OCR/extraction artifacts are therefore keyed to `file_asset_id` through `source_analysis_runs`, not forced to reference a nonexistent document version.
- When placement creates `document_versions`, a `document_version_analysis_bindings` row binds the immutable asset analysis to that version. Document-specific candidates and decisions reference the binding. This avoids a second AI call and lets an intentional audited Copy reuse the same organisation-local base analysis while rebuilding matter-specific projections.
- Base extraction excludes mutable matter context. Placement and relationship resolvers combine immutable source candidates with current, verified matter/client data in their own versioned runs. This prevents the same PDF from acquiring different base facts because it was temporarily suggested to another matter.
- A replacement version runs validation and source analysis against the new asset before promotion. Promotion is transactional; old source locators continue to resolve to the old version.
- Processing scopes are `validate`, `page_text_ocr`, `extract`, `placement`, `relationships`, `deadline_financial_projection`, `search_index`, and `full`. UI offers a scoped recovery action for a failed stage, not a generic rebuild.
- `Ready` does not wait for Search embeddings, Case Brief refresh, email, or other nonessential projections. Their failures remain separately observable and retryable.

### Approved page acquisition and language contract (2026-09-01)

- Native page text/geometry is the default authoritative page source and is acquired before a paid provider call. The versioned quality gate rejects empty/sparse, broken-encoding, implausible, or image-heavy mixed pages; non-empty native text alone does not prove that visible stamps, handwriting, or table regions are represented.
- Google Document AI Enterprise OCR is the approved selective OCR adapter. Use a pretrained `OCR_PROCESSOR` in Mumbai (`asia-south1`); no custom training or prompt is required. Ordinarily render rejected pages at 300 DPI and retain processor/version, detected language, quality, and normalized word/region coordinates.
- Original Hindi, English, or mixed-language native/OCR text remains the quotation and Search source. OCR does not translate it. Limited/unreadable pages retain metadata-only coverage with an explicit user-visible limitation.
- Gemini remains the GST/legal interpretation step. Its response schema contains no full-page transcript, `page_text`, or OCR-word stream. User-facing synopsis and descriptive metadata are English; proper names use a correctable English transliteration while exact original spelling/evidence remains retained. Exact GSTINs, references, provisions, dates, and amounts are preserved unchanged.
- Gemini document extraction and Document AI OCR use separately configured Mumbai endpoints. Embeddings use their own location configuration and cannot inherit or silently override the document-processing location.
- Commit `aa13669` remains useful for private page artifacts, chunks, anchors, lineage, leases, lifecycle, and replay. Its Gemini-transcription producer is superseded and cannot supply backfill or Search cutover until replaced and independently reverified.

### State separation and orchestration

- Keep separate state machines for upload session, asset validation, source analysis, intake placement, logical record, document version, candidate verification, relationship evaluation, Search indexing, and notification delivery.
- The compact Hub stage vocabulary is `Queued → Validating → Extracting → Matching → Ready`, with explicit `Needs placement`, `Review`, `Duplicate`, and `Failed` outcomes. `Extracting` exposes the current real substage such as native text, OCR, or AI metadata. It is a projection over actual states and never a percentage.
- Long-running processing is not one open database transaction. Each trusted worker transition commits durable state to the owning `source_analysis_runs`, `document_processing_runs`, page-artifact, or `intake_items` record with expected state/revision, idempotency, attempt/retry, heartbeat, and safe failure data as applicable.
- Every state transition is a server-side domain command or trusted worker transition with expected prior state/revision. The browser cannot arbitrarily update statuses.
- Upload finalization and every mutation that requires asynchronous work commit an outbox event in the same database transaction. A dispatcher leases, delivers, retries, and records attempts. Trigger.dev task acceptance is never the only durable copy of processing intent.
- `outbox_events` is the delivery envelope, not the Hub progress record. `delivered` means that Trigger.dev accepted the instruction; it never means that OCR, extraction, placement, or indexing completed. Outbox payloads remain limited to safe identifiers, versions, scopes, reason codes, and counts and never carry PDF/OCR text, provider payloads, prompts, embeddings, storage paths, signed URLs, credentials, or lease secrets.
- Serve Hub processing state through one organisation-authorized, allowlisted projection over the owning run, Intake, and page-artifact records. It may return safe resource/run IDs, display stage/substage, run state, attempt count, retry time, safe error/recovery code, meaningful timestamps, truthful page totals and native/OCR planned/completed/failed counts, and server-derived available actions. It never exposes internal lease tokens, provider diagnostics, source text, storage identity, or unrestricted worker telemetry.
- Realtime is an invalidation hint, not a second state authority. A permitted change signal causes the selected queue row to refetch that projection; initial load, refresh, focus/reconnect, and another device reconstruct the same state from the database. Realtime loss cannot strand or misstate the workflow.
- For one Document AI request containing multiple pages, show `OCR processing {N} pages…` until the batch succeeds or fails. Show `X of N` only when completed page results have actually been persisted independently; never interpolate time into a percentage or simulated page count.
- Workers validate `org_id`, source lineage, record/Trash state, source version, and idempotency key on every run. Replayed events skip completed stages or resume the failed stage without duplicating candidates, decisions, relationships, deadlines, Activity, or notifications.
- In-flight work stops publishing active projections when the Intake item, document, matter, or client becomes unavailable. Trash integration follows the approved suspension/restoration rules.
- Active queue rows remain in place during realtime updates. Assignment changes the selected row to a success handoff with `Open document` and `Open matter`; it does not disappear under the pointer. Completed rows move to Recent only after navigation, dismissal, or a short stable handoff period.

### Exact duplicates and intentional reuse

- SHA-256 over server-read bytes is the exact duplicate authority. Client hashing may provide early feedback but cannot make the decision.
- Duplicate lookup covers every surviving organisation-local asset reference: active/current and historical document versions, in-progress Intake, Trash, exports/holds where applicable, and replacement candidates.
- Ordinary re-upload of the same PDF never creates another logical document. The user is routed to the existing active document, current Intake row, or Trash restoration root without spending extraction tokens.
- A deliberate **Copy document to another matter** command is the only initial exception. It references the same `file_asset`, creates a new logical document with `copied_from_document_id`, records the justification/activity, and rebuilds document-specific placement, relationships, facts, and Search lineage. It does not upload the bytes again.
- Attaching bytes identical to the current version is an idempotent no-op. Selecting an asset already present in version history cannot create a version cycle; the Workbench explains which version already contains it.
- Similar filenames, references, summaries, or embeddings never hard-block. A calibrated possible-duplicate detector may create Review with side-by-side evidence, but Search embeddings are not its representation.

### Document classification

- Placement and classification are separate decisions. A placement candidate identifies the matter; a classification decision identifies `proceeding` or `supporting` and, optionally, a category.
- Entry points can provide human intent: `Add proceeding` from Timeline and `Add supporting file` from Files. This intent is authoritative but still receives a non-blocking warning if extraction strongly contradicts it.
- Global Intake may auto-classify a recognised procedural GST document as `proceeding` or a recognised evidence class as `supporting` only when the evaluated classification policy passes and no conflict exists. Unknown or conflicting classification is chosen in the Placement panel.
- Multi-financial-year content is not, by itself, a placement blocker. It is a document fact. Matter anchors and contradictions determine placement.
- Proceeding documents enter relationship evaluation and legal-fact candidate projection. Supporting documents still receive validation, OCR/extraction where useful, Search indexing, notes, and Workbench inspection, but do not become Timeline nodes unless promoted.
- Reclassification follows the impact-preview, archival, and reevaluation contract in the File Lifecycle plan. AI never silently changes a human classification later.

### Placement engine overhaul

#### Persisted model

- `placement_runs` records the intake/document source revision, resolver-policy version, extraction/binding version, state, trigger, candidate counts, winner, and safe diagnostics.
- `placement_candidates` records one candidate matter, rank, eligibility, outcome, and a non-authoritative internal score used only to order candidates.
- `placement_evidence` records typed positive or contradictory evidence, verified/provisional state, source locator, normalized value, and weight/reason code.
- `placement_decisions` is append-only and records `auto_assigned`, `assigned`, `reassigned`, `kept_despite_conflict`, `rejected_candidate`, or `unassigned`, including actor/policy, reason, source revision, and prior destination.
- The effective destination remains the logical document's `matter_id`; candidate/run rows explain how it was selected. No AI payload directly updates `matter_id`.

#### Candidate inputs

- Human-declared `intended_matter_id` and intended classification.
- Exact verified matter identifiers: CaseChain `matter_code` and typed external proceeding/portal/case identifiers.
- Exact, normalized, evidence-backed references to existing documents and their reference aliases.
- Verified client identifiers such as GSTIN and PAN.
- Tax period/financial-year overlap, document type and procedural family, issuer/authority, parties, root proceeding identifiers, and date consistency.
- Prior human candidate rejection or explicit keep/move decision.
- Name, filename, fuzzy reference, and semantic similarity may generate or order suggestions only. They are never initial-policy auto-placement evidence.

#### Initial policy

- **User-directed placement:** a valid intended matter is assigned. Contradictory extracted identity is preserved as evidence and creates a focused Review item after assignment; the system does not reroute.
- **Organisation placement policy:** Owner/Admin selects one organisation-scoped initial-placement mode in Operations settings: `manual_suggestions` (the default: evidence-backed suggestions may appear but unassigned Intake is never filed without a human decision), `strong_evidence_auto_place` (allow only the rules below), or `intended_matter_only` (honour user-directed placement and otherwise retain global Intake for a human). New organisations and safe backfills with no explicit choice resolve to `manual_suggestions`; only an explicit Owner/Admin change can enable an automatic mode. The policy affects only initial placement and never authorises an automatic move after a document is assigned. A matter-context upload already carries the user's deliberate destination and is not classified as inferred auto-placement.
- **Automatic placement:** only when the organisation selects `strong_evidence_auto_place`, allow one eligible active candidate with no hard contradiction and either:
  - one unique exact verified matter/external proceeding identifier; or
  - one unique exact referenced-document identity in that matter, supported by page evidence and no incompatible verified client identifier.
- **Suggestion only:** exact GSTIN/PAN plus financial year/tax period, compatible procedure/type sequence, unique client-year candidate, issuer/party overlap, name, filename, fuzzy reference, or semantic similarity. These signals can make the suggested matter excellent without silently filing the initial pilot document.
- **Conflict:** two high-authority candidates, an exact identifier mismatch, a referenced document under an incompatible verified client, an unavailable/trashed intended target, or evidence contradicting an existing human placement. Intake conflicts remain actionable in Hub; conflicts on an already placed document create Review.
- **No match:** keep the item in `Needs placement`; do not invent a client or matter.
- AI may prefill a new-client/new-matter proposal, but creating either record always requires explicit confirmation of the client identity, matter title/code, proceeding identifiers, classification, and destination. Creation and assignment commit atomically so an abandoned form cannot leave orphan records.
- The internal score ranks candidates; it does not independently cross an auto-assignment threshold and is not shown as a misleading percentage. UI shows concise evidence such as `Exact matter code`, `References OIO/… on page 3`, `GSTIN agrees`, or `Financial year only`.

#### Safe fuzzy-reference boundary

- Fuzzy reference matching is an optional **candidate-discovery safety net**, not decision evidence. It exists only to recover likely formatting or OCR variation after deterministic normalized exact matching fails.
- Normalize Unicode, case, whitespace, punctuation, separators, common prefixes, year forms, and known reference aliases first. Exact matching over normalized structured components is preferred to fuzzy similarity.
- Parse a reference into available authority/type prefix, serial or numeric core, year, and suffix. Fuzzy retrieval may tolerate separator changes and narrowly evaluated OCR confusions, but a conflicting numeric core, year, issuer, verified client identifier, or document type is a contradiction rather than a fuzzy match.
- Trigram/edit-distance similarity may retrieve a small candidate set; it never sets eligibility, auto-assigns a matter, resolves a reference, creates a relationship, or raises a candidate above an exact verified anchor.
- Run it only within the authorised organisation and narrow by verified client/issuer/year/type when those facts exist. Multiple plausible candidates remain explicitly ambiguous.
- Present it to users as `Possible reference match`, showing the extracted reference, candidate reference, differing characters/components, supporting context, and source page. Do not show a generic similarity percentage.
- Fuzzy matching can be disabled independently. It ships only after OCR-corruption and near-collision fixtures demonstrate useful suggestion recall without unsafe candidate disclosure; production acceptance/rejection metrics determine whether a rule remains enabled.

#### Matter identity correction

- Multiple active matters for one client and financial year are valid. Remove the current unique `(org_id, client_id, financial_year)` assumption after a duplicate-data audit and migration.
- Keep an organisation-unique CaseChain `matter_code`. Add `matter_identifiers` for typed verified external keys with organisation/client/matter lineage, normalized value, issuer/system, verification, provenance, and uniqueness rules appropriate to identifier type.
- Financial year and tax period remain attributes and matching evidence, not matter identity.
- Existing rows retain IDs. Potentially conflated client/year matters are reported for human audit; migration never splits or merges them automatically.

#### Reevaluation and learning

- Reevaluate placement only when an input changes: source extraction version, material human metadata correction, verified client/matter identifier, new candidate matter/document, intended target availability, restore, or explicit scoped retry.
- Recompute candidates in a new immutable run. Do not mutate the prior explanation.
- An unassigned Intake item may auto-place on a later run only if the current initial policy passes and no user decision/rejection blocks it.
- An assigned document never moves automatically. A stronger later candidate creates a `possible_reassignment` attention/Review item with old/new evidence and an impact preview; an authorised user reviews it and explicitly moves the document or keeps the current placement. The attention surface is informational until that human decision.
- Store human outcomes and false-positive/false-negative labels for offline evaluation. Do not perform uncontrolled online learning from a single organisation's decisions. Policy/prompt changes use a versioned, anonymised evaluation set and measured promotion.

### Reference and procedural-relationship overhaul

#### Two distinct layers

- A **reference mention** means the source PDF cites a reference number or another document. It carries exact page/quote/region evidence and may remain unresolved, resolve to one document, or remain ambiguous. It does not automatically appear as a Timeline edge.
- A **procedural relationship** is an effective, directed legal/process relationship between two logical documents. Only effective proceeding relationships drive Timeline graph edges.
- Legal provisions such as statutes, sections, rules, circulars, and notifications remain normalized legal references in the AI/Search domains unless they point to a CaseChain document. They are not document graph edges.

#### Persisted model

- `document_reference_mentions`: source document/version, semantic key, normalized cited reference identity, raw short quote, page/regions, extracted relation wording, resolution state, and optional resolved target.
- `relationship_resolution_runs`: matter/source revision, rule-catalogue version, trigger, state, counts, and diagnostics.
- `document_relationship_candidates`: source/target, proposed type/direction, semantic key, origin (`explicit_reference`, `deterministic_rule`, `ai_extracted`, `manual`), eligibility/state, source revision, and stale/supersession data.
- `document_relationship_evidence`: candidate, typed locator/fact, validation and conflict state, and reason code.
- `document_relationship_decisions`: append-only accept, correct, reject, clear, or archive decision with actor/reason/revision.
- `document_relationships`: the effective directed edge with source/target, type, provenance winner, verification state, lifecycle state, and timestamps. Both endpoints are non-null.
- Missing targets live only as unresolved reference mentions/candidates. Do not create a null-endpoint effective relationship.

#### Relationship types and direction

- Initial typed vocabulary is `responds_to`, `issued_pursuant_to`, `arises_from`, `challenges`, `decides`, `modifies`, `supersedes`, `remands`, `gives_effect_to`, `refers_to`, and `other`.
- Never default an unknown pair to `responds_to`. If the evidence proves only that one document cites another, resolve the reference mention and, when useful, use `refers_to`; do not fabricate procedural semantics.
- The source is the document performing the action expressed by the type, and the target is the document acted upon. UI presents a natural-language direction preview before manual confirmation.
- Versioned deterministic rules may validate compatible document-type pairs and dates, but type sequence alone cannot create a confirmed edge.

#### Resolution and automation policy

- Normalize a cited identity using reference value plus available issuer, document type, date/year, and verified aliases. Raw string equality alone is insufficient when collisions exist.
- Exact target resolution requires one accessible active candidate. Multiple exact candidates remain ambiguous; fuzzy reference matches are suggestions only.
- Relationship resolution applies the same safe fuzzy-reference boundary as placement: fuzzy retrieval may surface possible targets after normalized exact resolution fails, but only a human decision can bind the target or create an edge.
- Auto-confirm a procedural relationship only when the target is unique, both endpoints are active and organisation-compatible, the relationship is intra-matter, page evidence explicitly supports the proposed relation, type/direction passes the versioned catalogue, dates/identifiers have no contradiction, and no prior human rejection/override exists.
- An exact citation without explicit procedural language may resolve the reference mention but does not create a procedural edge. A deterministic type rule can propose an edge for Review.
- Fuzzy matches, progression inference, cross-matter targets, conflicting type/direction, weak OCR evidence, and AI-only relation wording require Review. They never create a routine personal notification unless the Review item is assigned.
- Cross-matter references may open the accessible related document with a clear external-matter label. They do not enter either matter's procedural Timeline automatically. A future explicit cross-matter relationship type can be added without weakening this rule.
- When a later document/reference alias appears, an outbox event reevaluates only unresolved mentions that can match its normalized keys. It does not scan every matter or rewrite confirmed history.

#### Human authority and graph integrity

- Manual create/correct/accept decisions are authoritative. Re-extraction may confirm them but cannot change their type, direction, or endpoints silently.
- Rejected candidates retain a semantic decision key so the same evidence/rule version does not recreate the same Review item. Materially new source evidence can create a new revision linked to the rejection.
- An automated relationship whose source version is replaced or evidence becomes invalid changes to `stale`/`suspended` and enters Review where material; it is not silently deleted. Historical decisions remain auditable.
- Reassignment/reclassification uses the approved consequence preview. Invalid matter-scoped automated edges archive; manual edges require explicit confirmation when the move would make them cross-matter.
- Database and domain constraints reject self-links, cross-organisation endpoints, inactive/purged endpoints, duplicate active source-target-type edges, impossible inverse duplicates defined by the catalogue, and procedural edges involving supporting documents.
- Remove the standard `Re-evaluate links` button. Failed relationship stages expose `Retry relationship matching`; platform operations can enqueue a scoped matter/source repair with dry-run counts. The ordinary user never needs a general `Sync` control.

### Document Hub experience

#### Desktop

- Use the authenticated application header for breadcrumbs, account, theme, and global controls. A compact collection workbar below it contains ownership scope, Search, result count, and `Upload PDFs`; it does not repeat selected-document identity. Upload is a collection action, not global application chrome.
- When the organisation has no intake items, show one centered empty workspace with upload guidance/action and no artificial queue/detail panes. Its restrained document-stack motion responds to hover/focus and respects reduced motion; it does not loop decoratively.
- The default populated workspace is one full-width compact table. It shows document identity/classification, equal-width status, uploader name/avatar, source, destination/current stage, and received date.
- Selecting a row opens the approved contextual-sidebar pattern. At wide desktop, preserve an approximately 60/40 table/sidebar split and reduce the table to Document, Status, and Uploaded by because source, destination, received time, and processing context are available in the sidebar. Below the wide split threshold, use full-screen details with a clear Back path.
- The sidebar uses stable `Overview` and `Extracted data` tabs, a Close control, one scrolling body, and a fixed action footer. Its identity block makes document type and semantic legal direction dominant, keeps the filename subordinate, and aligns current status separately. Overview then leads with up to three source-backed key evidence or processing-detail items, followed by one lightweight decision/outcome section for every item: plain state-specific heading, explicit `Decision required` or `No action needed` cue, outcome title, consequence, and a semantic leading rule. Intake details follow. This evidence-before-interpretation order is stable across document states. Extracted data starts with one compact, icon-led AI-verification header and renders complete typed metadata as bounded section panels with quiet headers and dense two-column field grids; each field keeps label, value, and source action together. Do not leave the state as an unstructured sentence, label every state `Needs attention`, apply warning background universally, or spend the prime region on a large generic status card.
- Source viewing is explicit and reversible. `View original PDF` or a cited `Open source · page {n}` action replaces the table with the PDF while the sidebar remains anchored; the interface never grows into a queue/PDF/sidebar triple split. On wide desktop, selection first establishes one stable 60/40 pane-chrome row: the queue workbar and sidebar tabs align at the same vertical origin. Source mode replaces only the left workbar/body with the PDF toolbar/viewer, so the sidebar header, width, scroller, and footer do not jump. The PDF toolbar owns a visible Close (`X`) control that restores the table and preserves the selected sidebar.
- Sidebar open/close uses the shared `150ms` fast duration and smooth easing with no artificial delay. Header, body, and the table's condensed/full column state change together; never restore columns only after the pane has finished closing. The shorter duration is intentional for this dense collection so rows do not feel elastic. Source mode leaves the already-open sidebar stationary. Reduced-motion presentation removes spatial movement and delay. Realtime row updates do not animate position.
- A cited source action opens the exact immutable version/page and highlights the retained source region using normalized coordinates. When coordinates are unavailable, anchor and highlight the best exact text match and disclose that fallback; opening the original PDF without a citation does not fabricate a highlight.
- `Upload PDFs` opens the native file picker directly. Drag-and-drop on the queue is equivalent. Selecting files immediately reserves and uploads them; there is no upload modal or additional Submit button.
- A compact upload tray shows current batch rows, real byte transfer progress, cancel-before-finalize, retry, and per-file errors. Once finalized, rows merge into the durable queue without changing position unexpectedly.
- Ownership scope is a compact `My uploads` / `All uploads` control before Search. It is available only when the user can view shared Intake, remembered per user, and defaults ordinary contributors to `My uploads`. Workflow filters are `Action required`, `Processing`, `Completed`, and `All statuses`; do not use `Recent` as a workflow state. On desktop, Status and other filters that map cleanly to a visible field open from that column heading, with a persistent active indicator and reset path. Search and ownership remain in the workbar. When table headings are absent or the selected split removes a filtered column, preserve the filter and expose an equivalent compact labelled control. Filtering applies in place and never opens a modal, drawer, or separate screen. Global versus matter upload is a context filter/chip, not a tall permanent tab strip.
- When opened from a matter, the header shows a removable `Destination: {matter}` context chip and uploads inherit that intended matter. It never creates a second matter-specific queue model.
- Queue table rows are for identity, comparison, and selection only. Keep every row at the same height and remove tiny row-level action labels; actions belong in the selected sidebar's fixed footer or appropriate tab content. A processing item may include one compact same-line segmented stage marker because stage is comparison context, never a fabricated percentage. If selected, its row marker yields to one compact processing summary stating the current work, a truthful completed-work fact, and whether user action is required; do not repeat a fully labelled stage rail in the sidebar. An active collaborator claim replaces secondary row metadata with a quiet named activity label and restrained live dot; it becomes a compact structural notice in the sidebar because it changes action availability.
- The Overview tab has a deliberate dynamic-artifact budget: one state-specific summary and at most three key evidence items. Every item uses the same compact schema—type, primary value, short explanation, and explicit source-page action. Complete extracted metadata remains available in predictable sections on the Extracted data tab.
- For unassigned Intake, Placement occupies the stable action/current-state contract: recommended matter and evidence, searchable alternative matter, classification, and `Assign document`. A separate **Create client and matter** proposal expands only when no valid record exists. `Discard upload` is isolated in the More/danger region, not placed beside the positive choices.
- Do not use the current square `Take action` modal. Multi-step client/matter creation uses a wide side sheet or dedicated route with reviewable values and horizontal desktop actions; destructive discard uses the shared confirmation dialog.

#### Mobile

- Use one principal queue scroller. Selecting an item navigates to a full-screen detail route with a compact sticky identity/status header and preserved Back position.
- The sequence is queue → details → source. Source opens only from `View original PDF` or a cited source-page action, and Back returns to the same details context before returning to the queue. Only the active mode scrolls. Persistent primary placement action may use the shared bottom action bar without covering source controls.
- Upload uses the platform file picker/camera-file capabilities permitted for PDFs and shows the same durable batch rows. All desktop decisions remain available; ordinary filters expand in place near the queue controls without navigating to another screen.

#### Queue behavior

- Active items are sorted by action need and creation time on initial load, but realtime stage changes update in place. A `New uploads` affordance handles arrivals above the current viewport.
- Duplicate, conflict, and failure rows state what happened; their selected sidebars offer the appropriate verb: `Open existing`, `View in Trash`, `Choose matter`, `Review conflict`, `Unlock and retry`, or `Retry extraction`.
- An assigned handoff shows its destination in the row and exposes `Open document` in the selected sidebar. `Completed` retains bounded assignment/failure history for operational reassurance. Activity remains the full historical record.
- Empty state explains global versus matter-context intake and provides `Upload PDFs`. A restrained upload/document motif may respond to hover or focus, but it must not loop decoratively or claim that every uploaded tax document belongs in a Timeline.

#### Shared visibility, action authority, and concurrency

- Document Hub is a capability-scoped organisation Intake workspace, not a feed visible to every account. Owner/Admin and an Associate granted `intake.manage_shared` can see `All uploads`; that grant includes standard shared-triage actions on visible Intake rather than creating a largely useless view-only global queue. Ordinary Associates see `My uploads` by default and do not receive `All uploads`; a Viewer does not gain unplaced-intake visibility merely from the Viewer role. The initial release does not issue a separate shared-queue-view-only grant.
- Queue visibility and action authority still remain distinct at the item boundary. The secured projection returns only records the caller may inspect and an allowed-action set per item. A shared-intake operator may perform ordinary existing-Matter placement, duplicate handling, recoverable retry, and other approved standard triage; an item requiring creation of a Client/Matter, reassignment of a filed document, pre-expiry takeover, or privileged recovery returns an explicit Owner/Admin escalation state rather than a dead control.
- Opening a row, sidebar, extracted data, or PDF is observational and never claims work. A claim is requested only when the user presses an explicit verb such as `Start conflict review` and the server successfully opens the multi-step consequential workflow. Merely clicking every queue row therefore claims nothing.
- Each membership may hold at most one active Document Hub claim in an organisation. Starting work on a second item first shows `Release {current item} and start this review?`; confirmation performs one server transaction that releases the prior claim and acquires the new item, while cancellation leaves both unchanged. The acquire command serializes on the membership and item, clears expired state, revalidates capability and source revision, and cannot be bypassed by multiple tabs.
- An active claim is a visible 10-minute soft lease containing actor, start, last meaningful activity, expiry, and source revision. While that resolution UI is active, source navigation, decision-draft changes, or an explicit `Continue review` action may renew the lease to 10 minutes from authoritative database time through a throttled authenticated command; a merely open or background tab does not renew it. The UI warns when two minutes remain.
- `Cancel review`, returning to the queue, closing the selected workflow, navigating to another application route, and signing out all attempt an immediate authenticated release. Moving between details and the source PDF for the same review retains the claim. Browser close, device sleep, crash, network loss, and process termination are not reliable release signals; the client may attempt best-effort cleanup but correctness relies on server expiry no later than 10 minutes after the last meaningful activity. A same-user reload/tab may resume the one existing claim rather than create another. Acquire, renewal, release, expiry, switch, or authorised confirmed takeover is audited.
- Claim acquisition, renewal, release, current-state reads, and final mutations use authenticated database/RPC commands over ordinary request/response transport and do not require Supabase Realtime. Realtime is only an invalidation hint. If it is refused, disconnected, disabled, or over quota, the workspace shows truthful paused freshness, refetches the visible selected claim every 30 seconds with jitter and the queue every 60 seconds while foregrounded, and always refetches on focus and immediately before an action. Hidden pages do not poll.
- Every final mutation carries an idempotency key and expected authoritative revision. The first valid commit wins; a stale second submission cannot overwrite it and receives the resolved actor, time, and current outcome. Realtime only prompts a refetch of that server projection.
- Another user's claim appears in the row and selected sidebar. Remote completion changes the row in place into a stable completion/handoff receipt such as `Resolved by {name}` with destination/open actions. It does not silently disappear; removal from the active view occurs only after explicit navigation/dismissal or the bounded handoff interval.

### Shared Document Workbench

#### Component contract and layout

- Implement one `DocumentWorkbench` with a typed subject:
  - `{ kind: 'intake'; intakeItemId; assetId }`, or
  - `{ kind: 'document'; documentId; versionId?: string }`.
- Server loaders derive organisation, access, current/historical/Trash state, signed asset access, capabilities, and source locator. Browser callers do not supply bucket paths, organisation IDs, or permission booleans.
- When explicitly opened in source mode, desktop uses a resizable PDF/inspector split, initially approximately 64/36. The outer workspace does not scroll. Viewer and inspector each have one independently scrolling body beneath stable pane headers; the selected width may be remembered per user. This source composition is not the Document Hub's default selection state.
- At constrained desktop/tablet widths, keep the PDF primary and open the inspector as a drawer. Mobile uses one active full-screen mode and one principal scroller.
- Stable Workbench chrome shows document identity, version/historical state, processing/classification, matter context when assigned, and primary task. Secondary operations live in a labelled More menu.

#### PDF viewer

- Render pages in a continuous vertical scroller with virtualization and reserved dimensions. Next/previous changes the active page but is not the only way to move through the document.
- Provide current page/total with direct page entry, zoom in/out, Fit width, Fit page, rotate, document text search with result navigation, and a thumbnail/outline drawer. Use visible labels where an icon is ambiguous and accessible tooltips for permitted compact controls.
- Keep the toolbar outside the page scroller. Preserve page/scroll context when opening and closing the inspector or switching between desktop/mobile presentations.
- Accept a `DocumentSourceLocator` on open and navigate to the exact immutable version, 1-based PDF page, and normalized highlight regions/text anchor. Search, Notes, Review, Activity, and Case Brief use this same contract.
- Show native text when available and OCR text boxes only for pages that need them. Disclose `OCR text`, low-confidence OCR, or `Text unavailable`; do not imply scanned text is exact.
- Loading, encrypted, malformed, unavailable historical asset, expired signed access, rendering failure, and partial OCR states have distinct messages and recovery paths.
- Download/open-original uses a short-lived version-authorized URL. Trash remains viewable but read-only under the approved danger-context strip.

#### PDF quotation to note

- Text-layer selection creates a proposed quotation with exact text, prefix/suffix context, page, and normalized page-coordinate regions derived from rendered text spans.
- OCR-layer selection uses the retained word boxes and stores the OCR text plus quality. When usable text selection is unavailable, `Select region for note` lets the user draw one rectangle on one page and create a region-only quotation. Initial multi-page freehand selection is out of scope.
- A quotation stores `document_id`, immutable `document_version_id`, 1-based page, normalized regions relative to the unrotated PDF page, optional exact/OCR excerpt, prefix/suffix, selection method, OCR/text version, and a short display snapshot. It never relies on a global browser event or current page state.
- Note creation receives the structured locator directly through component state/command input. The note domain persists it in `note_document_quotes` and validates the caller's access and page bounds.
- Clicking a quotation opens the exact historical version if necessary, scrolls to the page, and overlays the normalized region highlight after any zoom/rotation. If text/OCR changes, the region remains the fallback. If the asset was purged, render a non-disclosing unavailable-evidence tombstone.
- Copying quoted text into the note is optional; the source locator is mandatory. Long extracted text is shortened for display without altering the evidence anchor.

#### Inspector information architecture

- Present one quiet panel-level notice where AI-derived fields are shown: `AI-generated · Verify critical details`. Its helper text says `Dates, amounts and identifiers may be inaccurate. Compare important information with the source document.` Keep it visually subordinate and do not repeat it beside every field.
- Show field-level `Needs review` only for an actual exception: no or ambiguous canonical source match, invalid deterministic value, OCR/handwriting conflict, conflicting source, or a consequential Tier C action. The normal workflow must not ask the user to validate every extracted field.
- **At a glance:** effective title/type/reference/date/direction, concise cited summary, client/matter placement, classification, and processing/readability warnings.
- **Deadlines:** every extracted or manual deadline tied to the document, including overdue/missed dates, verification state, source page, and owning matter action. Relative unresolved periods are labelled and never presented as calendar deadlines.
- **Financial facts:** typed stated demand/tax/interest/penalty/pre-deposit/payment or other events, INR formatting, allegation/finding/operative context, verification, and evidence.
- **Parties and legal references:** GSTIN/PAN/party/issuer and normalized act/section/rule/circular references with original wording and provenance.
- **Relationships and references:** effective procedural relationships first, unresolved/ambiguous mentions and Review actions second, each with direction and evidence.
- **Notes:** document thread preview and create-note action, including quotation state. The full premium Notes architecture remains in its own plan.
- **Document record:** class/category, origin, uploader, created time, current/historical versions, file size/pages, replacement reason, and content/Search availability.
- **Provenance and processing:** field-level effective source, human correction, AI model/prompt/schema version where authorised, stage failures, and scoped retry. Hide raw provider payloads, embeddings, hashes, object keys, and operational secrets.
- Put the most consequential current facts above exhaustive metadata. Sections are collapsible and preserve user state; missing data says `Not available` or `Not extracted`, not a wall of empty cards.

#### Workbench actions

- Primary actions are context-specific: `Assign document` for Intake, `Add note` while quoting, `Resolve review` when opened from Review, or no forced action for ordinary reading.
- Normal assigned-document actions are `Edit details`, `Move or copy`, `Change classification`, and `Move to Trash`, subject to capability, verified implementation and release policy. A metadata-only record exposes `Attach PDF`. `Replace PDF` is a later gated More action, deferred for the pilot. Consequential actions use impact previews and domain commands.
- `Retry {failed stage}` is available only when a stage is failed/retryable. `Re-extract metadata` or `Retry relationship matching` appears in More with scope and consequence; there is no generic `Sync` or ordinary `Re-evaluate links` action.
- Every mutation is disabled in Trash/read-only/historical-version contexts as appropriate. Historical versions may still be viewed, quoted, and compared according to access policy.

### Permissions and security

- Viewer can inspect authorised active and Trash-readable documents/versions and quotations but cannot upload, assign, classify, retry, edit, replace, move/copy, or trash.
- Associate can upload, place Intake, correct permitted metadata, manage permitted relationships, reclassify, move/copy, retry recoverable stages, and trash/restore individual documents under the approved capability rules.
- Owner/Admin escalation inside Document Hub is contextual to the selected intake item: approve creating a new Client/Matter from that upload, resolve an assignment/reassignment conflict, confirm takeover of an active review when operationally necessary, or run an explicitly offered privileged intake recovery. These are not persistent global Hub controls. Organisation placement policy belongs in Organisation settings, permanent purge belongs in Trash, and tenant administrators cannot grant platform quota exceptions or bypass entitlements.
- Every table includes `org_id` and constrained lineage. RLS and server/domain commands enforce permissions. Service workers revalidate organisation/source lineage rather than trusting event payload IDs.
- Signed PDF access is resolved from an authorised intake item or document version with a short expiry. Storage paths, hashes, OCR text, embeddings, and quarantine diagnostics are not returned in ordinary list payloads.
- Text/OCR/PDF content is untrusted input. Extraction and matching prompts ignore embedded instructions; rendered PDF links/annotations follow safe browser policy.
- Cross-matter results and duplicate conflicts never disclose inaccessible document identity, filename, snippet, matter, or counts. Return a generic conflict and administrator escalation route.

### Activity, Review, and notification integration

- Append Activity for upload accepted, validation/processing completion or material failure, placement decision, classification, version attachment/replacement, human metadata correction, relationship decision, reclassification, reassignment/copy, Trash, and restore. High-frequency stages and retries remain operational telemetry.
- Placement insufficiency remains in Hub. Create Review only for possible duplicate, conflicting high-authority placement, possible reassignment, inferred/conflicting relationship, consequential metadata/deadline/financial exception, or supported recovery decision.
- Review items carry the exact source version, placement/relationship run revision, evidence locators, allowed resolver, and impact. Stale decisions cannot apply.
- Do not notify for upload success, extraction success, ready-to-place ordinary Intake, auto-assignment, exact automatic relationship, Search indexing, or routine completion.
- Notify only under the approved allowlist: assigned Review/failure, direct responsibility, verified deadlines, mentions, security, or administrator operational risk. Hub counts and inline realtime state provide routine awareness.

### Observability and cost controls

- Record per-stage run ID, source/asset/version, policy/model/schema version, attempts, duration, safe error code, provider tokens/billable units, and output counts without legal text.
- Platform operations sees queue depth, oldest age, stage latency/failure rate, retry exhaustion, OCR/extraction/embedding usage, duplicate savings, auto-placement rate, manual correction rate, relationship acceptance/rejection rate, and orphaned asset/reference checks by organisation without content.
- Track placement and relationship quality by rule version: coverage, auto-decision count, sampled accuracy, human overrides, conflicts, and false-negative labels. Pause an auto rule without deploying code.
- Reuse source analysis only for the same organisation, immutable asset hash, extraction model/prompt/schema/catalogue version, and page/OCR content version. Matter-specific and human-effective projections are never shared blindly.
- A provider outage leaves validated files accessible, keeps Global Intake in a retryable state, and allows manual placement/classification. Exact duplicate checks, PDF viewing, native-text extraction, and existing search continue where possible.

### Visual approval boundary (approved 2026-09-05)

- The fixture-only concept at `/dev/document-hub-workbench-concept` presents
  the approved operational queue and shared Workbench direction without
  production data, routes, APIs, uploads, storage, permissions, or real PDF
  rendering. The revised desktop concept rests on a full-width table, opens an
  adaptive 60/40 table/sidebar composition after selection, and replaces the
  table with PDF/sidebar only after an explicit original/source-page action.
  A truly empty Hub has no artificial panes. Its phone flow is queue → details
  → source.
- Local fixture controls cover queue states, upload-tray progress, quotation
  context, Viewer read-only behavior, loading, empty, error, long content,
  light/dark, and responsive layout. Consequential controls explicitly report
  a local preview result and make no mutation.
- The visual contract deliberately limits structural surprise: selecting a
  document opens one familiar contextual sidebar and removes redundant table
  columns; only a labelled, reversible source action replaces the table.
  Ordinary filters apply in place. Overview carries one state-specific summary
  and at most three evidence items; complete extracted metadata remains in its
  stable tab, and cited navigation highlights the exact retained source region.
- The user approved this production visual direction on 2026-09-05 after
  iterative desktop review and a final 460px responsive verification. The
  mobile queue showed no horizontal overflow; queue → details → source,
  preserved return context, readable Overview/Extracted data, fixed actions,
  and fitted PDF controls all remained intact. Visual approval no longer blocks
  live Document Hub or shared Workbench UI work; the secured readers, commands,
  source locators, and acceptance tests below remain mandatory.

## Implementation Plan

### Verified checkpoint: canonical Document Hub route cutover (2026-09-05)

- `/documents` is the live authenticated collection reader for the existing
  canonical Intake queue. `/inbox` is redirect-only compatibility, preserving
  only scalar `matterId` and `intakeId` state; sidebar, matter-upload,
  duplicate-intake, and mutation-refresh callers use `/documents`.
- This closure retains the organisation-fenced `intake_items` projection and
  existing server/RPC command boundaries unchanged. It introduces no migration,
  staging-table reader, placement policy, or Workbench contract.
- Focused developer verification and independent read-only QA passed. Local
  broad TypeScript/test execution remains limited by the pre-existing mixed
  dependency tree; no package recovery or install is part of this tranche.
- Next Document Hub tranche: replace the legacy queue/modal presentation with
  the approved secured queue → details → source Workbench closure, retaining
  the live `/documents` route and canonical Intake actions.

### Verified checkpoint: canonical assigned-document reader (2026-09-05)

- `/documents/{documentId}` is the live assigned-document reader. Active
  records resolve by authorised canonical ID; Trash requires the exact scalar
  Matter lineage already verified by the Trash projection and signed-version
  grant. The legacy nested Matter route is redirect-only compatibility.
- Active Matter, Notes, Search, notification, Intake-duplicate, and Trash
  callers now route canonically without weakening active/Trash access fences.
  Exact canonical readers are invalidated after their relevant document,
  relationship, review, financial-year, reprocess, and Trash mutations.
- Focused developer checks and adversarial QA passed after consolidated
  lineage/caller repairs. The next closure remains the approved secured
  queue → details → source Workbench presentation; viewer state restoration
  (page/highlight/return context) belongs to that later stateful UI contract.

### Verified checkpoint: secured Document Hub queue → details → source (2026-09-05)

- `/documents` now mounts the secured canonical Intake Workbench rather than
  the legacy Inbox client. Its unselected desktop queue is full width;
  selecting an allowlisted `intakeId` opens a 60/40 queue/detail composition.
  The explicit signed-source action replaces only the queue pane on desktop;
  mobile preserves queue → details → source with labelled return actions.
- The closure reuses the existing canonical upload modal, signed intake URL,
  assignment, discard, duplicate-resolution, route, and idempotency contracts.
  It introduces no new projection, migration, RLS rule, RPC, browser-supplied
  authority, or policy. Ready-only PDF/assignment actions and terminal-state
  handling remain derived from `canonicalIntakeActions`.
- The queue retains every record supplied by the authorised canonical reader,
  including matter-intended items. It has a native upload entry, URL-backed
  selection, safe refresh/error behavior, stable desktop pane headers and
  scrollers, semantic table/button controls, fixed-width status badges, and
  accessible empty/long-content states.
- Focused developer checks, a consolidated remediation, and fresh final
  read-only QA passed. Full TypeScript/ESLint remain unavailable because of the
  pre-existing broken dependency links; no dependency recovery was performed.
- Next Document Hub action: add only a separately approved live consumer for
  shared version/source-locator state (such as page/highlight restoration) once
  its secured loader and source-locator contract are ready. Do not create a
  page-local viewer policy in the meantime.

### Verified checkpoint: canonical version and page source locator (2026-09-05)

- The live `/documents/{documentId}` reader now accepts only scalar allowlisted
  `version` and positive `page` source state. It proves the requested version
  belongs to the exact canonical document before issuing either the active or
  exact Trash signed grant, then restores the one-based page in the shared
  viewer after its PDF page count is known. Malformed, repeated, unavailable,
  or foreign values fail closed without exposing a storage locator.
- This is deliberately page restoration only: there are no quote/region
  highlights, text search, Notes/Review producers, return-context policy, or
  second viewer. The shared viewer contract and static design-system specimen
  record its server-derived initial-page and accessible toolbar behavior.
- Focused developer tests and fresh adversarial QA passed. The next shared
  Workbench stage must be selected only with a secure downstream source-locator
  producer/consumer; retain the verified canonical reader in the meantime.

1. **Freeze fixtures and state catalogue.** Capture current global upload, matter upload, duplicate, manual/auto assignment, auto-create, reprocess, link/pending-link, move/copy, reclassify, viewer, quote, Trash, and failure behaviors. Add representative GST PDFs for exact/colliding references, multiple matters in one FY, multi-FY documents, scans, encrypted/malformed PDFs, conflicting GSTIN, missing targets, self-reference, and replacement versions.
2. **Resolve cross-plan source analysis.** Amend AI provenance so immutable source analysis can be asset-scoped during Intake and bound to a document version at placement; retain document-specific effective candidates/decisions. Amend File Lifecycle events/tables accordingly before schema work.
3. **Add the additive ingestion foundation.** Introduce/complete `file_assets`, `upload_sessions`, `intake_items`, `source_analysis_runs`, page/OCR artifacts, `document_versions`, analysis bindings, processing-stage runs, and outbox/dispatch state with RLS, lineage constraints, idempotency, reservations, and safe errors.
4. **Build upload reservation/finalization.** Move browser transfer to bounded direct-to-private-storage contracts, enforce the approved 25 MB/default and organisation/platform quotas, finalize server-observed object data, and implement cleanup/expiry. Do not remove legacy bucket reads yet.
5. **Build validation and duplicate resolution.** Add PDF signature/readability/encryption/page checks, SHA-256, quarantine adapter, all-lifecycle duplicate lookup, replacement/copy special cases, and non-disclosing conflict results. Ensure duplicate decisions occur before paid AI.
6. **Split analysis into resumable stages.** Implement versioned native page text/geometry and quality routing, selective Mumbai Enterprise OCR with word boxes and structured table cells/geometry, asset-scoped Gemini metadata-only extraction with English synopsis/display normalization, source-span/cell verification, Zod/domain validation, reusable artifacts, usage records, and document-version binding. Migrate Gemini structured generation to `@google/genai`. Remove Gemini transcript fields and the staged/raw-metadata fast-path heuristic after the corrected pipeline is verified and cut over.
7. **Introduce placement storage and policy.** Add runs/candidates/evidence/decisions, matter identifiers, policy registry, resolvers, conflict production, and audited create-client/matter proposal. Remove client-year uniqueness only after audit/backfill and replacement identity constraints exist.
8. **Migrate both upload paths.** Route global and matter upload through sessions/Intake. Matter intent assigns after validation; global Intake uses placement. Assignment references the asset without bucket copy and commits logical document/version/decisions/events atomically.
9. **Introduce reference/relationship storage and engine.** Backfill existing links into explicit provenance categories, add mentions/runs/candidates/evidence/decisions/effective relationships, seed the versioned type/rule catalogue, and implement exact resolution, review policy, event-driven pending resolution, rejection memory, and graph integrity constraints.
10. **Cut over downstream projections.** Move deadlines, financial candidates, Search chunks, Activity, Review, Matter Timeline, reclassification, reassignment, copy, replacement, Trash, and restore to source-version/run contracts. Stop consumers from parsing arbitrary `raw_metadata` or legacy `document_links`.
11. **Build the shared Workbench foundation.** Implement canonical loaders/routes, continuous virtualized viewer, stable toolbar, thumbnails/search, signed-version access, source-locator navigation/highlights, responsive split/drawer/mobile modes, and explicit scroll ownership.
12. **Build quotation and inspector contracts.** Implement text/OCR/region selection, normalized coordinate conversion, `note_document_quotes`, historical-version resolution, and the structured inspector sections/actions. Integrate Notes through typed props/commands rather than global events.
13. **Rebuild Document Hub.** Replace modal upload with native picker/drop plus durable tray, implement stable queue filters/list-detail, inline Placement panel, create-record side flow, isolated discard, realtime handoff, mobile detail routes, and complete loading/empty/error/partial states.
14. **Remove misleading controls and producers.** Remove `Sync`, ordinary `Re-evaluate links`, single-page-only viewer paths, routine processing notifications, current Take Action modal, broad organisation reevaluation loops, and page-local PDF/metadata variants after equivalent capability passes.
15. **Backfill and shadow.** Migrate `staged_documents`, files, current documents, hashes, raw extraction, links, pending references, and note quotes in resumable organisation batches. Run old/new placement and relationship engines in shadow, compare decisions, and require quality/security gates before enabling automation.
16. **Cut over and contract legacy storage.** Switch canonical routes and workers, verify asset reachability/current versions/run coverage, stop dual writes, retain rollback adapters for a bounded window, then remove legacy staged tables, raw-path signing, bucket-copy assignment, overloaded statuses, legacy relationship writes, and obsolete storage paths in separate migrations.

## Interfaces and Data Changes

### Core ingestion additions

- `source_analysis_runs`: organisation, immutable asset, page/OCR content version, provider/model/prompt/schema/catalogue versions, state, idempotency, restricted validated output, usage, safe error, and timestamps.
- `source_field_candidates`: source analysis run/asset, semantic key, field path/type, normalized typed value, page/quote/region evidence, confidence, validation state/errors, and timestamps. These are immutable observations about the PDF, not effective document fields.
- `source_pages`: asset/analysis, 1-based page, PDF geometry/rotation, native/OCR availability and quality, text-content hash, and restricted text/box artifact reference.
- `document_version_analysis_bindings`: organisation, document version, source analysis run, binding reason, creator/time, and unique compatible binding constraint. Document-level candidates reference the applicable source candidate/binding so copies may have independent human decisions without repeating source extraction.
- Extend `document_processing_runs` to stage-level attempts/dependencies and `intake_items` to classification/placement run and stable failure/action state. Persist only real current substage and progress facts: planned/completed/failed page counts are allowed when backed by committed page work, while estimated percentages and timer-derived completion are prohibited.
- Add an organisation-authorized Document Hub processing-status projection/RPC over `intake_items`, the active source/document processing runs, and aggregate page artifacts. This is the browser status contract and is safe to refetch after a Realtime hint; neither `outbox_events` nor private run/page tables become direct browser APIs.

### Placement additions

- `matter_identifiers`: organisation/client/matter, kind, normalized/display value, issuer/system, verification/provenance, source locator, lifecycle, and timestamps.
- `placement_policy_versions`: version, enabled rules, evaluation reference, rollout state, and timestamps.
- `placement_runs`, `placement_candidates`, `placement_evidence`, and append-only `placement_decisions` as defined above.

```ts
type PlacementOutcome =
  | 'user_directed'
  | 'auto_assigned'
  | 'needs_placement'
  | 'conflict'
  | 'possible_reassignment'

type PlacementEvidenceKind =
  | 'intended_matter'
  | 'matter_code_exact'
  | 'external_proceeding_id_exact'
  | 'referenced_document_exact'
  | 'gstin_exact'
  | 'pan_exact'
  | 'tax_period_overlap'
  | 'financial_year_overlap'
  | 'procedure_compatible'
  | 'issuer_party_overlap'
  | 'name_similarity'
  | 'filename_hint'
  | 'reference_fuzzy'
  | 'semantic_similarity'
  | 'identifier_conflict'
  | 'target_unavailable'
```

### Reference and relationship additions

- `document_reference_mentions`, `relationship_rule_versions`, `relationship_resolution_runs`, `document_relationship_candidates`, `document_relationship_evidence`, append-only `document_relationship_decisions`, and effective `document_relationships`.
- Legacy `document_links` remains readable during backfill. Every row receives an explicit disposition: effective manual/confirmed relationship, pending reference mention, proposed inference, rejected, archived, or invalid self/cross-tenant record.

```ts
type DocumentRelationshipType =
  | 'responds_to'
  | 'issued_pursuant_to'
  | 'arises_from'
  | 'challenges'
  | 'decides'
  | 'modifies'
  | 'supersedes'
  | 'remands'
  | 'gives_effect_to'
  | 'refers_to'
  | 'other'

type RelationshipVerification = 'human' | 'policy_confirmed' | 'provisional'
type RelationshipLifecycle = 'active' | 'stale' | 'suspended' | 'archived'
```

### Workbench and source locators

```ts
type DocumentSourceLocator = {
  documentId: string
  documentVersionId: string
  pageIndex?: number
  quote?: {
    exactText?: string
    prefix?: string
    suffix?: string
    selectionMethod: 'native_text' | 'ocr_text' | 'region'
    textVersion?: string
    regions: Array<{
      pageIndex: number
      x: number
      y: number
      width: number
      height: number
    }> // normalized 0..1 coordinates on the unrotated PDF page
  }
}

type WorkbenchSubject =
  | { kind: 'intake'; intakeItemId: string }
  | { kind: 'document'; documentId: string; versionId?: string; locator?: DocumentSourceLocator }
```

- `note_document_quotes`: organisation, note/message, document/version, page, selection method, exact/OCR display excerpt, prefix/suffix, normalized regions, text/OCR version, creator/time, and availability state.
- Workbench loaders return typed identity, source access, inspector projections, processing states, and server-derived capability keys. They never return raw object keys, embeddings, or unrestricted provider output.

### Commands and events

- Commands: reserve/finalize/cancel upload; retry upload/stage; discard Intake; choose classification; assign Intake; approve client/matter proposal; keep/move placement conflict; attach/replace version; copy/move/reclassify/trash document; accept/correct/reject/archive relationship; create note quotation; obtain signed version access.
- Events: `upload.reserved`, `intake.uploaded`, `asset.validated`, `asset.duplicate_detected`, `source.analysis_completed`, `source.analysis_failed`, `placement.evaluated`, `intake.assigned`, `placement.conflict_detected`, `document.version_bound`, `reference.mention_resolved`, `relationship.proposed`, `relationship.confirmed`, `relationship.rejected`, `relationship.suspended`, `document.processing_completed`, and scoped failure/retry events.
- Event payloads contain identifiers, policy/source versions, safe reason codes, and counts—not PDF text, quotations, signed URLs, embeddings, or credentials.

## Testing and Acceptance Criteria

- Reproduce and close the reviewed empty-success refresh, late source-sign response, historical-source/current-inspector mismatch and narrow-viewer defects using real state transitions and production components. Quotes persist the exact selected version; no global quote event supplies ambiguous current-page state.
- A real deployed upload exceeding 4.5 MB and at the 25 MiB application boundary succeeds through direct Storage transfer. Retry/cancel/expiry and reload-with-file-reselection behavior match the lifecycle contract and never duplicate finalization or paid work.
- Distinct same-client/year matters can be created, assigned and restored while genuine identifier conflicts remain explicit; dropping the old index alone does not satisfy acceptance.

### Pipeline and storage

- Global, matter, replacement, later-attachment, and intentional-copy fixtures all use the same upload/asset contracts. Ordinary assignment/reassignment performs no storage download, copy, move, or re-upload.
- A browser disconnect after upload/finalization and an application crash after database commit both leave recoverable durable work. Outbox replay and worker retry create exactly one logical document/version and one set of candidates/events.
- Server validation rejects or safely handles wrong MIME/extension, malformed, encrypted, oversize, empty, suspicious, missing, and unreadable PDFs. The approved 25 MB default, reservations, organisation quota, and platform guard withstand concurrent uploads and forged client metadata.
- Exact duplicate detection covers active, historical, Intake, and Trash before AI. Renaming, forged hashes, or alternate routes cannot bypass it. Intentional Copy reuses one asset and rebuilds matter-specific state.
- Provider outage or OCR/extraction failure never loses a validated asset. Manual placement remains possible where safe; retries are scope-specific and idempotent.
- Every stage transition and status projection has unit/state-machine tests, RLS tests, stale revision tests, and safe failure codes. No combined status can claim `Ready` while the source itself is unavailable.
- Dispatch acceptance while the owning run remains queued/running does not advance the Hub to `Ready`. Tests cover outbox replay, expired leases, duplicate delivery, retry scheduling, provider failure, refresh/reconnect, and Realtime loss while proving that the database projection remains authoritative.

### Placement quality and integrity

- Tests cover intended matter, exact matter/external key, exact cited document, same reference under multiple matters, GSTIN conflict, GSTIN+FY only, multiple matters in one FY, multi-FY source, fuzzy/name/filename/semantic hints, unavailable/Trash targets, no match, later stronger evidence, and concurrent user/worker decisions.
- Fuzzy-reference fixtures cover punctuation/spacing variants, year formats, known OCR confusions, one-character numeric collisions, different issuers, different clients, multiple plausible targets, and adversarial near matches. They prove that fuzzy results are explainable suggestions only and cause no mutation.
- Native/OCR routing fixtures cover good native English/Hindi/mixed pages, empty and broken text layers, large image regions, stamps, handwriting, rotation, poor scans, and representative tables. They measure missed and unnecessary OCR, source-text accuracy, reading order, page/word anchors, latency, and billed pages without allowing Gemini to supply the transcript.
- Gemini extraction fixtures require an English neutral synopsis and English display metadata, retain original evidence for transliterated proper names, preserve exact identifiers/numbers, and reject any provider response containing page transcripts or OCR word streams.
- Critical metadata is automatically eligible only when its typed value resolves to the quoted canonical page span or structured table cell and its field validator passes. Date-format normalization compares real calendar values; GSTIN/reference/amount normalization preserves raw evidence; absent, repeated, ambiguous, invalid, or one-digit-conflicting values fail closed into one grouped Review exception.
- Regional configuration tests prove document extraction and OCR use `asia-south1`, embeddings have an independent location, and no India processing path silently falls back to a US or global endpoint.
- Initial auto-placement occurs only for the approved strong-anchor cases with one eligible candidate and no contradiction. GSTIN+FY, fuzzy, name, filename, and semantic-only cases remain suggestions.
- Fresh-organisation, unset/backfill, and policy-reversion fixtures prove `manual_suggestions` is the fail-closed default: global uploads remain in Intake until a human assigns them, and neither a worker nor a browser-supplied mode can enable automatic placement without the current stored Owner/Admin decision.
- A human-directed matter upload is never rerouted by AI. A conflict creates one evidence-backed Review item without blocking PDF access.
- An assigned document never moves on reevaluation. Possible reassignment requires a current, typed Review decision and impact preview.
- Client/matter proposal creates no record before confirmation and commits client/matter/document assignment atomically. Race tests resolve existing identifiers without orphan or duplicate records.
- Removing client-year uniqueness preserves existing IDs and permits two legitimate active matters for the same client/FY while organisation matter-code/external-key rules prevent actual duplicates.
- Shadow evaluation includes at least 100 adjudicated placement examples and reports coverage, suggestion Recall@3, auto-placement precision, conflicts, and abstention. Require 100% precision on critical fixtures and at least 98% adjudicated auto-placement precision before enabling an automatic rule in pilot; otherwise keep it suggestion-only.

### Relationships

- Exact citation without procedural language resolves a reference mention but does not fabricate a Timeline edge. Unknown type pairs never default to `responds_to`.
- Tests cover explicit relation language, exact/fuzzy/colliding/missing references, date/type/identifier conflicts, later target arrival, cross-matter reference, supporting documents, self-reference, inverse/duplicate edge, replacement version, reassignment, reclassification, Trash/restore, manual override, and prior rejection.
- Self-links and cross-organisation links fail at database and command layers. Only active effective proceeding relationships drive the Timeline.
- Fuzzy/progression/AI-only suggestions require Review. Exact automatic relationships meet every evidence/policy condition and remain fully explainable.
- Reprocessing cannot overwrite a manual relationship or recreate an unchanged rejected suggestion. Event-driven pending resolution touches only relevant unresolved mention keys.
- Backfill gives every legacy link an explicit disposition and reports invalid, ambiguous, pending, confirmed, inferred, self-link, cross-matter, and unmigrated counts before cutover.
- A versioned relationship evaluation set reaches 100% precision on critical direction/type fixtures and at least 97% precision for auto-confirmed relationships before automation is enabled; lower-quality rules stay proposal-only.

### Hub and Workbench

- Clicking `Upload PDFs` opens the native picker directly; drag/drop and multi-file selection create durable rows without a modal or Submit step. Transfer failures and finalized processing are visually distinct.
- Hub queue rows do not jump during realtime stage updates or vanish on assignment. Filters, selected item, matter context, and return navigation are URL-addressable and preserved appropriately.
- Batch OCR renders `OCR processing {N} pages…` from the committed request scope. It renders `X of N` only from persisted per-page completions, shows a safe retry/failure state when applicable, and never displays a timer-derived percentage or simulated progress.
- The Placement pane cleanly separates suggested/existing matter assignment, new client/matter proposal, and destructive discard. Every candidate shows evidence and contradictions without a fake confidence percentage.
- The same Workbench renders an Intake asset, assigned document, historical version, Search passage, Review evidence, and Trash read-only route. No page maintains a separate PDF/metadata viewer contract.
- Continuous scrolling works with long PDFs; direct page entry, zoom, fit, rotate, search, thumbnails, keyboard navigation, and native scroll all work without forcing next/previous clicks.
- Every document passage fixture opens the exact immutable version/page and highlights the expected normalized regions after zoom, rotation, resize, and desktop/mobile layout changes.
- Native-text, OCR-text, and region-only quotations create valid note locators. Clicking the note quote returns to the correct page/highlight; historical replacement preserves the old quotation; purged evidence shows the approved tombstone.
- Inspector shows overdue/missed deadlines, provisional/verified facts, financial context, parties, legal references, relationships, versions, and processing/provenance without reading arbitrary `raw_metadata` after cutover.
- The inspector shows one subtle `AI-generated · Verify critical details` notice for AI-derived content, field-level warnings only for actual exceptions, source evidence/highlights for review, and no mandatory confirmation of every clean field.
- `Sync`, ordinary `Re-evaluate links`, routine-completion notifications, current upload modal, and PDF-only Hub modal are absent after equivalent workflows pass.

### Security, accessibility, responsive, and performance

- Cross-tenant and revoked-access tests deny Intake, assets, signed URLs, pages/OCR, analysis, placement candidates, relationships, quotations, Workbench projections, and counts through direct IDs, RPCs, events, and storage paths.
- Viewer/Associate/Admin/Owner capability tests cover every Hub and Workbench mutation, including forged intended matter, version, candidate, target, and locator IDs.
- Desktop split panes retain stable headers and independent discoverable scrollers. Mobile retains upload, PDF navigation/search, placement, metadata, quotation, notes, recovery, and read-only Trash capability with one principal scroller per mode.
- Keyboard-only, screen-reader, focus return, 44px touch targets, reduced motion, light/dark, 200% zoom, 320px width, long names, loading/empty/error/partial, expired URL, and processing-live-region checks pass.
- No page-level horizontal overflow or nested scroll trap occurs. Realtime updates preserve focus and spatial position.
- On representative pilot data, target p95 under 300 ms for Hub first-page/filter queries, under 500 ms for Workbench metadata load excluding signed asset/PDF transfer, and visible first PDF page as soon as its bytes/rendering allow. Publish actual stage latency rather than fabricating progress.

## Assumptions

- Supabase/PostgreSQL, private Supabase Storage, Trigger.dev, Vertex AI, React PDF/pdf.js, and the Civic Ink design system remain the initial stack.
- PDF is the only binary original accepted in this phase; selective OCR infrastructure is available or added behind the documented adapter.
- Matter access is organisation-wide today, but every contract supports future matter-level access without data-model replacement.
- The approved File Lifecycle, AI provenance, Trash, Work/Review, and Search contracts remain authoritative except for the explicit asset-scoped Intake analysis amendment recorded by this plan.
- Exact placement and relationship policies begin conservatively. Evaluation can promote additional versioned deterministic rules without changing the persisted run/evidence/decision model.

## Open Questions

None.
