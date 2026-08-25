---
title: Hierarchical Resource Trash, Retention, and Purge
status: approved
created: 2026-08-24
updated: 2026-08-24
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ./2026-08-24-document-record-and-file-lifecycle.md
  - ./2026-08-24-ai-extraction-and-model-lifecycle.md
---

# Hierarchical Resource Trash, Retention, and Purge

## Summary

Introduce an organisation Trash that preserves the `Client → Matter → Document` hierarchy. Moving a resource to Trash makes the selected root and its active descendants unavailable to ordinary workflows while keeping their normal routes, data, files, audit history, and nested navigation readable in an unmistakable read-only state.

Each delete action creates one grouped trash operation. Descendants inherited from that action do not clutter the top-level Trash list and cannot be restored or purged separately. Restoration reverses only the members introduced by that operation. Permanent purge is restricted to Owner/Admin, requires an impact preview and explicit confirmation, follows dependency-aware resumable cleanup, and never occurs merely because storage is full.

## Context and Goals

Current client and matter deletion uses service-role code to timestamp several child tables independently. It can leave partial state when a later update fails, hard-deletes Matter wiki sections immediately, mutates staging suggestions ad hoc, and has no restore workflow or Trash UI. Database foreign keys also retain destructive `ON DELETE CASCADE` paths that are unsuitable as ordinary legal-record deletion behavior.

The intended experience is recoverable and intelligible: a deleted client appears once in Trash; opening it renders the familiar client page with its matters and documents, but the entire subtree is read-only until the client is restored. The system must also handle independently deleted descendants, uniqueness conflicts, shared files, cross-matter links, deadlines/reminders, tasks, review items, notifications, search, processing jobs, retention changes, legal holds, and partial purge failure.

The hierarchy, read-only experience, duplicate protection, retention defaults, purge safeguards, and role boundary in this plan were approved on 2026-08-24.

## Decisions

### Scope and hierarchy

- The first-class trashable resources are `client`, `matter`, and `document`.
- Hierarchy is fixed for this phase: Client owns Matters; Matter owns Documents. Notes, Case Brief content, deadlines, financials, relationships, tasks, review items, extraction data, search chunks, and file versions are dependent data governed by their owning resource's effective trash state; they are not separate top-level Trash cards.
- Moving a client to Trash includes every currently active matter and document beneath it. Moving a matter includes every currently active document beneath it. Moving a document includes only that document and its dependent data.
- Use application-level archival transactions, not physical database cascades, for ordinary deletion. Replace or fence destructive `ON DELETE CASCADE` parent paths before exposing permanent purge.

### Trash operation model

- Each delete command creates one `trash_operations` root with organisation, resource type/ID, actor, reason, creation time, retention-policy snapshot, descendant counts, unique storage bytes, and state.
- Each active resource affected by the command gets a `resource_trash_memberships` row with resource type/ID, root operation, parent membership, cause (`direct` or `inherited`), prior lifecycle state, and restoration/purge state.
- Resources already in Trash before an ancestor is deleted are not adopted into the new operation. They are counted as pre-existing exclusions and retain their original trash operation and retention history.
- Each client, matter, and document has at most one active trash membership and an effective `record_state` of `active`, `trashed`, `purging`, or `purged`.
- The delete transaction locks the root, computes active descendants, writes all memberships, updates resource states, appends activity/outbox events, and commits atomically. A failure leaves the entire hierarchy active.
- Repeated delete submissions use an idempotency key and return the existing operation.

### Permissions

- Viewer cannot trash, restore, or purge anything.
- Associate may move an individual document to Trash and restore a document they trashed, subject to matter access. Associate cannot trash or restore a client/matter and can never permanently purge.
- Owner/Admin may trash and restore clients, matters, and documents.
- Permanent purge is Owner/Admin only. An organisation may later split purge into a dedicated capability without changing the domain contract.
- A deleted subtree is read-only for every role. Owner/Admin receives Restore and eligible purge actions in the Trash context; no role can edit the subtree without restoration.

### Trash workspace and read-only routes

- Add `/trash` to organisation utilities. Its primary list shows root trash operations only, with resource type/name, original parent context, deleted by/date/reason, included descendant counts, unique storage size, retention or auto-purge date, legal-hold state, and purge status.
- Allow filtering by resource type, actor, deletion date, purge eligibility, and hold. A root can expand to a nested tree; inherited members are labelled and have no independent restore/purge action.
- Opening a trashed resource uses its normal canonical route and page composition. Route loaders recognise exact trashed IDs through a secured trash-aware query; ordinary collection queries continue excluding trashed rows.
- Every trashed page shows a persistent full-width `In Trash — read only` context strip immediately below the stable application/context header. Use the Civic Ink danger surface, border, icon, and explicit text rather than a saturated solid-red bar or red-tinted page. The strip contains deletion actor/date, root operation, retention status, Back to Trash, and permitted Restore action; it remains available while the page body scrolls.
- On mobile, reduce the strip to the status, deleted date, and one Restore/More action without hiding the explanation. Colour is never the only signal, reduced motion is respected, and the strip must meet contrast and screen-reader requirements.
- If the opened item is an inherited descendant, the banner identifies the deleted ancestor and explains that the ancestor must be restored. Do not offer a misleading child restore button.
- Hide or disable editing, upload, note/reply, relationship, reprocess, reminder, assignment, and destructive feature actions. Preserve navigation, PDF viewing, metadata, timeline, Files, Case Brief, Notes, Deadlines, Financials, Details, and Activity in read-only mode.
- Direct links from Activity or old Notifications may open the read-only Trash context if the caller retains access; they must not return a confusing generic 404.

### Effects on dependent domains

- Search removes the entire subtree immediately after the trash transaction and never returns its snippets or counts in ordinary results. Trash search is metadata-only within `/trash`; full legal content search of deleted resources is deferred.
- Activity remains append-only and visible in the trashed resource and organisation Activity according to permissions.
- Notes, quotations, Case Brief versions, deadlines, financials, extraction history, and file versions remain preserved and readable. No new edits or AI refreshes run while the owner is trashed.
- Deadline reminders and scheduled automations are suspended, not marked completed. Restoration recalculates future schedules; it never sends accumulated reminders for dates that passed while trashed without a new user decision.
- Tasks and review items tied only to the trashed subtree become `suspended_resource_trashed`. They leave Today/My Work/Review active counts but retain prior assignee/state. Restoration reactivates still-relevant open items; expired or conflicting items return to Review rather than firing automatically.
- In-flight document processing receives cancellation where supported. Completed results may be stored for audit but cannot reactivate search, create notifications, or mutate effective state while the resource is trashed.
- Cross-subtree relationships are retained with an endpoint-unavailable state. Active documents do not expose legal content from the trashed endpoint. Restoration reactivates the relationship only when both endpoints are active and the relationship was not separately rejected/archived.
- Intake items merely suggested to a trashed client/matter lose the suggestion and are re-evaluated. An explicit intended matter that becomes trashed requires a new placement decision; it is never silently redirected.
- Trashed and historical assets continue counting against the organisation quota. Quota pressure shows a link to Trash/storage management but never purges legal data automatically.

### Restoration

- Restore is root-operation scoped. It restores only resources whose active membership belongs to that operation; descendants that were already independently trashed remain in their original Trash entries.
- Restoring an inherited child independently is not allowed. Restore the root ancestor, then make any desired child-level deletion separately.
- Before restore, validate that required parents are active or are part of the same operation, tenant ownership remains valid, and unique identifiers/codes do not conflict with active records created after deletion.
- A separately trashed parent blocks child-root restoration. The UI links to the blocking ancestor operation.
- Uniqueness conflicts never trigger silent renaming, identifier clearing, or merging. Restore remains blocked with a resolution workflow for an authorised admin to correct the active or trashed record deliberately.
- Restore writes all state changes, activity/outbox events, schedule recalculation requests, and search/index requests atomically. It preserves stable IDs and prior URLs.
- Restoration does not automatically resume failed processing, accept AI candidates, send missed notifications, or reinstate archived cross-links. Those actions are re-evaluated after the records become active.

### Duplicate protection while in Trash

- Exact-PDF duplicate detection covers active documents, all Trash operations, document-version history, and unassigned Intake within the organisation. Trash is not an escape hatch from duplicate protection.
- If an uploaded PDF hash belongs to a trashed document or a document inherited under a trashed matter/client, CaseChain blocks creation of a new document and explains that the existing record is in Trash.
- An authorised user receives `View in Trash` and, when permitted, `Restore` or `Restore deleted ancestor`. Uploading into, attaching a version to, or replacing a file on a trashed resource is forbidden until restoration.
- If the same asset has both an active reference and a trashed reference, the active record is the primary duplicate result. If the caller lacks access to the matching matter, return a non-disclosing duplicate message and an administrator escalation path rather than its identity.
- Filename changes do not bypass detection because the server-verified SHA-256 is authoritative. Client-computed hashes may provide an early warning but are never trusted as the final decision.
- Similar reference numbers, filenames, or metadata without an exact file hash are not hard-blocked; they create a possible-duplicate Review decision because legitimate legal documents and later versions can share identifiers.
- After a permanent purge, the hash blocks upload only while another surviving document version, Intake item, export, hold, or asset reference exists. Cross-organisation matches are never disclosed or reused.

### Retention settings

- Organisation Settings includes Trash retention controlled by Owner/Admin. Options are `Manual purge only`, 30, 60, 90, 180, or 365 days; recommend 90 days for a legal workspace.
- The initial product default is `Manual purge only`. This avoids silently destroying legal records before an organisation intentionally chooses an automated policy.
- Retention is snapshotted on each trash operation. A later settings change applies to future deletions. Extending existing entries is allowed in bulk; shortening existing retention requires a separate explicit impact confirmation and never bypasses legal hold.
- Automatic purge is a separate switch, off by default. Enabling it requires Owner/Admin confirmation and displays the next eligible operations. A background purge is considered an administrator-authorised policy action and remains fully audited.
- Changing from automatic to manual purge cancels unstarted scheduled purges. It cannot reverse an operation whose purge transaction has begun.
- Storage quota exhaustion does not shorten retention, enable auto-purge, or select records for deletion.

### Permanent purge

- Purge can target only a root trash operation. It includes every membership owned by that operation and the dependent data that cannot outlive those resources.
- Before scheduling purge, show exact root identity, descendant counts by type, unique bytes likely to be freed, shared assets that will remain, holds/blockers, and consequences for notes, citations, deadlines, financials, activity, and integrations.
- Manual purge requires recent authentication and typed confirmation using the resource name or matter/client code. Client and matter purges require a second confirmation after the impact calculation.
- A legal hold on any included resource blocks the whole operation. Do not partially purge a client or matter around a held descendant.
- Purge is asynchronous, durable, idempotent, and dependency ordered: disable active projections/jobs; remove search/embeddings; remove notification deliveries and task/review projections as policy requires; purge collaboration/derived facts according to retention; remove relationships; detach document versions; delete unreferenced assets; anonymise or retain mandatory activity tombstones; then mark the root purged.
- Once purge begins, the subtree cannot be restored. If a stage fails, the operation becomes `purge_failed`, remains inaccessible, exposes a safe admin retry, and does not pretend that storage was freed.
- A file asset is deleted only after a transaction proves there are no surviving document-version, intake, export, or hold references. Organisation-local deduplication therefore cannot make one document purge erase another document's PDF.
- Activity retains a minimal tombstone containing organisation, resource type, former opaque ID, purge actor/policy, timestamp, and operation ID. It does not retain names, legal content, filenames, reference numbers, or extracted facts after purge.

### Legal hold and exports

- Add a legal-hold/blocker contract even if the first UI ships later. A hold prevents permanent purge but does not prevent moving a resource to Trash or restoring it.
- Active export/backup generation blocks purge until it completes or is cancelled. Exports created before deletion remain governed by their own expiry and audit policy.
- Platform administrators cannot bypass tenant legal holds or purge tenant content through the ordinary platform console. Exceptional support procedures require a separate audited operations plan.

## Implementation Plan

1. Add `trash_operations`, `resource_trash_memberships`, organisation trash settings, resource record-state fields, legal-hold/blocker interface, RLS, unique active-membership constraints, and typed operation states.
2. Replace current service-role multi-update deletion functions with transactional security-definer domain functions or equivalent server transactions that verify caller capability and tenant lineage.
3. Add hierarchy-aware trash commands for document, matter, and client, including idempotency, pre-existing descendant handling, impact counts, activity/outbox events, and dependent-domain suspension.
4. Extend organisation-local duplicate resolution across active, historical, Intake, and Trash references. Add non-disclosing access behavior and restore-aware duplicate actions before permitting another canonical document.
5. Add trash-aware exact-resource loaders and read-only capability context. Keep active collection queries and search strictly filtered to active state.
6. Build `/trash` using the shared server-driven table/list, nested operation tree, filters, storage impact, retention/hold states, responsive drill-down, and stable scroll ownership.
7. Add the persistent danger-context Trash strip and action suppression to Client, Matter Workspace, and Document Workbench routes on desktop and mobile.
8. Implement root-scoped restore with parent/uniqueness validation, conflict resolution, dependent-domain reactivation/re-evaluation, and atomic indexing/schedule events.
9. Implement organisation retention settings and prospective policy snapshots. Add optional auto-purge scheduling only after manual purge is proven.
10. Implement impact calculation, recent-auth/typed confirmation, durable purge orchestration, blocker checks, dependency cleanup, shared-asset reference checks, tombstones, retry, and operational visibility.
11. Migrate existing `deleted_at` records into synthetic trash operations with explicit unknown actor/reason where necessary. Preserve IDs and never infer that already hard-deleted legacy data is recoverable.
12. Replace dangerous parent `ON DELETE CASCADE` constraints or restrict physical parent deletion to the purge orchestrator after children are handled.
13. Remove legacy page-specific delete implementations only after client, matter, document, dependent-domain, restore, and purge acceptance tests pass.

## Interfaces and Data Changes

- `trash_operations`: root type/ID, organisation, actor/reason, state, policy snapshot, purge eligibility/schedule, counts, deduplicated bytes, hold/blocker summary, error code, and lifecycle timestamps.
- `resource_trash_memberships`: operation, resource type/ID, parent membership, direct/inherited cause, prior state, restore/purge state, and timestamps; unique active membership per resource.
- `organisation_retention_settings`: trash retention mode/days, auto-purge flag, updated actor/time, and policy version.
- `resource_holds`: organisation, resource locator, inherited scope, reason, authority/reference, creator/time, release actor/time, and state.
- Client, Matter, and Document add typed `record_state` plus active trash membership reference. Legacy `deleted_at` remains during migration only.

```ts
type TrashResourceType = 'client' | 'matter' | 'document'

type TrashOperationState =
  | 'trashed'
  | 'restore_blocked'
  | 'restoring'
  | 'purge_scheduled'
  | 'purging'
  | 'purge_failed'
  | 'restored'
  | 'purged'

type TrashImpact = {
  clients: number
  matters: number
  documents: number
  uniqueBytes: number
  sharedBytesRetained: number
  preExistingTrashedDescendants: number
  blockers: Array<{ code: string; resourceType: TrashResourceType; resourceId: string }>
}
```

## Testing and Acceptance Criteria

- Deleting a document, matter, or client is atomic, idempotent, tenant-scoped, and creates one root Trash card with the correct inherited tree and impact counts.
- A pre-deleted document remains independently trashed when its later-deleted matter/client is restored.
- Uploading the same bytes as an active, historical, Intake, or trashed PDF cannot create a new document. A trashed match routes to the correct root restore flow; renamed files and forged client hashes do not bypass the block.
- Metadata-only similarity does not create a false hard block; possible duplicates enter Review with evidence.
- Normal lists, Search, Today, My Work, Review, reminders, and active APIs expose no trashed content or counts. Exact authorised routes render the familiar resource read-only with clear Trash context.
- Trashed client pages navigate through their trashed matters/documents without enabling a mutation. Inherited descendants point restoration to the correct root.
- Viewer, Associate, Admin, and Owner capability tests cover each resource level, direct Server Action/RPC invocation, forged organisation IDs, and service-role boundary.
- Restore preserves IDs/URLs and reactivates only the operation's members. Parent and uniqueness conflicts block restore without partial changes or silent renaming.
- Deadlines do not send reminders while trashed; tasks/review items suspend; in-flight jobs cannot republish content; restoration does not send a burst of missed alerts.
- Cross-matter links and shared assets remain safe when one endpoint/document is trashed, restored, or purged.
- Retention changes are prospective by default. Existing entries never receive a shorter purge date without explicit confirmation. Disabling auto-purge cancels unstarted schedules.
- Manual and automatic purge honor holds, recent-auth and confirmation policy, dependency order, retries, shared references, and minimal tombstones. A partial failure never reports success or freed bytes.
- Quota exhaustion cannot invoke or accelerate purge. Trashed bytes remain visible and counted until assets are actually deleted.
- Existing legacy soft-deleted records migrate into accessible Trash entries when their source data/files still exist; migration reports unrecoverable inconsistencies.
- Trash and read-only routes meet Civic Ink responsive, keyboard, screen-reader, dark appearance, long-content, loading/error/empty, 200% zoom, touch-target, and scroll-ownership requirements.
- The danger-context strip stays visible with stable workspace chrome, communicates status without colour alone, remains restrained in light/dark appearances, and does not reduce the legal content body to an unusable height on mobile or at 200% zoom.

## Assumptions

- CaseChain legal records require a conservative deletion model; convenience does not justify irreversible implicit cascades.
- Manual purge only is the safest initial default. Organisations may intentionally enable a timed policy later.
- Trash retention and legal hold are organisation policy, while platform storage guards remain independent operational constraints.
- Dependent domain plans will implement their suspension, restoration, and purge hooks against the events defined here.

## Open Questions

None.
