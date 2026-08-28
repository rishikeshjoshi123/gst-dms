---
title: Document Record and File Lifecycle
status: in-progress
created: 2026-08-24
updated: 2026-08-28
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

- A document write that requires processing commits a versioned `outbox_event` in the same transaction. A dispatcher delivers it to Trigger.dev and records delivery/attempt state; a missed gateway call cannot lose processing intent.
- Intake/source-analysis runs own validation, page/OCR, and extraction before placement. `document_processing_runs` owns document/version-scoped materialization and downstream projection after placement. Both use the same outbox/idempotency contract and reference the immutable asset/source-analysis run rather than inferring completion from mutable metadata.
- The initial user-facing stages are `Queued → Validating → Extracting → Matching → Ready`, plus `Review` and `Failed`. Stages are not displayed as fabricated percentages.
- Processing events carry versioned payloads and idempotency keys. Repeated delivery skips completed work or resumes the failed stage without duplicating candidates, links, deadlines, financial events, embeddings, activity, or notifications.
- Reprocessing selects an explicit scope: extraction, OCR/text, matching/relationships, search indexing, or full. A general standard-user `Sync`/rebuild action is not part of the lifecycle.
- Upload/processing completion updates inline state and Activity. It creates a personal notification only when a failure or decision requires that recipient.

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
5. **Introduce durable dispatch.** Add an outbox dispatcher and idempotent version-scoped Trigger.dev orchestration. Reconcile stuck queued/delivered runs and expose safe operational metrics without legal content.
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

### Canonical next action

Convert the **global Inbox upload and staged-assignment flow** to the same canonical upload-session/intake-item pipeline. Preserve legacy reads only behind a bounded compatibility adapter, eliminate staging-bucket copy on assignment, and then run the same independent database, authorization, and UI QA gates before beginning backfill work.

## Interfaces and Data Changes

### Core tables

- `file_assets`: `id`, `org_id`, bucket/key, SHA-256, byte size, detected MIME, availability/quarantine state, created actor/time, deletion timestamps, and safe failure code.
- `upload_sessions`: `id`, `org_id`, uploader, reserved asset/key, declared bytes/MIME/name, intended matter, idempotency key, expiry, state, and finalized time.
- `intake_items`: `id`, `org_id`, asset, uploader, intended matter, origin, state, suggested client/matter and evidence reference, source-analysis run, assignment result, failure code, and timestamps.
- `document_versions`: `id`, `org_id`, `document_id`, version number, asset, original filename, validation/page data, state, replacement reason, creator/time, and current/retired timestamps.
- `document_version_analysis_bindings`: document version, compatible asset-scoped source-analysis run, binding reason, creator/time, and timestamps; exact storage belongs to the AI/Document Hub plan.
- `documents`: add `origin_kind`, `origin_external_key`, `record_state`, `content_availability`, `current_version_id`, `copied_from_document_id`, trashed actor/time/reason, and restored time. Retire physical `storage_path` after cutover.
- `document_processing_runs`: document/version, requested scopes, state/stage, idempotency key, attempts, linked extraction/indexing runs, safe error code/message, and timestamps.
- `outbox_events`: tenant, event kind/version, aggregate, idempotency key, payload, delivery state, attempts, scheduling/lease data, and timestamps.

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
