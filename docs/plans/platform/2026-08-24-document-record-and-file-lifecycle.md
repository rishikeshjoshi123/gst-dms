---
title: Document Record and File Lifecycle
status: in-progress
created: 2026-08-24
updated: 2026-08-29
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ./2026-08-24-ai-extraction-and-model-lifecycle.md
  - ./2026-08-24-resource-trash-retention-and-purge.md
  - ../features/2026-08-24-universal-search-and-evidence-retrieval.md
  - ../features/2026-08-25-document-hub-ingestion-and-workbench.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Document Record and File Lifecycle

## Summary

Separate the logical legal-document record from its physical PDF evidence. A document may exist with verified/imported metadata before a PDF is available, may later receive an immutable PDF version, and may receive replacement versions without breaking timeline identity, notes, citations, audit history, or search locators.

Unify global and matter uploads behind one durable intake pipeline. Store every unique PDF once per organisation in a private, organisation-scoped asset path; assignment changes database relationships rather than copying files between staging and matter folders. Processing is driven by a transactional outbox and idempotent run records rather than a best-effort post-response trigger.

## Context and Goals

The current `documents` row requires `matter_id` and `storage_path`, mixes logical identity, effective metadata, AI output, processing, review, and physical storage, and uses a single overloaded status. `staged_documents` and two storage buckets create a second partial document model. Assignment downloads and re-uploads a PDF into another bucket, while copying a document to another matter duplicates the binary. Reassignment deletes relationships and mutates deadlines without an atomic domain boundary. Supporting documents have both a deprecated table and a classification field on `documents`.

Some prospective organisations maintain procedural registers in spreadsheets and do not initially possess every PDF. CaseChain must represent those proceedings honestly, allow a PDF to be attached later, and avoid fabricating searchable body content or embeddings from sparse metadata.

This plan does not decide whether the import product begins with a CaseChain-owned spreadsheet template or accepts arbitrary customer column layouts through a mapping wizard. That choice remains deferred until representative customer sheets are available. Both approaches must translate into the same validated canonical import draft and then call the document commands defined here; neither may populate production tables directly.

The lifecycle must support direct matter upload, global intake, metadata-only record creation, later file attachment, safe replacement, exact duplicate handling, proceeding/supporting reclassification, recoverable deletion, conservative pilot quotas, and stable evidence locators.

## Decisions

### Logical document identity

- `documents` is the stable legal record. Its ID survives file attachment, file replacement, reassignment, classification changes, re-extraction, and embedding-model migration.
- A filed document belongs to exactly one organisation and one matter. Unassigned uploads remain `intake_items`; they do not become nullable-matter documents.
- A document can exist with zero file versions. Such a row has `content_availability = metadata_only` and participates in timeline, exact/structured search, manual relationships, deadlines, financial facts, notes, and activity according to the metadata actually supplied.
- `documents` owns effective high-use identity fields and lifecycle/classification, not a raw storage path or mutable AI response.
- Use explicit enums for `document_class` (`proceeding`, `supporting`) and `record_state` (`active`, `trashed`). Processing, extraction verification, and review use separate tables/states.
- `origin_kind` records `upload`, `spreadsheet_import`, `manual_record`, `email_intake`, `api_intake`, or `legacy_migration`. The later importer may add an external source key and row provenance without changing document identity.
- Metadata-only records are created through the same server-side document command as future imports. Direct database population scripts are not a supported product path.
- The later import plan may choose a strict CaseChain template, an arbitrary-column mapper, or a staged rollout from template to mapper. This lifecycle contract supports all three and intentionally makes no UI or mapping-algorithm commitment.

### Immutable file assets and versions

- `file_assets` represents an immutable stored binary. It records organisation, private bucket/object key, SHA-256, byte size, detected MIME type, availability state, and creation/audit data.
- Store assets under an organisation-stable path such as `orgs/{org_id}/assets/{asset_id}/original.pdf`. Matter IDs and filenames are metadata, not authorisation-bearing path components.
- `document_versions` attaches an immutable PDF asset to a logical document and supplies monotonic version number, original filename, page count, validation state, created actor/time, and replacement reason.
- A document has at most one current version. Historical versions remain addressable until authorised retention purge. Do not overwrite an object at an existing key.
- Exact byte duplicates within an organisation reuse a single `file_asset`; separate logical documents or versions may reference it. Cross-organisation deduplication is forbidden because it complicates isolation and deletion disclosure.
- Upload validation checks server-observed size, MIME/signature, PDF readability, encryption state, and hash. File extension and browser MIME are not trusted.
- Password-protected, malformed, unsupported, or malware-suspect files never become available document versions. They remain quarantined or failed intake with a safe resolution path.
- Attaching a first valid PDF to a metadata-only document creates version 1 and changes availability to `source_attached`; page/OCR indexing later moves it to `source_indexed` or `source_unreadable`.
- Replacing an existing PDF creates a pending new version. After binary validation succeeds, a transaction promotes it to current and preserves the old version. Extraction/search updates run against the new version; old citations continue to open the historical version with an `Older version` explanation.
- Notes, search passages, extracted evidence, and Case Brief citations identify `document_version_id`, 1-based PDF page index, and optional text/region anchor. They never point only to the mutable current document.

### Canonical PDF fidelity and optimization

- Preserve the exact uploaded PDF bytes as the canonical `file_asset`. Compute its hash before any transformation. Do not downsample, recompress, rasterize, recolour, flatten, sanitize, linearize, or otherwise rewrite the only stored copy.
- The canonical original is the evidentiary source for download, signature/certification verification, duplicate detection, historical versions, legal holds, and audit. A visually identical rewrite is still a different binary and may invalidate or remove digital signatures, forms, annotations, attachments, bookmarks, metadata, colour evidence, native text, or accessibility structure.
- Do not offer a Google-Photos-style `storage saver` mode for proceeding or supporting evidence. Storage pressure is handled through exact within-organisation deduplication, conservative upload/organisation/platform quotas, retention/purge policy, and later movement to a more suitable object-storage tier—not by silently degrading evidence.
- Lossless structural optimization and lossy image optimization may be evaluated only as non-evidentiary derived renditions after canonical validation. The initial product does not persist a second optimized PDF in Supabase because retaining both usually increases total storage; a worker may create a temporary rendition for a bounded AI/viewer operation and delete it after use.
- Native-text PDFs use their original text layer. Scanned pages are assessed individually; OCR/render inputs remain at least 200 DPI and ordinarily target 300 DPI. A lower-resolution or lossy rendition is never used when it reduces small-text, stamp, handwriting, signature, table, reference-number, amount, or date recognition.
- Any future persistent rendition contract records source asset, purpose, transform/tool version, DPI, colour mode, compression parameters, byte size/hash, quality results, creation/expiry, and non-evidentiary status. It is regenerable, excluded from duplicate identity, and purged before the canonical asset.
- Before enabling any optimization on production documents, evaluate a representative corpus of native-text, black-and-white scan, colour scan, mixed, signed/certified, form, annotation, and poor-quality PDFs. Compare byte savings, rendering, page geometry/count, native text, signatures/forms/annotations, page anchors, OCR, and extraction accuracy for GSTINs, references, sections, dates, and amounts. No corpus-wide percentage is assumed.

### Intake and assignment

- All PDF uploads begin as `intake_items`, including uploads initiated inside a matter. A matter upload sets `intended_matter_id`; global upload leaves it null.
- Reserve an `upload_session` and asset ID before file transfer. The server issues a bounded signed upload contract for the exact organisation, asset key, MIME, and maximum size.
- The intake state machine is `awaiting_upload → uploaded → validating → processing → ready → assigned`, with terminal `duplicate`, `failed`, `discarded`, and `expired` states. State transitions are enforced by domain commands/database functions rather than arbitrary client updates.
- Direct matter intake may auto-assign after validation when the intended matter is still active and the uploader retains permission. It still uses the same durable pipeline and remains visible in the inline upload tray.
- AI suggestions never become the user's declared intake context. `intended_matter_id` and suggested matches remain separate.
- Global Intake may require page/OCR/extraction before a logical document or document version exists. Those immutable base artifacts are keyed to the organisation-owned `file_asset` through an append-only source-analysis run, then bound to the created `document_version` during assignment. Do not create a nullable-matter document merely to satisfy processing foreign keys, and do not call the extraction model again solely because placement occurred.
- Assignment creates or links the logical document/version and updates the intake item atomically. It does not download, copy, move, or rename the asset.
- Creating a new client/matter from intake remains an explicit user-confirmed proposal. The transaction creates the approved records, assigns the document, writes activity/outbox events, and records the proposal values used.
- Discarding an unassigned intake item soft-closes the item and immediately removes its only unreferenced asset when safe. Failed/incomplete sessions expire automatically after 24 hours. Assignment is idempotent and cannot produce two documents from repeated submissions.
- Exact duplicates present the existing document/matter evidence and the policy-allowed choices. In the initial product policy, ordinary upload can open existing or discard only; creating a second logical record from the same bytes is available solely through the explicit audited `Copy document to another matter` command. A later broader exception would require its own approved policy.
- Exact duplicate lookup includes active, historical, Intake, and Trash references. A PDF already owned by a trashed document is blocked from creating a fresh document and directs the user to the hierarchy-aware restore flow; only permanent purge of every surviving reference releases the binary from this rule.

### Processing and durable work

- A document write that requires processing commits a typed, versioned `outbox_event` in the same database transaction as the domain change. The database is the authority that work exists; neither an open browser request nor a successful Trigger.dev API call is the source of truth.
- An outbox event contains only tenant and aggregate identifiers, typed/versioned `event_kind`, safe routing identifiers such as upload session, Intake item, logical document, document version, or asset ID, an idempotency key, delivery state, attempts, lease/retry timestamps, Trigger run ID, and a safe error code. It never contains PDF/OCR/legal content, raw model output, signed URLs, credentials, storage paths, or arbitrary natural-language instructions.
- Outbox delivery and actual processing are separate state machines. `outbox_events` answers whether durable work was leased and delivered to Trigger.dev. Intake/source-analysis runs own validation, page/OCR, and extraction before placement; `document_processing_runs` owns document/version-scoped materialization and downstream projection after placement. Processing completion is never inferred from outbox delivery.
- After the transaction commits, trusted server code sends one best-effort, coalesced wake-up per upload batch, carrying only the outbox event or batch reference. The browser does not choose task names or privileged payload fields, and upload success does not depend on Trigger.dev accepting this immediate wake-up.
- The Trigger.dev dispatcher is a singleton or otherwise tightly bounded task, initially with concurrency one. A new wake-up does not cancel a running dispatcher: the running task continues draining, while an overlapping wake is coalesced or queued. Child document-processing tasks use their own bounded concurrency.
- A scheduled recovery invocation runs every minute and leases only indexed, due events. It recovers missed immediate wake-ups, expired delivery leases, and due delivery retries. Delivery retry uses capped exponential backoff and a dead-letter state after the configured maximum; a dead-letter event remains visible to operations and is never silently discarded.
- Dispatch drains continuously in bounded batches while downstream capacity exists instead of claiming one small batch and then waiting for the next minute. A completion wake-up may refill capacity promptly. Leasing is organisation-aware and borrowable: active organisations receive a fair minimum, unused capacity may be borrowed, and global/per-organisation concurrency and batch caps are configurable so a large tenant cannot starve smaller tenants.
- Processing events carry versioned payloads and idempotency keys. Automatic processing retries are limited to stages with proven idempotent effects and keep the same logical document version and idempotency identity. A failure after uncertain partial effects such as relationships, deadlines, Activity, or notifications enters recovery or Review instead of blindly replaying the whole pipeline.
- The initial user-facing states are `Queued`, `Waiting for capacity`, `Validating`, `Extracting`, `Matching`, `Ready`, `Review required`, and `Failed`. The UI reads these states from database-backed records, unblocks after the file and processing instruction are durable, and shows no countdown or fabricated percentage.
- Reprocessing creates an explicit database command/event with one selected scope: extraction, OCR/text, matching/relationships, search indexing, or controlled full processing. It never calls Trigger.dev directly. A general standard-user `Sync`/rebuild action is not part of the lifecycle.
- The dispatcher schedule is one minute; interrupted validation/work reconciliation remains five minutes; terminal failed, expired, quarantined, or duplicate asset cleanup runs hourly with immediate best-effort deletion when a terminal transition occurs. An asset continues counting toward quota until Storage confirms deletion.
- A one-minute recovery schedule means 1,440 scheduler executions per day, or about 43,200 in a 30-day month. Managed Trigger.dev scheduling does not require a permanently running CaseChain application server; measure the dispatcher task's actual execution duration and machine usage. Empty invocations perform one narrow indexed due-work query and exit quickly. Child document processing and Vertex usage are expected to dominate cost, but this assumption must be verified from recorded cost-per-document metrics and alerts.
- Observe outbox-to-dispatch delay, queue wait by organisation, processing duration and attempts, peak queue depth, dead-letter/recovery counts, Trigger.dev cost per document, Vertex cost per page/document, and quota blocked by pending cleanup. Trigger.dev remains the managed pilot platform; reconsider AWS SQS/Lambda or self-hosting only when measured volume, cost, delay, or concurrency justifies the operational complexity.

### Outbox retention and hot-path efficiency

- The every-minute dispatcher does not scan the whole outbox. A partial operational index covers only due `pending` and expired/due `leased` rows, and the lease query returns a bounded set of narrow columns. Completed history is excluded from the hot read path.
- At one recovery query per minute, the baseline is about 43,200 narrow Supabase queries per 30-day month, normally returning no rows or a bounded batch. Track rows examined/returned, query latency, database size, and database egress; the design must not read completed payloads or allow table growth to turn the baseline into a full-table scan.
- Pending, leased, dead-lettered, or otherwise unresolved events are never aged out. Successfully delivered events remain in the hot outbox for 30 days by default, then a privileged bounded maintenance task compacts them into payload-free delivery receipts and removes detailed delivery-attempt rows.
- Compact delivery receipts remain for a configurable 180 days by default. Processing runs and Activity retain the meaningful long-term business/audit history under their own retention rules; the outbox is not the permanent legal-history store.
- Ordinary users and service paths cannot delete outbox history. Retention cleanup is privileged, bounded, resumable, auditable, and reports counts only. Monitor outbox row count, index/database size, oldest unresolved event, and compaction lag so retention can be tuned from evidence rather than guesswork.

### Classification, reassignment, and relationships

- Proceeding/supporting is a property of the logical document; both classes use the same asset/version model and shared Workbench.
- Promoting supporting to proceeding preserves the asset and versions, enters relationship evaluation, and proposes extracted deadlines/financials through their verification workflows.
- Demoting proceeding to supporting first produces an impact preview. Confirmation archives affected procedural relationships and derived provisional facts with a reason; it does not hard-delete them or the source evidence.
- Reassignment to another matter is an atomic domain command. It verifies permissions and same-organisation lineage, preserves the asset/version, archives relationships invalidated by the move, reevaluates matter-scoped derived data, and emits one activity/outbox transaction.
- Copying to another matter creates a new logical document linked to the same organisation-owned asset and records `copied_from_document_id`. Metadata/effective values are copied with provenance; matter-specific links, deadlines, review items, and embeddings are rebuilt rather than copied blindly.
- Relationship endpoints remain logical document IDs. A database constraint forbids self-links, organisation mismatch, and duplicate active edge/type combinations. Manual, exact cited, inferred, rejected, and archived relationship provenance are distinguishable.

### Deletion, restoration, and retention

- Follow the canonical Hierarchical Resource Trash plan. Deleting a document creates a root Trash operation; deleting its matter or client includes it as an inherited member only when it was active at the time.
- Trash preserves the document, all versions, evidence, and ordinary route in read-only form while removing it from active Timeline, Search, work, reminders, and automation.
- Retention is organisation-configurable. The initial default is manual purge only; timed options and optional auto-purge are explicit Owner/Admin settings rather than a fixed 30-day lifecycle constant.
- Restore is operation-scoped and preserves IDs. Permanent purge is Owner/Admin-only, impact-previewed, hold-aware, durable, and deletes an asset only when no surviving reference remains.
- Client or matter trash never relies on physical database cascade deletion. The Trash plan owns hierarchy, dependent-domain suspension, restore conflicts, and purge order.

### Legacy staging retirement

- Assignment and controlled backfill transfer never delete the legacy staging PDF inline. They first preserve the only recoverable source while canonical placement, integrity evidence, and downstream state settle.
- A separate service-only, bounded, recurring purge job owns staging cleanup. It may claim only an explicitly mapped staging source whose Intake has been assigned to a matter and whose expected canonical asset is referenced by that document's immutable version.
- Before deletion, the job must freshly prove organisation/path lineage; source and destination reachability; exact byte-size and SHA-256 equality; readable validated PDF state; the expected asset–Intake–document/version relationship; and the absence of active upload, assignment, verification, transfer, audit, processing, export/backup, legal-hold, retention-lock, or recovery work. A verified same-organisation duplicate may substitute for the copied destination only after the same equality, reachability, assignment, and blocker checks pass.
- Eligibility is fail-closed. An unknown, missing, stale, contradictory, cross-tenant, unreadable, or blocked fact skips that object without deleting it. Later scheduled runs may retry ordinary transient or not-yet-settled conditions; contradictions and unexpected source loss create a durable recovery case rather than being inferred away.
- Each attempt is leased and recorded durably before the Storage effect. Completion is recorded only after Storage confirms the exact source object is absent. If deletion succeeds but its response or the final database write is lost, a later run reconciles the existing attempt and confirmed absence idempotently; an unexplained 404 without prior purge intent is not accepted as successful cleanup.
- Confirmed cleanup leaves a minimal content-free tombstone/receipt containing organisation, opaque source and canonical references, purge attempt/operation, policy or safe reason code, verifier result, actor or maintenance job, and timestamps. It contains no PDF bytes, filename, raw storage path, signed URL, legal content, extracted facts, or credentials.
- Quarantined late-duplicate preallocated assets are a separate cleanup target. They may be removed only after the winning canonical duplicate and the original staging source have been proved equal and reachable and no surviving reference or blocker exists.
- The compatibility adapter and legacy assignment paths remain until aggregate retirement reports show zero unresolved sources, active work, recovery cases, unproven quarantined assets, and access/lineage diagnostics. Their later removal is a separate verified contract migration, not a side effect of object cleanup.

### Storage quotas for the current pilot

- Keep the Supabase bucket ceiling at 50 MB, but set the initial application default to **25 MB per PDF**. Platform operators may raise an organisation to 50 MB for a justified pilot case.
- Set the initial organisation entitlement to **100 MB of unique stored assets**, including assigned, historical, trashed, and unassigned intake assets. Shared asset references are counted once.
- Set a **750 MB platform storage guard** while running on Supabase Free, leaving headroom for system artifacts and operational recovery. Stop new uploads before the provider limit rather than relying on exact quota equality.
- Warn authorised organisation users at 80% and 95%; reject reservation before upload at 100% or when the platform guard would be exceeded.
- Reservations include the declared upload size for active sessions and expire after 24 hours. Final accounting uses server-observed bytes.
- Quotas are entitlements stored in configuration, not constants embedded in upload UI. Future pricing may change entitlements without rewriting lifecycle logic.
- Storage reporting separates active document assets, historical versions, Trash, and Intake while also showing deduplicated total bytes.

### Security and access

- Signed read URLs are requested by `document_version_id` or authorised intake ID, never by a browser-supplied bucket/path pair. Server code resolves the asset under RLS and produces a short-lived URL.
- Asset/storage policies verify organisation membership and an authorised asset or upload-session row. Trusted workers may use server-only credentials after revalidating tenant and source lineage.
- Viewer can read authorised records/versions but cannot upload, attach, replace, classify, assign, restore, or delete. Associate can perform normal operational intake and metadata correction. Destructive retention and quota changes require Admin/Owner capabilities.
- File hash, object key, signed URL, OCR text, embeddings, and quarantined content are sensitive tenant data and are not exposed through ordinary list payloads or logs.

## Implementation Plan

1. **Freeze lifecycle vocabulary and fixtures.** Document current upload, staged assignment, direct matter upload, copy, move, reclassify, delete, restore, and signed-URL behaviors. Add fixtures for metadata-only records, duplicate assets, missing legacy objects, failed queue dispatch, and cross-tenant IDs.
2. **Add foundational tables additively.** Create `file_assets`, `upload_sessions`, `intake_items`, asset-scoped source-analysis hooks, `document_versions`, analysis bindings, `document_processing_runs`, and transactional `outbox_events`, including RLS, parent-organisation constraints, state-transition checks, unique current-version/index constraints, asset reference counts/queries, and timestamps.
3. **Expand logical documents.** Add origin, record state, content availability, current version, copied-from identity, and effective filename/size projections. Make legacy `storage_path` nullable only after version backfill; retain legacy columns during compatibility.
4. **Build server-side domain commands.** Implement reserve/finalize upload, validate asset, create metadata-only record, attach/replace version, assign/discard intake, copy/move document, reclassify, and signed-version access. Provide the document/version hooks required by the separate hierarchical Trash commands. Commands validate caller capability and parent lineage and emit activity/outbox records transactionally.
5. **Introduce durable dispatch.** Add the typed safe outbox, immediate trusted coalesced wake-up, singleton bounded Trigger.dev dispatcher, one-minute recovery schedule, organisation-aware borrowable leasing, continuous bounded draining, delivery dead-letter/recovery, idempotent version-scoped processing, hot-path indexes, compacted delivery receipts, and safe operational/cost metrics without legal content.
6. **Move new uploads to one private asset namespace.** Keep legacy buckets readable. Route global and matter uploads through upload sessions and intake items; remove binary copy from assignment. Show a stable inline tray when the later Document Hub UI plan adopts the contract.
7. **Backfill existing files.** In resumable organisation batches, create assets/versions for active `documents`, migrate active `staged_documents` to intake items, detect missing objects, hash/deduplicate safely within an organisation, and label unreadable/missing sources for Review. Preserve document IDs.
8. **Consolidate legacy supporting documents.** Migrate `supporting_documents` rows into logical `documents` with `document_class = supporting`, versions, links, provenance, and legacy IDs/mapping. Verify counts and access before stopping reads from the old table.
9. **Cut over consumers.** Change Workbench, Notes quotes, Search chunks, extraction, assignment, reprocess, deletion, and activity to use document/version/source-locator contracts. Keep a bounded adapter for legacy rows until coverage is complete.
10. **Enable classification and reassignment workflows.** Add consequence previews, archival provenance, version-stable copy/move, and automatic scoped reevaluation. Remove destructive delete-and-recreate behavior.
11. **Enable quotas and integrate Trash.** Add reservations, organisation/platform guards, usage projections, warnings, and expiration cleanup. Integrate document versions/assets with the approved Trash restore, retention, hold, and privileged purge orchestration.
12. **Verify and contract.** Compare legacy/new counts, object reachability, hashes, RLS, current versions, signed access, and processing coverage. Stop dual writes, then remove `staged_documents`, legacy `supporting_documents`, raw-path signing, bucket-copy assignment, and finally obsolete `storage_path`/overloaded status columns in separate migrations.

## Implementation Status

### Completed: direct-matter canonical intake foundation (2026-08-28)

- Added the additive lifecycle migrations through `00042`, including private asset/upload-session/intake/version foundations, materialization, durable outbox delivery, intended-matter auto-assignment, lifecycle integrity controls, and version-authorised signed reads.
- Direct matter upload now reserves the canonical private asset key, derives completion facts from the stored object, and emits durable validation work. Validated intended-matter Intake is materialised atomically into a logical document and current version without a binary copy or legacy document insert.
- Added server-verified duplicate, quota, retry, terminal-cleanup, Storage tombstone, and document-version access boundaries. The request path supports the 25 MiB application limit, and policy overrides remain capped by the 50 MiB Storage ceiling.
- Added conservative recovery: validation leases can resume safely; legacy processing work that cannot prove idempotent downstream effects is fenced into a service recovery case and cannot be replayed automatically.
- Local Supabase reset and lifecycle SQL acceptance suites passed, as did focused TypeScript tests, type checking, migration checks, upload-limit checks, and the replay-fence regression. Repository-wide lint remains baseline-red outside this tranche.

### Completed: staged-document backfill validation contract foundation (2026-08-28)

- Added migration `00048` with a service-only, per-organisation claim/verification contract for legacy `staged_documents`. It preserves every legacy ID through an opaque mapping, limits claims to rate-safe leased batches, and never stores a legacy path, filename, raw metadata, or document content in its diagnostics or reports.
- A trusted external verifier now has explicit outcomes: only a readable, validated, bounded PDF maps to a quarantined **mapping-only** canonical asset; missing, unreadable, malformed, encrypted, non-PDF, oversize, invalid-lineage, duplicate/reference, and already-migrated sources receive durable, safe terminal classifications. Same-byte matching remains organisation-local.
- The verifier receives a legacy object key only through a leased service-only grant after exact `staging/{org UUID}/{temporary UUID}/original.pdf` validation. Foreign prefixes, traversal, alternate names, and cross-organisation lineage are rejected before Storage access.
- Canonical assets awaiting the later controlled staging transfer are fenced from signing, validation, processing, ordinary Intake visibility, and terminal-storage cleanup. Mapped legacy rows are hidden from the compatibility adapter, Review/notification projection, and legacy signed URLs. Legacy assign, discard, and analysis paths must atomically reserve a source-row action lease before any Storage effect and use a database-issued source grant; backfill claims skip active leases, so map creation cannot race an old-flow copy/delete. Legacy rows and staging objects remain unchanged by this foundation.
- Local reset plus dedicated repeated-batch, cross-organisation, missing-object, malformed-source, duplicate, report-count, RLS/grant, legacy-action-fence, and legacy-source-preservation SQL coverage passed, along with adjacent upload/Inbox fixtures, TypeScript checking, migration checks, and diff checks.

### Completed: server-only staged-document verifier (2026-08-29)

- Added a Trigger-scheduled, service-role-only verifier. It selects incomplete organisations, claims bounded opaque batches, obtains each actual staging key only through the active lease's database source grant, and never accepts a path from a task payload.
- The worker derives the actual object byte count and SHA-256, checks a PDF signature, uses the existing PDF reader to distinguish readable, malformed, and encrypted sources, and records only the migration contract's typed safe outcomes. A hard worker ceiling protects the verifier; the database remains authoritative for the organisation-specific size ceiling.
- Missing is recorded only for an explicit trusted Storage 404. Transient download and worker failures record no terminal observation, so the short database lease expires and the source is safely retried. Task output contains bounded aggregate outcome counts only—never object keys, source IDs, hashes, bytes, document content, or storage/parser errors.
- The worker creates no Intake, makes no copy or delete request, changes no legacy source or read path, and does not retire the adapter or release the staging-transfer fence. Mocked worker/storage tests cover the grant-only path, safe hash observation, non-PDF handling, explicit missing classification, and retryable storage failure.

### Completed: controlled staged-document transfer (2026-08-29)

- Added a service-only, fixed/bounded serial transfer worker for `transfer_pending` mappings. It obtains opaque work claims and a fresh per-item lease before receiving either source or destination key through a database grant; no task payload can provide a storage path.
- The worker revalidates the staging source against its prior verified byte size and SHA-256, uploads only to the preallocated canonical private asset key with overwrite disabled, and independently downloads the canonical target to prove reachability, exact byte size, and SHA-256 before finalisation.
- Database finalisation rechecks the trusted observations, atomically creates ready canonical Intake, marks the canonical asset available, and clears `legacy_staged_backfill_pending`. It is idempotent, organisation-scoped, and preserves every legacy staging row/object and legacy adapter fence.
- If a same-organisation duplicate appears after source verification, finalisation terminally records the existing asset as `duplicate_reference` instead of retrying. It preserves any already-copied preallocated canonical asset in its quarantined state for the separately verified retirement audit; that audit must account for these quarantined orphan assets before any retention or cleanup decision.
- Safe reports now separate pending and completed transfers without exposing object paths, source IDs, byte values, hashes, contents, or provider errors. No staging deletion, adapter retirement, or consumer cutover is included in this tranche.

### Completed: staged-document retirement evidence inventory (2026-08-29)

- Added migration `00050` and a bounded service-only audit worker. Completed transfers are re-read only through fresh lease-bound source/destination grants; a report records aggregate-safe equal, missing, and conflict evidence without exposing paths, IDs, hashes, byte counts, content, or provider errors.
- The per-organisation report is fail-closed. It covers exhaustive map/classification counts, live verification/transfer/legacy/audit leases, transfer database consistency, duplicate target health, source lineage and adapter-fence diagnostics, terminal exception categories, and an explicit unproven count for quarantined backfill-pending assets that cannot safely be paired with a historical late-duplicate race.
- The inventory does not delete staging or canonical objects, alter legacy staged rows, change compatibility reads/assignment behavior, or authorise retention, adapter retirement, or consumer cutover. A true evidence flag is only an input to a separate human decision.

### Approved: fail-closed staged-source purge and tombstone policy (2026-08-29)

- Product approval now authorises a separate recurring maintenance job to delete a redundant legacy staging PDF only after fresh assignment, reference, reachability, byte/hash equality, PDF-integrity, lease/work, hold, export/backup, and recovery checks all pass.
- Uncertain or exceptional sources are retained and skipped for a later run; contradictions enter durable recovery. Deletion uses a leased, resumable intent/confirmation protocol and produces a minimal content-free tombstone. Inline assignment deletion, time-only deletion, storage-pressure deletion, and best-effort unrecorded cleanup remain forbidden.
- This decision is implementation-ready but is not part of the active durable-processing tranche. Its migration, worker, regression suite, retirement report review, and later adapter contract removal remain separate checkpoints.

### Completed: durable outbox delivery authority foundation (2026-08-29)

- Added a service-only delivery authority over the existing typed/versioned, content-free outbox contract. Due work is leased through bounded, organisation-aware fair-first selection; unused capacity remains borrowable, overlapping dispatchers use lease fencing, and only indexed pending or expired-lease rows are on the hot path.
- Expired delivery leases now reconcile independently from source analysis and document processing. They enter capped, jittered delivery retry or durable dead letter with append-only safe attempt outcomes; accepting an event records Trigger delivery only and cannot imply processing completion.
- The database now enforces the exact safe envelope per event kind/version, opaque bounded idempotency keys, and bounded delivery attempts. A migration preflight preserves any earlier broad-contract row in place, records a service-only content-free quarantine marker, and terminalises it before the new checks govern future writes.
- Added content-free delivery health projection, RLS/privilege regression coverage, and a bounded dispatcher drain. The implementation intentionally does not add reprocess commands, provider processing, child-task orchestration, compaction, staging purge, adapter retirement, or user interface work.
- This authority covers rows that enter `outbox_events`; it does not yet migrate pre-existing direct `tasks.trigger` document/reprocess paths or add the trusted coalesced post-commit wake-up. Those paths therefore remain outside the completed delivery authority and are the first remaining write-path checkpoint.
- Local Supabase reset, durable-outbox SQL acceptance (including legacy-upgrade quarantine), adjacent lifecycle/outbox/processing regressions, focused TypeScript tests, targeted lint, type checking, migration uniqueness, and schema lint passed. Schema lint reports only two pre-existing warnings outside this tranche. A final local schema-diff rerun was inconclusive because its local API port was unavailable after shadow migration replay; it is not used as evidence for this checkpoint.

### Canonical next action

Implement the separately approved fail-closed staged-source purge as its own migration/worker/QA tranche before any adapter removal. The direct document/reprocess Trigger bypasses remain removed; canonical upload completion and the approved search-index reprocess command send only a trusted, content-free, coalesced, non-blocking singleton dispatcher wake after their outbox transaction commits, while the one-minute recovery remains authoritative if that wake fails. Keep legacy reads and assignment behind their compatibility/fence contracts; do not expand this work into adapter contract removal.

### Completed: privileged outbox retention and compaction (2026-08-29)

- Added a PostgreSQL-maintenance-only, bounded and resumable compaction authority. It selects only `delivered` envelopes whose delivery time is at least 30 days old, locks candidates with `SKIP LOCKED`, atomically writes one payload-free receipt, removes detailed dispatch attempts, and deletes the delivered envelope. Historical rows with an attempt count outside the current receipt invariant or no final Trigger run ID are retained and recorded once in a payload-free compaction-skip journal, so they cannot roll back or starve the remaining batch.
- Receipts retain the event, tenant, aggregate identity, event kind/version, final Trigger run ID, attempt count, and delivery time—never a payload, path, object key, content, credential, or provider output. They receive a separately bounded 180-day cleanup path and count-only execution journal.
- Pending, leased, dead-letter, unresolved, and boundary-younger rows remain in place. Existing lifecycle and append-only triggers stay fail-closed except for a transaction-scoped deletion fence available only to the original PostgreSQL maintenance session; service and ordinary roles have neither table access nor function execution rights.
- Historical source-analysis and processing run references are retained through nullable foreign keys when a delivered envelope is compacted. The due pending and expired-lease dispatcher indexes are unchanged.
- No repository-supported database-owner scheduler is configured, and Trigger/service authority is intentionally excluded from deletion. The approved execution procedure is a controlled database-owner maintenance run: connect with the PostgreSQL owner credential, run `SELECT * FROM public.compact_delivered_document_outbox_events(100);` and `SELECT * FROM public.cleanup_compacted_outbox_delivery_receipts(100);`, record only the returned counts, and repeat bounded invocations until each returns zero. It is not a browser, service-role, or application-worker operation.
- Local rollback-only SQL acceptance passed for privilege/RLS, safe receipt shape, zero-attempt legacy retention, cutoff boundaries, idempotence, ledger deletion, source-analysis/processing reference nulling, unresolved-row retention, hot-index preservation, and receipt cleanup. A clean local shadow-schema replay through migration `00058`, generated database types, TypeScript checking, migration checks, and diff checks also passed.

### Completed: explicit scoped durable reprocess authority (2026-08-29)

- Reprocess is now one authenticated database command with one selected allow-listed scope (`extract`, `ocr`, `relationships`, `search_index`, or controlled `full`), capability-version validation, tenant/current-version checks, actor-scoped idempotency, a persisted processing-run identity, and a typed `document.reprocess_requested.v1` envelope in the same transaction.
- The Server Action can schedule only the fixed, empty post-commit outbox wake. It cannot choose a Trigger task or carry a storage key, path, binary, raw provider payload, or arbitrary instruction. The dispatcher records the event as scoped durable intent and deliberately does not route it into the legacy generic processor.
- Reconciliation requeues only the proven idempotent `search_index` scope. Expired or failed extraction, OCR, relationship, and full scopes become Review/recovery records with no automatic replay, preserving the existing legacy-processing fence until a later scoped worker supplies run-level completion semantics.
- SQL acceptance coverage verifies capability/version and tenant denial, exact safe envelopes, idempotent run/event identity, unavailable/invalid scope rejection, privilege boundaries, and retry fencing. Focused TypeScript coverage verifies the explicit-scope command surface and fixed wake boundary.

### Completed: bounded scoped search-index reprocess worker (2026-08-29)

- Added a service-only worker contract for the only currently proven-idempotent scope, `search_index`. Its database claim validates the delivered event, organisation, run, document, and exact current document version before issuing a short fenced lease; a replacement, deletion, or stale completion cannot update the newer version.
- The worker reads only bounded typed document-summary fields after claiming work. Its Trigger payload and task result contain identifiers and safe outcomes only—never a storage key, PDF, raw metadata, source text, provider response, or embedding—and it never invokes the legacy generic processor.
- Fenced completion atomically writes the 768-dimensional metadata-summary vector and effective model/version only for that active version, then marks the run ready. A repeated completion is idempotent; a stale/changed version is cancelled without touching document projections.
- Provider or completion failures retain only safe state. Search indexing may be reconciled at most twice after the first claim (three total attempts) because its overwrite is bounded and idempotent; exhaustion becomes a durable Review/recovery case. Extraction, OCR, relationship, and full scopes remain unavailable to the worker and continue to enter Review/recovery rather than replay legacy effects.
- SQL and TypeScript coverage exercises exact tenant/version claim fencing, grant boundaries, no-path/no-raw worker input, idempotent completion, bounded retry exhaustion, malformed/truncated embedding handling, and dispatch routing.
- The release fence requires the live durable-outbox lease token before a Trigger child may claim work, rejects unavailable scopes before they create work, and upgrades older queued unavailable scopes into terminal Review/recovery evidence. Vertex parsing is complete-JSON only, retains fixed safe diagnostics, pins model/version/task/dimensions, records provider token usage, and retries only twice with bounded jitter before durable recovery. The Timeline exposes the one executable 44px search-index action with a stable client idempotency key; unavailable scopes remain explicit.

### Completed: global Inbox canonical upload (2026-08-28)

- Global Inbox uploads now use the same reservation, private asset, server-observed completion, durable outbox, duplicate, quota, and idempotency contract as direct matter uploads. New uploads never create `staged_documents` rows or staging-bucket objects.
- The Inbox projects canonical unassigned Intake alongside a clearly marked read-only legacy staged adapter. Its 25 MiB, retryable-versus-terminal, safe failure, and explicit refresh behavior matches the lifecycle contract.
- Independent QA found and verified fixes for terminal-cleanup ownership, storage tombstone confirmation, retry metadata, and canonical state presentation. Focused tests, type checks, migration checks, and diff checks passed; broader legacy lint remains baseline-red.

### Completed: canonical Inbox placement and recovery boundaries (2026-08-28)

- Ready Intake can be assigned to an existing matter atomically without a storage copy, discarded through an idempotent ready-only command, and previewed only through an authorised Intake-ID grant.
- Command receipts are bound to the Intake subject, assignment emits the durable `intake.assigned.v1` event, and the shared version-4 capability matrix exposes discard only to Owner/Admin/Associate.
- Duplicate recovery covers current and superseded versions; a Trash-held-only match is non-disclosing and explicitly restore-required until the approved Trash workspace is implemented.
- Local SQL, build, type, migration, and focused tests passed; authenticated browser interaction could not be re-exercised without a local sign-in session.

## Interfaces and Data Changes

### Core tables

- `file_assets`: `id`, `org_id`, bucket/key, SHA-256, byte size, detected MIME, availability/quarantine state, created actor/time, deletion timestamps, and safe failure code.
- `upload_sessions`: `id`, `org_id`, uploader, reserved asset/key, declared bytes/MIME/name, intended matter, idempotency key, expiry, state, and finalized time.
- `intake_items`: `id`, `org_id`, asset, uploader, intended matter, origin, state, suggested client/matter and evidence reference, source-analysis run, assignment result, failure code, and timestamps.
- `document_versions`: `id`, `org_id`, `document_id`, version number, asset, original filename, validation/page data, state, replacement reason, creator/time, and current/retired timestamps.
- `document_version_analysis_bindings`: document version, compatible asset-scoped source-analysis run, binding reason, creator/time, and timestamps; exact storage belongs to the AI/Document Hub plan.
- `documents`: add `origin_kind`, `origin_external_key`, `record_state`, `content_availability`, `current_version_id`, `copied_from_document_id`, trashed actor/time/reason, and restored time. Retire physical `storage_path` after cutover.
- `document_processing_runs`: document/version, requested scopes, state/stage, idempotency key, attempts, linked extraction/indexing runs, safe error code/message, and timestamps.
- `outbox_events`: tenant; typed event kind/version; aggregate and safe routing IDs; idempotency key; delivery state; attempt count; next-attempt, lease, delivery, and timestamps; Trigger run ID; and safe error code. Payloads are allow-listed, versioned identifiers only and exclude content, paths, signed URLs, credentials, and arbitrary descriptions.
- `outbox_delivery_attempts`: append-only safe attempt metadata, lease/dispatch timing, Trigger run ID, outcome, and safe error category; detailed successful attempts are eligible for bounded compaction.
- `outbox_delivery_receipts`: compact payload-free proof of older successful delivery, retaining event/tenant/aggregate identity, event version, final Trigger run ID, attempt count, and delivery time.

### Domain commands

```ts
type DocumentSourceLocator = {
  documentId: string
  documentVersionId: string
  pageIndex?: number // 1-based PDF page index
  quote?: {
    exactText?: string
    prefix?: string
    suffix?: string
    regions?: Array<{ pageIndex: number; x: number; y: number; width: number; height: number }>
  }
}

type ContentAvailability =
  | 'metadata_only'
  | 'source_attached'
  | 'source_indexed'
  | 'source_unreadable'

type ProcessingScope =
  | 'validate'
  | 'extract'
  | 'ocr'
  | 'relationships'
  | 'search_index'
  | 'full'
```

- Upload reservation accepts intended context and declared file metadata and returns a bounded upload contract, not a general storage credential.
- Finalization identifies the session/idempotency key; the server verifies the stored object rather than trusting client-reported hash/size.
- Signed access accepts a document version or intake ID and resolves the private object after authorisation.
- Attach/replace, assignment, copy/move, reclassification, trash/restore/purge, and reprocess are typed domain commands with audited consequence/result contracts.

### Events

- `intake.uploaded`, `intake.validated`, `intake.ready`, `intake.assigned`, `intake.failed`, `intake.discarded`
- `document.created`, `document.file_attached`, `document.version_replaced`, `document.reassigned`, `document.copied`, `document.reclassified`, `document.trashed`, `document.restored`, `document.purged`
- `document.processing_requested`, `document.processing_stage_changed`, `document.processing_failed`, `document.processing_completed`

Event payloads contain IDs, state, safe reason codes, and source versions—not raw PDF text, signed URLs, or credentials.

## Testing and Acceptance Criteria

- Creating a metadata-only document requires no fake path/vector and immediately supports matter timeline placement and verified structured fields.
- Later PDF attachment preserves document ID and relationships; conflicts with existing imported metadata create review candidates instead of overwriting values.
- Replacing a PDF preserves old version access and quotations. New citations use the new version; historical notes/search/activity resolve the old one.
- Global and matter uploads use the same intake pipeline. Assignment performs no storage download/re-upload/move and is idempotent under double-click, retry, refresh, and repeated event delivery.
- Exact duplicate bytes are stored once per organisation and never deduplicated across organisations. Usage counts unique asset bytes once.
- Exact duplicate protection remains effective when the matching document, matter, or client is in Trash. Renaming the file, changing browser-reported MIME, or submitting a forged client hash cannot bypass server verification.
- Cross-tenant tests deny asset reservation, finalization, intake assignment, signed access, version attachment, copy/move, classification, deletion, restoration, and direct table/storage access.
- A caller cannot bypass the 25 MB application default or organisation/platform quota with false client size, concurrent reservations, chunked transfer, duplicate references, or an abandoned session.
- Uploads at the configured boundary are deterministic; malformed signature, encrypted PDF, missing object, oversize file, and validation timeout enter explicit recoverable states.
- Outbox dispatch survives application-process termination after database commit. Replayed events and worker retries do not duplicate document versions, extraction runs, links, deadlines, financial events, activity, or notifications.
- An immediate post-commit wake-up normally begins dispatch without waiting for the schedule; if it is missed, the one-minute recovery invocation leases the event. A wake arriving while the dispatcher runs neither cancels it nor causes two workers to lease the same event.
- A large organisation backlog cannot starve a later small-organisation upload. Bounded concurrency and borrowable fairness are covered under simultaneous multi-tenant load, expired leases, duplicate wakes, Trigger rate limits, and child-task completion refills.
- The dispatch hot path uses the due-state partial index and remains bounded when historical delivery rows are large. Retention never removes unresolved/dead-letter events, and compaction preserves the configured receipt while preventing delivered history from increasing every-minute read cost indefinitely.
- Reprocess creates a scoped durable command and cannot be used to bypass tenant authorisation, select a Trigger task, or blindly repeat uncertain downstream side effects.
- Promotion/demotion and reassignment show and apply the same tested consequence set. Self-links and cross-organisation links fail at database and server layers.
- Trash hides a document and all retrieval projections immediately. Restore recovers it during retention. Purge deletes derived/source data in dependency order and deletes a binary only when no live reference remains.
- Legacy backfill reports source row count, migrated count, missing objects, hash conflicts, duplicate assets, tenant mismatches, and unmigrated rows; cutover is blocked unless every row has an explicit terminal classification.
- The migration preserves stable document IDs and supports rollback to legacy reads until the verified contract phase begins.
- UI consumers meet the Civic Ink stable-chrome, scroll ownership, mobile capability, 44px touch target, loading/empty/error/partial state, keyboard, screen-reader, dark appearance, and 200% zoom requirements in their owning UI plans.

## Assumptions

- PDF is the only accepted original file format in this phase.
- Supabase private Storage remains the binary store, but database rows—not path parsing alone—are the source of access truth.
- The deployment remains on Supabase Free during the controlled pilot, so the conservative quotas in this plan are intentional configuration defaults.
- Spreadsheet mapping and GST-portal acquisition are later capabilities; both will call the document/intake domain contracts defined here.
- The separate Hierarchical Resource Trash plan is the authoritative retention, restoration, legal-hold, and purge contract.

## Open Questions

None.
