# Resolved decisions recorded through 2026-09-08

These dated user-decision receipts were moved from the [decision queue](../approval-based-blockers.md#resolved) without changing their decisions. Read the relevant receipt with the latest canonical plan; later explicit decisions can supersede earlier ones. Historical next actions and implementation claims need current-state reconciliation. This file is supporting history, not mandatory startup reading.

### 2026-09-08 — Source scope and single-task implementation workflow

- **User decision:** no automatic merging from similar metadata; implement Attach PDF and preserve immutable source/citation identity; defer replacement UI. Use one implementation task without parallel worktrees, bounded stronger consultation early, explicit blocker ownership and a delivery ledger.
- **Planning decisions recorded:** use the supported bounded resumable-upload integration, and Sol/medium coordination with risk-appropriate high-effort review as specified in the canonical lifecycle and delivery plans. These are implementation guidance, not measured latency or completed-feature claims.
- **Resume action/owner:** next implementation coordinator follows D01 onward and records its task identity. D04/D05 carry upload/attachment implementation; D14 keeps replacement UI deferred.
- **Implementation commit:** not implemented. This entry records planning agreement only; retain its decisions in the canonical plans after the operational queue is pruned.

### 2026-09-05 — Document Hub and Workbench concept

- **Plan:** Document Hub, Ingestion, Placement, Relationships, and Workbench.
- **Decision:** approve the fixture-only concept at
  `/dev/document-hub-workbench-concept` as the production visual direction.
  The user gave the concept a green flag after iterative review of density,
  queue rows, evidence ordering, extracted metadata, collaboration state,
  stable pane chrome, source viewing, and restrained motion.
- **Approved desktop contract:** a full-width compact queue rests without a
  selected document; selection opens an approximately 60/40 table/sidebar
  composition with stable aligned headers and a fixed action footer. Source
  viewing replaces only the queue pane. The sidebar uses Overview and Extracted
  data, evidence before interpretation, compact intake facts, and explicit
  source-page actions. Sidebar motion is the fast 150ms treatment and the table
  changes condensed/full columns in the same state change.
- **Approved collaboration treatment:** a claimed row uses a quiet named
  activity label with a restrained live dot; the selected sidebar uses the
  stronger structural notice because the claim changes action availability.
- **Mobile verification:** at a 460px viewport, the queue has no horizontal
  overflow; queue → details → source is intact; Overview and Extracted data are
  readable; the detail body owns one scroller above fixed actions; PDF controls
  fit; and closing the viewer returns to the preserved detail tab.
- **Outcome:** visual approval no longer blocks secured Document Hub or shared
  Workbench implementation. Production readers, upload/placement commands,
  permissions, retained source anchors, and real PDF rendering must still meet
  the canonical plan and its independent acceptance tests.

### 2026-09-03 — Mumbai OCR processor promotion

- **Plan:** AI Extraction, Provenance, and Model Lifecycle; Universal Search
  and Evidence Retrieval.
- **Decision:** approve the exact Mumbai Document AI Enterprise OCR processor
  version `pretrained-ocr-v2.1.1-2025-01-31` for the bounded design-partner
  production release. The user delegated the version choice and authorised
  the representative-corpus testing needed to validate it. Do not use the
  mutable `stable` alias or silently change the effective processor version.
- **Why this version:** the 2026-09-02 diagnostic found the tested exact stable
  v2.1 identifier unavailable and the `stable` alias behaving like the older
  v1.0 family, while this exact v2.1.1 release candidate produced the strongest
  available Mumbai output. Its release-candidate label is an accepted bounded
  pilot risk, not permission to weaken evidence or human-review controls.
- **Release boundary:** the labelled 60–100-page benchmark must still pass
  before page backfill or Search cutover. Selective OCR, source-span/cell
  verification, critical-field Review, safe monitoring, and rollback to
  native-text/manual handling remain mandatory. A version change is
  configuration-driven, but still requires a recorded Mumbai availability
  check, smoke test, relevant regression evidence, and rollback readiness.
- **Outcome:** processor-version approval no longer blocks the benchmark or a
  passing benchmark's bounded shadow backfill and cutover acceptance. Prefer a
  later equivalent stable Mumbai version through the same tested configuration
  change; return for approval only if its risk or product boundary materially
  differs.
- **Evidence:** the local 2026-09-02 evaluation report remains outside the
  repository at `/Users/rishikeshjoshi/Downloads/Document AI OCR Evaluation - 2026-09-02/DOCUMENT_AI_OCR_EVALUATION.md`; it contains no copied source PDFs or credentials.

### 2026-09-01 — Independent backup destination for the design-partner release

- **Plan:** Platform Operations; Design Partner Pilot Execution Sequence.
- **Decision:** the one-organisation design-partner production release may
  proceed without a CaseChain-managed S3-compatible or other independent
  backup destination. It will run on Supabase Pro and rely initially on the
  plan's included managed daily database backups (currently the last seven
  daily restore points). Supabase database backups do not protect private
  Storage object bytes.
- **Recovery boundary:** the design partner retains its original PDFs and the
  pilot terms must state that limitation. CaseChain preserves server-verified
  SHA-256 identity so a later authorised repair workflow can match re-uploaded
  originals to missing assets without creating duplicate legal records. This
  is a planned rehydration path, not a claim that the initial release can
  reconstruct object storage automatically or recover metadata when no
  database backup survives.
- **Deferred gate:** independent encrypted database and complete object-byte
  backup, manifests, retention, and an isolated restore drill become mandatory
  before rollout beyond the single design-partner organisation, before
  onboarding a client that will not retain recoverable originals, or before a
  stronger contractual/regulatory recovery promise—whichever comes first.
- **Outcome:** remove the missing backup destination/key as a blocker for the
  first production release. Reopen destination/key authority as a setup
  blocker when the deferred gate is reached; do not silently represent the
  Supabase-only arrangement as vendor-independent disaster recovery.

### 2026-09-01 — Search page-text source and first-release embedding scope

- **Plan:** Universal Search and Evidence Retrieval; AI Extraction,
  Provenance, and Model Lifecycle.
- **Decision:** add one private, service-written, version-bound extraction
  artifact containing page text and optional OCR word/region anchors for the
  current immutable PDF version. The Search worker chunks only that artifact,
  retains exact version/page locators, writes only changed content hashes, and
  removes derived chunks/vectors with the source lifecycle.
- **First-release boundary:** embeddings are limited to meaningful current-PDF
  document chunks for cited matter-scoped retrieval. Client, Matter, Task,
  Note, chat, Case Brief, Activity, and arbitrary database rows are not
  semantically embedded in the design-partner release. Exact identifiers,
  relational facts, dates, and amounts continue to use lexical/structured
  queries. There are no agents, generated answers, or workspace-wide memory.
- **Outcome:** resume the page-aware changed-chunk writer with existing tenant,
  current-version, Trash, lease, content-hash, model-version, and replay fences.
  Keep organisation-wide semantic expansion and additional content families
  behind later relevance, cost, and citation evaluation.

### 2026-09-01 — Page acquisition, English metadata, and India processing boundary

- **Plan:** AI Extraction, Provenance, and Model Lifecycle; Document Hub,
  Ingestion, Placement, Relationships, and Workbench; Universal Search and
  Evidence Retrieval.
- **Decision:** acquire authoritative page content outside Gemini. Read the
  native PDF text layer and geometry page by page first, then use Google
  Document AI Enterprise OCR only for absent, low-quality, or suspicious mixed
  pages. Retain the original-language native/OCR text and coordinates as the
  citation and Search source. Gemini remains the structured GST/legal metadata
  extractor and must not return or persist a full transcript, `page_text`, or
  `ocr_words`.
- **Language contract:** Gemini returns the synopsis and user-facing metadata
  in English. Proper named entities are transliterated rather than translated;
  institutional/role terms may be translated where useful. Exact source
  spelling and evidence remain retained, machine-derived English aliases are
  correctable, and GSTINs, references, provision numbers, dates, and amounts
  are never transliterated or rewritten.
- **Retrieval contract:** embed original Hindi, English, or mixed-language page
  chunks directly with the approved multilingual embedding model. Do not
  translate the document body solely for indexing. Exact/entity retrieval may
  additionally index the retained English alias alongside the original value.
- **Location contract:** run Gemini document extraction and Document AI OCR in
  Mumbai (`asia-south1`). Configure the embedding endpoint independently and
  verify the selected embedding model in Mumbai before rollout; never silently
  fall back to `us-central1` or a global endpoint when India residency is an
  active requirement.
- **Implementation consequence:** preserve the private artifact, chunking,
  lineage, lease, tenant, Trash, content-hash, and replay foundations delivered
  in `aa13669`, but replace its Gemini-transcription producer. No page backfill,
  Search cutover, or query/UI consumer may rely on that producer.
- **Exact resume action:** add the local Document AI evaluation harness and
  representative-corpus report; configure a Mumbai `OCR_PROCESSOR`; implement
  the versioned native-page quality gate and selective OCR adapter; remove page
  transcription from the Gemini prompt/schema/worker; harden English synopsis
  and named-entity normalization; then rerun focused extraction, page-anchor,
  multilingual retrieval, cost, and adversarial QA before backfill.
- **2026-09-02 outcome:** the corrected producer and local harness exist, and
  the first diagnostic corpus run is complete. It found strong multilingual
  OCR alongside a high-confidence critical-date error, flattened-table limits,
  and a production processor-version ambiguity subsequently resolved by the
  2026-09-03 exact v2.1.1 bounded-pilot approval above. The precise continuation
  is the labelled 60–100-page benchmark; Search backfill remains prohibited
  until that quality gate passes.

### 2026-09-01 — Task comments workspace direction

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **Decision:** approved the `/dev/task-comments-concept` direction: a
  task-scoped conversation in the peer **Comments** tab; an independent Notes
  origin link (not copied messages); chronological Notes-style presentation;
  accessible mentions and one-message replies; a fixed composer with a visible
  **Send** action; and the approved desktop/mobile drill-in behavior.
- **Outcome:** implement the secured first comment-thread consumer slice. It
  must keep terminal tasks commentable, make suspended Tasks read-only, and
  defer notification delivery, My Work, Activity reader/projector, nested
  tasks, and broader legacy cleanup.

### 2026-09-01 — Task RPC organisation-selection authority

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today;
  Organisation Administration, Team Access, and Personal Settings.
- **Decision:** ordinary users may have exactly one active or suspended
  organisation membership until a separately approved multi-organisation
  design replaces the invariant. Organisation creation, invitation acceptance,
  and rejoining must serialize and enforce that invariant in the database.
  Removed membership generations do not block joining elsewhere; suspended
  membership does.
- **Authority:** tenant RPCs derive the organisation from `auth.uid()` and the
  caller's exactly one active membership. They do not use the workspace cookie,
  accept a browser organisation authority, choose the newest membership, or
  introduce a selected-organisation context. Zero active membership is a
  normal no-access outcome. An impossible duplicate fails closed, produces safe
  operational diagnostics, and requires a privileged repair runbook rather
  than presenting the user with a workspace-selection stalemate.
- **Outcome:** resume the secured Task reader/transition closure and replace the
  multi-organisation fixture with exactly-one-current-membership, concurrent
  join denial, removed-history/rejoin, suspension denial, zero-membership, and
  invariant-corruption coverage.

### 2026-09-01 — Dedicated Tasks workspace concept

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **Decision:** the user revised and approved the fixture-only compact Tasks
  workspace at `/dev/tasks-workspace-concept`, including Notes-to-Task deep
  links, stable desktop/mobile task detail navigation, and fixture-only
  comments presentation.
- **Outcome:** implement the secured Task reader/transition closure,
  organisation-timezone semantics, and Notes summary against this visual
  contract. Task comments remain a concept-only future workflow: do not ship
  comment storage, mentions, or notification policy in this first Task slice.

### 2026-08-31 — Local browser QA authority for permanent-delete verification

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** local browser login/signup and creating or deleting local test
  resources are authorised whenever needed for QA.
- **Outcome:** authenticated permanent-delete browser verification is execution
  work, not an approval blocker. Continue it without requesting another product
  or local-QA permission; report only genuine verification failures or material
  decisions.

### 2026-09-01 — Task and legacy note action-item compatibility

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **Decision:** approve **Task-only current state**. Notes are immutable origins
  and show a live, read-only summary of their linked Task. The dedicated Tasks
  area is the sole place for Task state and actions; stale copied assignee,
  due-date, and resolution fields must not remain in Notes.
- **Outcome:** no dual write or legacy note-state mutation. The approved Task
  reader/transition slice must provide the replacement experience, use the
  organisation timezone, and include an idempotent one-to-one legacy backfill.
- **Next action:** create and obtain visual approval for the dedicated Tasks
  workspace concept, then implement the secured reader/transition closure.

### 2026-08-31 — Trash permanent-delete concept

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** approve the compact root-operation permanent-delete review and
  typed-confirmation direction.
- **Why it needed review:** permanent deletion is irreversible and its impact,
  holds, and confirmation flow need human visual judgement.
- **Outcome:** user reviewed and revised the `/dev/trash-permanent-delete-concept`;
  the revised compact direction is approved for the production implementation
  tranche.
- **Next action:** implement and independently verify the governed permanent-delete
  authority and durable execution workflow.

### 2026-08-31 — Retention for historical soft-deleted records

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** no legacy compatibility migration is required before the first
  production deployment.
- **Why:** the local database contains test data only; no real client records
  exist that predate the automatic Trash policy. Production begins with the
  approved automatic retention policy, so it cannot contain pre-policy Trash
  entries.
- **Outcome:** do not invent or maintain a legacy exception for test data. If a
  future import introduces historical records, it must use its own approved
  import/retention contract.
