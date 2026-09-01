# Approval-based blockers

This is the short, human-readable queue for decisions that need review before a
tranche can safely continue. It prevents one approval boundary from stopping
the rest of the approved portfolio.

## How it works

- Add an **Open** entry when a user decision, visual review, external authority,
  or material policy choice blocks a tranche.
- State the plan, the exact decision, why it cannot be safely inferred, the
  recommended option, and the safe next action after approval.
- Continue with the next independent canonical tranche. Do not treat this file
  as approval by itself.
- When the user resolves an entry, move it to **Resolved** with the recorded
  decision. Remove it after the dependent verified tranche is committed, unless
  its history is useful to the canonical plan.

## Open

### WORK-REVIEW-CONCEPT-2026-09-01 — Review workspace direction

- **Date/domain/plan:** 2026-09-01 · Work · Work Orchestration, Review,
  Activity, Notifications, and Today.
- **Decision needed:** approve the material production direction for the
  dedicated Review queue and decision pane, including its evidence-first
  desktop layout and mobile list-to-detail flow.
- **Why the approved contract does not settle it:** the plan defines Review
  state, evidence, permissions, and interaction requirements, but the
  production workspace has no reviewed `/dev` concept.
- **Recommended direction:** create a compact fixture-only Review concept with
  stable queue filters, an evidence/decision detail pane, explicit primary
  decisions, and the approved mobile drill-in; it must not reproduce the
  legacy Dashboard/Review four-table query.
- **Alternatives/consequences:** implementing a live Review workspace without
  visual review crosses the approved material UI boundary; delaying it does
  not block the independently approved Organisation Administration tranche.
- **Exact resume action:** build `/dev/review-workspace-concept`, record its
  visual approval here, then implement the smallest secure Review
  producer/consumer closure.

### ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01 — Departure and Team impact workflow

- **Date/domain/plan:** 2026-09-01 · Organisation Administration ·
  Organisation Administration, Team Access, and Personal Settings.
- **Decision needed:** approve the material Team/member-inspector and
  self-service departure-impact direction before replacing the current legacy
  remove-member action with the approved typed departure/administrative
  removal commands.
- **Why the approved contract does not settle it:** the plan specifies impact
  projections, explicit dispositions, role/Owner constraints, and mobile
  behavior, but the existing Settings member removal UI has no reviewed
  departure/confirmation concept.
- **Recommended direction:** create a compact fixture-only concept with a
  Team list/detail workspace, Owner/Admin departure queue, explicit impact
  summary and reassignment/disposition confirmation, plus a separate
  self-service countdown/withdrawal flow. It must not expose another member's
  reason/dependency details to ordinary members.
- **Alternatives/consequences:** retaining the old direct removal flow would
  bypass the approved impact/confirmation contract; delaying this UI does not
  block independent approved backend foundations or other portfolio domains.
- **Concept:** `/dev/organisation-departure-team-concept` (fixture-only;
  no live membership mutation).
- **Exact resume action:** review and approve that concept, record the decision
  here, then replace the legacy live removal caller with the smallest secure
  departure/administrative-removal closure.

### PLAT-BACKUP-DESTINATION-2026-09-01 — Independent backup destination and key authority

- **Date/domain/plan:** 2026-09-01 · Platform Operations · Platform Operations.
- **Decision/authority needed:** provide or authorise a non-production,
  independently controlled object-storage destination and encryption-key
  authority for the approved backup/restore gate, together with a scoped local
  test credential or equivalent isolated test harness.
- **Why the approved contract does not settle it:** the plan requires an
  encrypted independent-destination copy outside the primary failure domain,
  but the repository contains no destination, key ownership, retention-lock
  policy, or credential. Those cannot be invented safely in source code.
- **Recommended direction:** use a dedicated, separately administered
  S3-compatible backup account/project and managed encryption key, with a
  least-privilege backup writer, separate restore reader, immutable 30-daily
  and 12-monthly retention policy, and no application/auth/provider secrets in
  backup data.
- **Alternatives/consequences:** an isolated managed backup service is
  acceptable only if it can prove complete object-byte copies, manifests and
  independent restore; reusing the primary storage account fails the approved
  independent-failure-domain requirement; a local-only mock can validate code
  but cannot close the pilot backup gate.
- **Contract:** [Platform Operations backup, recovery, and rollout gate](./plans/platform/2026-08-27-platform-operations.md#backup-recovery-and-rollout-gate).
- **Exact resume action:** implement the approved backup-set writer, manifest
  verifier, retention/freshness evidence, and isolated restore drill against
  the authorised destination; then run the complete object-byte and database
  recovery acceptance fixtures.

### 2026-09-01 — Document Hub and Workbench concept

- **Plan:** Document Hub, Ingestion, Placement, Relationships, and Workbench.
- **What is waiting:** visual approval for the fixture-only concept at
  `/dev/document-hub-workbench-concept` before live Document Hub or Workbench
  UI is implemented.
- **Proposed direction:** one compact operational queue with upload and state
  context outside the moving body; a shared document viewer and inspector on
  desktop; and a list-to-document flow with Document, Details, Notes, and
  Placement modes on phones. The page placeholder and every consequential
  control state plainly say that this is a local preview, not real document
  work.
- **Why:** the approved plan defines capability and workflow, but the dense
  queue/Workbench layout and mobile adaptation need human visual judgement
  before they become production UI.
- **Then:** implement the secured Document Hub reader/upload/placement and
  shared Workbench consumers against the approved visual contract.

### 2026-09-01 — Search page-text source for evidence chunks

- **Plan:** Universal Search and Evidence Retrieval.
- **What is waiting:** choose the approved source that supplies retained,
  page-by-page document text (and, for scans, OCR text plus page/word
  coordinates) to the Search chunk writer.
- **What exists today:** the processing pipeline stores validated field
  candidates and their evidence quotations, but it does not retain the full
  extracted/OCR text or page coordinate stream. The only legacy
  `document_text` column belongs to staged intake records and has no live
  producer or version/page binding.
- **Why:** a chunk writer without that source would either invent passages or
  lose the exact version/page citation that Search promises. The approved plan
  requires versioned, page-aware chunks, so the extraction storage contract
  cannot be inferred as a routine implementation detail.
- **Recommended direction:** add a private, version-bound extraction artifact
  owned by the document-processing pipeline. It should keep page text and
  optional word/region anchors only for the current immutable document version,
  be service-writer-only, and be removed with the source version during Trash
  and purge. The Search worker then chunks that artifact and never reads a raw
  storage path.
- **Then:** implement the page-aware changed-chunk writer against that approved
  artifact, with the existing current-version, tenant, Trash, lease, and replay
  fences.

## Resolved

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
