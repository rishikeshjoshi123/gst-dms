---
title: CaseChain Product Architecture Portfolio
status: proposed
created: 2026-08-24
updated: 2026-08-29
owners:
  - product
  - engineering
related:
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
  - ./2026-08-24-document-record-and-file-lifecycle.md
  - ./2026-08-24-ai-extraction-and-model-lifecycle.md
  - ./2026-08-24-resource-trash-retention-and-purge.md
  - ../features/2026-08-24-universal-search-and-evidence-retrieval.md
  - ../features/2026-08-25-work-review-activity-notifications.md
  - ../features/2026-08-25-document-hub-ingestion-and-workbench.md
  - ../features/2026-08-25-matter-workspace-and-procedural-timeline.md
  - ../features/2026-08-25-notes-and-case-brief.md
  - ../features/2026-08-26-deadlines-and-financials.md
  - ./2026-08-25-realtime-delivery-freshness-and-unread-state.md
  - ./2026-08-26-organisation-administration.md
  - ./2026-08-27-platform-operations.md
---

# CaseChain Product Architecture Portfolio

## Summary

Rebuild CaseChain as an evidence-centred GST-litigation workspace with explicit boundaries between source records, immutable files, AI-derived candidates, human decisions, collaborative work, and user-facing projections. The portfolio is divided into bounded canonical plans so an implementation agent can work from an approved domain contract without inventing cross-domain architecture.

The product vocabulary is **Today**, **My Work**, **Review**, **Activity**, **Document Hub**, **Search**, and the **Matter Workspace**. The legacy CaseWiki concept becomes a cited **Case Brief**. These are projections over shared domain services, not isolated page-specific data models.

## Context and Goals

The current application was assembled feature by feature. Processing state, review state, notifications, activity, extracted metadata, files, and user tasks are frequently combined in page-specific tables or JSON. The same PDF is copied between storage buckets during assignment, AI output can become effective metadata without field-level provenance, and UI surfaces independently decide what constitutes attention or recent activity.

The overhaul must preserve legal evidence, tenant isolation, human authority, mobile capability, and a clear migration path while allowing delivery in independent increments. It must avoid a single rewrite and must not require every future feature to be designed before foundational work begins.

Success means:

- every canonical datum has one owning domain and explicit provenance;
- asynchronous work is durable, idempotent, observable, and retryable;
- AI uses risk-based review by exception: safe, validated candidates may apply automatically, while consequential or conflicting candidates require a human decision and never silently replace verified human state;
- every attention surface is a projection of tasks, review items, deadlines, processing failures, or mentions rather than page-local logic;
- document/page citations survive file replacement and route users back to the exact evidence version;
- domain plans define data, permissions, events, migration, testing, desktop, and mobile behavior before implementation;
- later Excel and GST-portal acquisition can enter through supported ingestion contracts rather than direct database scripts.

## Decisions

### Product model

- **Today** is a prioritised daily command centre, not a statistics dashboard. It contains urgent/resumable projections and a compact activity preview.
- **My Work** owns user-assigned tasks, deadlines, review assignments, and mentions.
- **Review** owns decisions where human judgement or verification is required. It is not a generic list of unfinished work.
- **Activity** is append-only organisation and matter history. Routine processing belongs here or inline, not in Notifications.
- **Notifications** are personal interruptions with a reason, recipient, deep link, and useful action.
- **Document Hub** is the intake and placement workspace. A single shared Document Workbench owns PDF inspection everywhere.
- **Matter Workspace** is the flagship record workspace. Timeline, Files, Case Brief, Notes, Deadlines, Financials, Details, and Activity are coordinated sections over shared domains.
- **Case Brief** is a cited, current orientation layer for a matter. It complements the factual timeline and is updated incrementally; it is not a periodic uncited essay or a duplicate timeline.
- **Search** is a shell-level capability with scoped, explainable retrieval. It is not owned by Today.

### Architectural layers and ownership

| Layer | Owns | Must not own |
| --- | --- | --- |
| Identity and tenancy | organisations, memberships, roles, invitations, platform administrators | feature-specific permissions or tenant legal content |
| Legal records | clients, matters, logical documents, relationships, classification | physical storage paths or unvalidated AI payloads |
| Evidence assets | immutable file assets, document versions, page/OCR anchors, retention | effective legal metadata or workflow decisions |
| Intelligence and provenance | extraction runs, candidates, evidence, prompt/model versions, embeddings | silent canonical overwrites or user permissions |
| Work and decisions | tasks, review items, assignments, resolution state | source evidence copies or notification delivery state |
| Collaboration | note threads/messages/mentions/quotes, Case Brief blocks/versions | general activity or deadline truth |
| Legal facts | deadlines and financial positions/events with verification/provenance | arbitrary fields buried only in document JSON |
| Audit and delivery | activity events, outbox events, notification/email deliveries | mutable source-of-truth feature state |
| Experience | shell, tables, workspaces, workbench, mobile adaptations | page-local copies of domain state machines |

### Cross-domain invariants

- Every tenant-owned row carries `org_id`, including derived and operational rows. Child `org_id` values are constrained against their parents or assigned only by trusted database/domain functions.
- Tenant authorisation is enforced through RLS and server-side domain commands. Hiding a control in the UI is never the only permission check.
- Browser-supplied organisation IDs, storage paths, parent IDs, model versions, and prices are not trusted as authorisation or configuration.
- Source records, file evidence, AI candidates, human overrides, and effective values remain distinguishable. A projection may combine them, but storage must preserve their origin.
- Verified human values are never silently overwritten by re-extraction, import, model upgrade, Case Brief refresh, or reclassification.
- Material mutations append an `activity_event` and, where asynchronous work is required, a transactional outbox record in the same database transaction.
- The outbox is the delivery authority, not the processing-result store. Trusted server code may send an immediate coalesced wake-up, but a one-minute indexed recovery dispatcher guarantees later delivery. Delivery state and domain processing state remain separate.
- Workers consume organisation-fair, bounded durable work, use idempotency keys, append attempt/run records, and can retry only proven-safe stages without duplicating records, notifications, links, deadlines, or financial events. Uncertain partial effects enter recovery or Review instead of blind replay.
- Derived artifacts are versioned against their source. Document text, quotations, embeddings, extraction evidence, and Case Brief citations identify the exact `document_version_id` where applicable.
- Moving a Client, Matter, or Document to Trash creates a hierarchy-aware reversible operation, removes it from ordinary access/search, and preserves its canonical route in read-only form. Hard purge is privileged, audited, hold-aware, and dependency ordered.
- Deep links use stable application IDs and typed source locators. UI routes never require callers to submit a raw bucket/path to gain access.
- UTC timestamps are stored for events; organisation timezone controls display, calendar grouping, reminder evaluation, and date-entry interpretation.
- Currency is stored in integer paise for new canonical financial domains. Display formatting may use lakh/crore without losing exact values.

### Shared state machines

- Keep separate state machines for logical record lifecycle, file availability, processing, extraction verification, review, assignment, and notification delivery. Do not add another overloaded `status` column.
- User-facing status components may combine several states into an understandable label, but the mapping is typed and centrally tested.
- Failures record a stable error code, safe user message, retryability, attempt count, and last failure time. Raw legal content and credentials do not enter operational logs.

### Domain-plan portfolio

The overhaul is split into these canonical plans. A plan is archived only when it has no implementation-blocking question.

1. **Design System and Application Shell:** Civic Ink tokens, shared components, stable context bar, navigation, account menu, theme transition, responsive templates, tables, dialogs, and toasts.
2. **Document Record and File Lifecycle:** logical document identity, metadata-only records, immutable file assets/versions, intake, assignment, reclassification, deletion, quotas, and durable processing.
3. **Hierarchical Resource Trash:** Client/Matter/Document trash operations, read-only routes, restore, retention settings, holds, and permanent purge.
4. **AI Extraction and Provenance:** schemas, prompts, extraction runs, field candidates, human overrides, risk-based auto-acceptance, effective metadata, model lifecycle, and evaluation.
5. **Universal Search and Evidence Retrieval:** hybrid retrieval, typed constraints, page chunks, citations, security, model migration, and saved searches.
6. **Work, Review, Activity, and Notifications:** tasks, review items, activity events, outbox, notification policy, preferences, Today, and My Work projections.
7. **Document Hub and Workbench:** queue interaction, direct upload, assignment decisions, continuous PDF viewer, inspector, document quotations, and mobile inspection.
8. **Matter Workspace and Timeline:** matter shell, procedural graph, relationship editing, Files evidence library, details, state preservation, and chronological mobile fallback.
9. **Notes and Case Brief:** note threads/messages/mentions/quotes/tasks, cited Brief blocks, human provenance, incremental refresh, suggestions, and history.
10. **Deadlines and Financials:** verified/provisional deadlines, reminders, legal financial histories, internal cost ledger, access, matter views, and organisation projections.
11. **Organisation Administration:** team, RBAC, settings, preferences, security/MFA, storage/retention, invitations, and organisation profile.
12. **Platform Operations:** isolated platform console, platform administrators, MFA, usage/pricing, quotas, job health, audit, and privacy boundary.
13. **External Acquisition and Imports:** spreadsheet mapping/import and GST-document acquisition. Spreadsheet template versus arbitrary-column mapping remains deliberately undecided until representative sheets are reviewed; both must target one validated import contract.
14. **Realtime Delivery and Freshness:** selective private matter/intake/Review delivery, connection and freshness state, quota-aware lifecycle, and durable per-user unread cursors. Realtime is a non-authoritative hint and is not enabled on every screen.

### Portfolio status and resumption contract

This table is the durable handoff ledger for a fresh planning task. `Status` is the canonical archive status from the child plan. `Maturity` records why a plan has or has not advanced without treating browser concepts or conversational review as implementation.

| Domain | Status | Maturity | Required next action |
| --- | --- | --- | --- |
| Design System and Application Shell | `in-progress` | Contract is established and shared UI work is underway. | Continue implementation as a cross-cutting dependency; revise the canonical plan when a reusable contract changes. |
| Document Record and File Lifecycle | `in-progress` | Direct-matter and global Inbox canonical upload, placement, authorised preview, recovery, staged-source verification, controlled non-destructive transfer, aggregate-safe retirement evidence inventory, durable dispatch, scoped search-index reprocess completion/recovery, structured Vertex failure fences, privileged outbox compaction, fail-closed staged-source duplicate purge authority, and zero-unresolved compatibility/legacy-assignment cutover are implemented and verified. Unassigned Intake remains manual-only; canonical document/Trash policy owns hold, export, backup, and retention. | Retain staging history/tombstones unless a later separately approved retention contract permits removal. |
| Hierarchical Resource Trash | `approved` | Approved implementation contract. | Implement in dependency order; no further architecture pass is required unless a conflicting requirement appears. |
| AI Extraction and Provenance | `in-progress` | Transitional hardening, immutable source runs/candidates, version bindings, effective decisions, processing provenance writes, the bounded effective-metadata Search consumer fence, and the live inspector and relationship-dialog consumers are implemented and verified; normalized provenance/model-lifecycle work remains active. | Migrate the live relationship re-evaluation consumer. Keep automatic assignment as a prerequisite until a real caller exists, and keep multi-index rollout and page-aware Search separate. |
| Universal Search and Evidence Retrieval | `approved` | Approved implementation contract. | Implement after versioned document text and provenance dependencies are ready. |
| Work, Review, Activity, Notifications, and Today | `approved` | Approved implementation contract, including opt-in optional email and digest defaults. | Implement after the shared Activity/outbox and work-state foundations are ready. |
| Document Hub and Workbench | `approved` | Approved implementation contract. | Implement against stable document-version, provenance, and Review contracts. |
| Matter Workspace and Timeline | `approved` | Approved implementation contract. | Implement after document lifecycle, Workbench, relationship, and Activity dependencies are ready. |
| Notes and Case Brief | `approved` | Approved implementation contract. | Implement after quotation/source-locator, Work/Review, and evidence dependencies are ready. |
| Deadlines and Financials | `approved` | Approved implementation contract and browser concept reviewed. | Implement against effective metadata, Work, and organisation capability contracts. |
| Organisation Administration | `in-progress` | The identity/RBAC foundation, canonical membership RLS cutover, hash-only invitation commands, safe acceptance flow, and associated local database acceptance gates are stable as a completed foundation tranche; remaining approved work stays in progress. | Begin the approved Document Record and File Lifecycle foundation; resume remaining Organisation Administration work in its approved rollout sequence. |
| Platform Operations | `approved` | Approved implementation contract; it must ship and pass its gates before rollout beyond the controlled pilot. | Implement after Organisation Administration identity/RBAC and Document Record and File Lifecycle foundations; complete the backup/restore gate before broader rollout. |
| External Acquisition and Imports | `not archived` | Architecture boundary is known, but spreadsheet field mapping is intentionally undecided. | Defer detailed planning until representative organisation spreadsheets are supplied; do not implement direct database-population scripts. |
| Realtime Delivery and Freshness | `approved` | Approved implementation contract. | Implement selectively after its Matter, Notes, Document Hub, and Review consumers are ready. |

The count is therefore exact for this portfolio snapshot: **9 approved**, **0 decision-complete proposed**, **4 in progress**, and **1 not archived**, across **14 child domains**. Every archived decision-complete proposed child plan has now passed final approval. The umbrella portfolio remains `proposed` until External Acquisition and Imports is archived, but planning no longer blocks implementation. A change to any child status must update this table and `docs/plans/README.md` in the same commit.

All final approval passes, including Platform Operations, are complete; there are no remaining proposed-plan approval passes. Organisation Administration remains in progress, but its identity/RBAC foundation, canonical membership RLS cutover, hash-only invitation commands, safe acceptance flow, and associated local database acceptance gates are stable as a completed foundation tranche. The Document Record and File Lifecycle plan is now in progress: direct-matter and global Inbox canonical upload, placement, recovery, staged-source verification, controlled transfer, non-destructive retirement evidence inventory, durable outbox authority, trusted wake-up, bounded organisation-aware draining, scoped search-index completion/recovery, structured Vertex failure fencing, privileged outbox compaction, fail-closed staged-source duplicate purge authority, and the zero-unresolved staging compatibility/legacy-assignment cutover are complete and independently verified. Unassigned Inbox/Intake sources remain manual-only. After assignment and independent byte/hash/PDF equality, the staging object is a redundant transport copy; legal hold, export, backup, and retention govern the canonical matter document and hierarchical Trash lifecycle. Retain staging history and tombstones until a separately approved data-retention contract authorises removal. Keep External Acquisition and Imports deliberately deferred until representative spreadsheets are available, and allow implementation work to consume only approved contracts and their dependencies. Platform Operations must ship and pass its gates before rollout beyond the controlled pilot.

To resume in a new task:

1. Read `AGENTS.md`, `docs/plans/README.md`, and this status table.
2. Read only the canonical plan and directly linked dependencies for the active domain.
3. Treat approved decisions as fixed unless new evidence creates a concrete conflict.
4. Keep architecture approval, bounded implementation, and read-only QA as separate work assignments; do not pass the full historical conversation to implementation or QA workers.
5. Return material implementation deviations to the owning plan before allowing feature-local architecture to emerge.

### Dependency order

Dependency order constrains architecture; it does not force a single release order.

1. Continue the Design System contract in parallel with backend foundations.
2. Establish Organisation Administration identity/RBAC invariants before expanding dependent UI or platform authority.
3. Establish Document Record and File Lifecycle before normalised provenance, page citations, search chunks, or the shared Workbench.
4. Establish hierarchy-aware Trash contracts before rebuilding deleted-resource routes, retention settings, or purge behavior.
5. Complete AI extraction run/candidate/effective-value boundaries before making extracted deadlines or financials authoritative.
6. Establish Activity/outbox, Review, and Tasks before building Today, My Work, notification preferences, or Case Brief contradiction workflows.
7. Build the Workbench and Document Hub against stable version/source-locator contracts.
8. Build Matter Timeline and Files against stable document classification, relationships, and Workbench routes.
9. Build Notes/Case Brief, Deadlines/Financials, and Search as consumers of the shared evidence/provenance contracts; their implementation may proceed in parallel once those contracts exist.
10. Rebuild shell-level Today and collection pages after their underlying projections have stable semantics.
11. Implement Platform Operations after its identity/RBAC and document lifecycle foundations; it must pass its security, usage, quota, job, and backup/restore gates before rollout beyond the controlled pilot. Implement external acquisition/import only through the same ingestion and provenance contracts.

### Migration policy

- Use additive expand/backfill/verify/cut-over/contract migrations. Do not combine destructive cleanup with the first schema introduction.
- New and legacy paths may dual-write only for a bounded, observable migration window. Record the removal condition and rollback boundary.
- Backfills are organisation- or matter-scoped, resumable, idempotent, rate-limited, and report counts without exposing legal content.
- Preserve stable client, matter, and document IDs. Storage paths, extracted payload shapes, and derived indexes are replaceable implementation details.
- Development data may be reset only with explicit user authorisation. No production-destructive migration is approved by this portfolio.
- Migration filenames are unique and monotonically ordered. CI rejects duplicate numeric prefixes and schema drift.

### Scope control

- PDF remains the only original file format in the first overhaul. Image and Office ingestion require a later plan.
- Motivational quotes, decorative theme scenes, hidden primary actions, vanity metrics, and a user-visible semantic-search confidence percentage are excluded.
- Simultaneous Case Brief co-editing, generated legal answers, billing/pricing tiers, arbitrary colour themes, and unattended GST-portal credential automation are not implicitly approved.
- The spreadsheet importer is not designed until representative files are supplied. The architecture nevertheless supports metadata-only document records and later attachment.

## Implementation Plan

1. All final approval passes, including Platform Operations, are complete. Organisation Administration remains in progress, but its identity/RBAC foundation, canonical membership RLS cutover, hash-only invitation commands, safe acceptance flow, and associated local database acceptance gates are stable as a completed foundation tranche; its remaining approved work stays governed by that plan. Begin implementation from approved dependency order with the approved Document Record and File Lifecycle foundation; no proposed-plan approval pass remains.
2. Continue the in-progress Design System and AI tracks. Reconcile the AI implementation and read-only QA findings with normalized extraction runs/candidates/overrides rather than leaving validated payloads only in `raw_metadata`.
3. Implement Platform Operations after its foundations. Keep global usage, quotas, job health, and platform administration outside ordinary tenant routes and credentials; it must ship and pass its gates before rollout beyond the controlled pilot.
4. Defer the detailed External Acquisition and Imports plan until representative spreadsheets are supplied; preserve the validated intake/import boundary in the meantime.
5. Actual implementation may consume only approved contracts and their dependencies. For each implementation tranche, include the owning plan's code/schema audit, additive migration sequence, permission matrix, failure/retry behavior, backfill, observability, automated tests, and manual acceptance matrix.
6. Keep `docs/plans/README.md` and the portfolio status table synchronized whenever a plan is created, approved, started, completed, or superseded.

## Interfaces and Data Changes

This portfolio defines shared contracts that domain plans must refine:

- `SourceLocator`: typed entity/document-version/page/text-or-region locator used by search, notes, review, notifications, activity, and deep links.
- `Provenance`: origin kind, source entity/version, actor or AI run, evidence locator, confidence/verification state, and timestamps.
- `DomainCommandResult`: success/failure code, changed entity IDs, durable asynchronous work ID when applicable, and safe user message.
- `ActivityEvent`: actor, organisation lineage, event type, entity, human summary, typed metadata, target locator, and timestamp.
- `OutboxEvent`: typed event kind/version, tenant, aggregate and allow-listed routing IDs, idempotency key, delivery attempts/lease/next attempt, Trigger run ID, delivery state, and safe error category. It contains no legal content, storage path, signed URL, credential, or arbitrary instruction.
- `ReviewItem`: type, subject, reason, evidence locators, impact, assignee, priority, state, resolution, and timestamps.
- `Task`: origin, assignee, matter/client lineage, due date, priority, state, and completion/audit data.

Exact schemas belong to the owning domain plans. Feature pages consume domain services or secured projections rather than writing these tables independently.

## Testing and Acceptance Criteria

- Every archived child plan identifies its owning tables, allowed writers, RLS behavior, events, async work, migration/backfill, rollback, and deletion behavior.
- Automated architecture tests cover cross-tenant denial, parent/child organisation integrity, Viewer write denial, outbox idempotency, and source-locator authorisation.
- Durable-work tests cover immediate-wake failure, one-minute recovery, duplicate/overlapping wakes, expired leases, fair multi-organisation draining, dead-letter visibility, hot-index selection, retention compaction, scoped reprocess, and retry fencing after uncertain side effects.
- CI rejects duplicate migration prefixes, direct client access to service credentials, unscoped tenant mutations, and new raw storage-path signing interfaces.
- A representative end-to-end fixture can enter through upload, become a versioned document, produce validated candidates, require review, appear in Matter/Search/Activity, receive a note quotation, and remain auditable after replacement and soft deletion.
- A metadata-only imported fixture can participate in Matter, Timeline, exact/structured Search, deadlines/financial review, and later gain a PDF without changing document identity.
- Every operational screen defines desktop and mobile capability, scroll ownership, loading/empty/error/partial states, keyboard operation, screen-reader names, dark appearance, and 200% zoom acceptance.
- No rollout beyond the controlled pilot occurs until tenant isolation, backup/restore strategy, quotas, operational job visibility, and platform administration have approved plans and passing tests.

## Assumptions

- CaseChain remains a multi-tenant GST-litigation DMS with one organisation per normal user for the initial product phase.
- Supabase/PostgreSQL, private Supabase Storage, Next.js, Trigger.dev, and Vertex AI remain the initial platform stack.
- Owner/Admin, Associate, and Viewer remain the initial tenant role families; child plans may refine permission capabilities without adding page-local role logic.
- The application is in a controlled pilot phase, so additive migrations and measured backfills are preferred over preserving weak legacy contracts indefinitely.

## Open Questions

None.
