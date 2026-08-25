---
title: Document Hub, Ingestion, Placement, Relationships, and Workbench
status: approved
created: 2026-08-25
updated: 2026-08-25
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

## Summary

Rebuild document intake as one durable path from file selection to an evidence-backed document inside a matter. Global uploads, matter uploads, later file attachment, replacement versions, and future external acquisition all enter through the same upload-session, immutable-asset, validation, analysis, placement, and projection contracts. The pipeline extracts a unique PDF once, never copies it merely to assign it, records every consequential automated decision, and can resume individual failed stages without a user-facing `Sync` action.

Replace the current reference-first assignment function with a versioned placement engine that separates human-declared destination, deterministic evidence, ranked suggestions, conflicts, and effective assignment. Initial automatic placement is deliberately limited to an explicit intended matter or one unique, high-authority matter anchor with no contradictory evidence. GSTIN plus financial year, fuzzy references, names, filenames, and semantic similarity can rank suggestions but cannot silently file a document in the initial policy.

Replace the current `document_links` algorithm with two layers: source-grounded reference mentions and effective procedural relationships. An ordinary citation does not automatically become a timeline edge. Exact, unique, same-matter, procedurally explicit relationships may auto-confirm; fuzzy or progression-only inference becomes a Review candidate. Manual decisions remain authoritative, rejected suggestions do not recur, self-links are impossible, and event-driven reevaluation replaces the ordinary-user `Re-evaluate links` button.

Make Document Hub the operational queue and create one shared `DocumentWorkbench` for intake, matter, Search, Activity, Review, and Trash routes. The Workbench uses a continuous, searchable PDF viewer; a structured inspector; page-accurate text/OCR/region quotations; stable desktop split panes; and mobile-equivalent document, details, notes, and decision flows.

## Context and Goals

### Current-state audit

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
| 5. Acquire page content | Extract the native PDF text layer and page geometry. Run OCR only for pages that have absent or low-quality text, retaining page/word boxes and quality. | The row is `Extracting` with a real `Reading document` or `Running OCR` substage; limited/unreadable pages are disclosed rather than hidden. |
| 6. Extract and validate | Run the versioned Vertex extraction contract once for the immutable asset/schema/model input, validate with Zod and domain rules, and persist source-grounded candidates. | Key facts populate progressively; structural failure becomes retryable without losing the file. |
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

### State separation and orchestration

- Keep separate state machines for upload session, asset validation, source analysis, intake placement, logical record, document version, candidate verification, relationship evaluation, Search indexing, and notification delivery.
- The compact Hub stage vocabulary is `Queued → Validating → Extracting → Matching → Ready`, with explicit `Needs placement`, `Review`, `Duplicate`, and `Failed` outcomes. `Extracting` exposes the current real substage such as native text, OCR, or AI metadata. It is a projection over actual states and never a percentage.
- Every state transition is a server-side domain command or trusted worker transition with expected prior state/revision. The browser cannot arbitrarily update statuses.
- Upload finalization and every mutation that requires asynchronous work commit an outbox event in the same database transaction. A dispatcher leases, delivers, retries, and records attempts. Trigger.dev task acceptance is never the only durable copy of processing intent.
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
- **Automatic placement:** allow only one eligible active candidate with no hard contradiction and either:
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
- An assigned document never moves automatically. A stronger later candidate creates a `possible_reassignment` Review item with old/new evidence and an impact preview.
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

- Use a bounded list/detail workspace beneath one stable page header. The header contains `Document Hub`, concise queue context, `Upload PDFs`, and filters; it does not contain large tabs, summary cards, or a `Sync` button.
- `Upload PDFs` opens the native file picker directly. Drag-and-drop on the queue is equivalent. Selecting files immediately reserves and uploads them; there is no upload modal or additional Submit button.
- A compact upload tray shows current batch rows, real byte transfer progress, cancel-before-finalize, retry, and per-file errors. Once finalized, rows merge into the durable queue without changing position unexpectedly.
- The queue uses compact status groups/filters: `Needs action`, `In progress`, `Recent`, and `All`. Additional filters cover destination context, uploader, date, classification, and state. Global versus matter upload is a context filter/chip, not a tall permanent tab strip.
- When opened from a matter, the header shows a removable `Destination: {matter}` context chip and uploads inherit that intended matter. It never creates a second matter-specific queue model.
- The left list shows filename/title, source, intended/suggested destination, current real stage, age, and one clear next action. Stable equal-width badges use the approved intake vocabulary.
- The detail pane embeds the Workbench. For unassigned Intake, its first inspector section is **Placement**: recommended matter and evidence, searchable alternative matter, classification, and `Assign document`. A separate **Create client and matter** proposal expands only when no valid record exists. `Discard upload` is isolated in the More/danger region, not placed beside the positive choices.
- Do not use the current square `Take action` modal. Multi-step client/matter creation uses a wide side sheet or dedicated route with reviewable values and horizontal desktop actions; destructive discard uses the shared confirmation dialog.

#### Mobile

- Use one principal queue scroller. Selecting an item navigates to a full-screen detail route with a compact sticky identity/status header and preserved Back position.
- PDF, Details, Notes, and Placement are explicit modes; only the active mode scrolls. Persistent primary placement action may use the shared bottom action bar without covering PDF controls.
- Upload uses the platform file picker/camera-file capabilities permitted for PDFs and shows the same durable batch rows. All desktop decisions remain available; filters become a drawer.

#### Queue behavior

- Active items are sorted by action need and creation time on initial load, but realtime stage changes update in place. A `New uploads` affordance handles arrivals above the current viewport.
- Duplicate, conflict, and failure rows state what happened and offer an appropriate verb: `Open existing`, `View in Trash`, `Choose matter`, `Review conflict`, `Unlock and retry`, or `Retry extraction`.
- An assigned handoff shows its destination and `Open document`; Recent retains bounded assignment/failure history for operational reassurance. Activity remains the full historical record.
- Empty state explains global versus matter-context intake and provides `Upload PDFs`. It does not use decorative illustration or claim that every uploaded tax document belongs in a Timeline.

### Shared Document Workbench

#### Component contract and layout

- Implement one `DocumentWorkbench` with a typed subject:
  - `{ kind: 'intake'; intakeItemId; assetId }`, or
  - `{ kind: 'document'; documentId; versionId?: string }`.
- Server loaders derive organisation, access, current/historical/Trash state, signed asset access, capabilities, and source locator. Browser callers do not supply bucket paths, organisation IDs, or permission booleans.
- Desktop uses a resizable PDF/inspector split, initially approximately 64/36. The outer workspace does not scroll. Viewer and inspector each have one independently scrolling body beneath stable pane headers; the selected width may be remembered per user.
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
- Normal assigned-document actions are `Edit details`, `Move or copy`, `Change classification`, `Replace PDF`, and `Move to Trash`, subject to capability and state. Consequential actions use impact previews and domain commands.
- `Retry {failed stage}` is available only when a stage is failed/retryable. `Re-extract metadata` or `Retry relationship matching` appears in More with scope and consequence; there is no generic `Sync` or ordinary `Re-evaluate links` action.
- Every mutation is disabled in Trash/read-only/historical-version contexts as appropriate. Historical versions may still be viewed, quoted, and compared according to access policy.

### Permissions and security

- Viewer can inspect authorised active and Trash-readable documents/versions and quotations but cannot upload, assign, classify, retry, edit, replace, move/copy, or trash.
- Associate can upload, place Intake, correct permitted metadata, manage permitted relationships, reclassify, move/copy, retry recoverable stages, and trash/restore individual documents under the approved capability rules.
- Owner/Admin has organisation triage, conflict reassignment, new client/matter approval, quota exceptions within platform limits, and privileged recovery. Permanent purge remains governed by the Trash plan.
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

## Implementation Plan

1. **Freeze fixtures and state catalogue.** Capture current global upload, matter upload, duplicate, manual/auto assignment, auto-create, reprocess, link/pending-link, move/copy, reclassify, viewer, quote, Trash, and failure behaviors. Add representative GST PDFs for exact/colliding references, multiple matters in one FY, multi-FY documents, scans, encrypted/malformed PDFs, conflicting GSTIN, missing targets, self-reference, and replacement versions.
2. **Resolve cross-plan source analysis.** Amend AI provenance so immutable source analysis can be asset-scoped during Intake and bound to a document version at placement; retain document-specific effective candidates/decisions. Amend File Lifecycle events/tables accordingly before schema work.
3. **Add the additive ingestion foundation.** Introduce/complete `file_assets`, `upload_sessions`, `intake_items`, `source_analysis_runs`, page/OCR artifacts, `document_versions`, analysis bindings, processing-stage runs, and outbox/dispatch state with RLS, lineage constraints, idempotency, reservations, and safe errors.
4. **Build upload reservation/finalization.** Move browser transfer to bounded direct-to-private-storage contracts, enforce the approved 25 MB/default and organisation/platform quotas, finalize server-observed object data, and implement cleanup/expiry. Do not remove legacy bucket reads yet.
5. **Build validation and duplicate resolution.** Add PDF signature/readability/encryption/page checks, SHA-256, quarantine adapter, all-lifecycle duplicate lookup, replacement/copy special cases, and non-disclosing conflict results. Ensure duplicate decisions occur before paid AI.
6. **Split analysis into resumable stages.** Implement native page text/geometry, selective OCR with word boxes/quality, asset-scoped Vertex extraction, Zod/domain validation, reusable artifacts, usage records, and document-version binding. Remove the staged/raw-metadata fast-path heuristic after cutover.
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
- Extend `document_processing_runs` to stage-level attempts/dependencies and `intake_items` to classification/placement run and stable failure/action state.

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

### Pipeline and storage

- Global, matter, replacement, later-attachment, and intentional-copy fixtures all use the same upload/asset contracts. Ordinary assignment/reassignment performs no storage download, copy, move, or re-upload.
- A browser disconnect after upload/finalization and an application crash after database commit both leave recoverable durable work. Outbox replay and worker retry create exactly one logical document/version and one set of candidates/events.
- Server validation rejects or safely handles wrong MIME/extension, malformed, encrypted, oversize, empty, suspicious, missing, and unreadable PDFs. The approved 25 MB default, reservations, organisation quota, and platform guard withstand concurrent uploads and forged client metadata.
- Exact duplicate detection covers active, historical, Intake, and Trash before AI. Renaming, forged hashes, or alternate routes cannot bypass it. Intentional Copy reuses one asset and rebuilds matter-specific state.
- Provider outage or OCR/extraction failure never loses a validated asset. Manual placement remains possible where safe; retries are scope-specific and idempotent.
- Every stage transition and status projection has unit/state-machine tests, RLS tests, stale revision tests, and safe failure codes. No combined status can claim `Ready` while the source itself is unavailable.

### Placement quality and integrity

- Tests cover intended matter, exact matter/external key, exact cited document, same reference under multiple matters, GSTIN conflict, GSTIN+FY only, multiple matters in one FY, multi-FY source, fuzzy/name/filename/semantic hints, unavailable/Trash targets, no match, later stronger evidence, and concurrent user/worker decisions.
- Fuzzy-reference fixtures cover punctuation/spacing variants, year formats, known OCR confusions, one-character numeric collisions, different issuers, different clients, multiple plausible targets, and adversarial near matches. They prove that fuzzy results are explainable suggestions only and cause no mutation.
- Initial auto-placement occurs only for the approved strong-anchor cases with one eligible candidate and no contradiction. GSTIN+FY, fuzzy, name, filename, and semantic-only cases remain suggestions.
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
- The Placement pane cleanly separates suggested/existing matter assignment, new client/matter proposal, and destructive discard. Every candidate shows evidence and contradictions without a fake confidence percentage.
- The same Workbench renders an Intake asset, assigned document, historical version, Search passage, Review evidence, and Trash read-only route. No page maintains a separate PDF/metadata viewer contract.
- Continuous scrolling works with long PDFs; direct page entry, zoom, fit, rotate, search, thumbnails, keyboard navigation, and native scroll all work without forcing next/previous clicks.
- Every document passage fixture opens the exact immutable version/page and highlights the expected normalized regions after zoom, rotation, resize, and desktop/mobile layout changes.
- Native-text, OCR-text, and region-only quotations create valid note locators. Clicking the note quote returns to the correct page/highlight; historical replacement preserves the old quotation; purged evidence shows the approved tombstone.
- Inspector shows overdue/missed deadlines, provisional/verified facts, financial context, parties, legal references, relationships, versions, and processing/provenance without reading arbitrary `raw_metadata` after cutover.
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
