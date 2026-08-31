# Work Catalogue Inventory

**Status:** completed prerequisite for the approved [Work Orchestration, Review, Activity, Notifications, and Today plan](./plans/features/2026-08-25-work-review-activity-notifications.md).  
**Recorded:** 2026-08-31  
**Scope:** current runtime callers and schema only; this is a disposition contract, not a migration record. No consumer has migrated because of this inventory.

## Reading the catalogue

Each row has exactly one approved destination: **Activity**, **Task**, **Review**, **Notification**, **inline status**, **operational telemetry**, or **removal**. “Live” means a current production path can read or write it; “compatibility/dead” means it is retained only for historical compatibility, migration safety, or has no current producer. Source links deliberately identify code and schema, never document contents, storage keys, credentials, or tenant identities.

## Current Activity actions

| Current action / source | State | Destination | Disposition |
| --- | --- | --- | --- |
| [`client_created`](../src/lib/actions/client.ts#L91) | Live caller | Activity | Material client creation; replace free-form description with an approved event definition and safe snapshots. |
| [`client_updated`](../src/lib/actions/client.ts#L157) | Live caller | Activity | Material client change; event payload must not preserve GSTIN/PAN or other sensitive field values. |
| [`document_copied`](../src/lib/actions/document.ts#L374) and [`document_reassigned`](../src/lib/actions/document.ts#L418) | Live callers | Activity | Material document lifecycle/context changes. |
| [`manual_link_created`](../src/lib/actions/document.ts#L717), [`manual_link_deleted`](../src/lib/actions/document.ts#L776), and [`link_resolved`](../src/lib/actions/chaining.ts#L173) | Live callers | Activity | Link decision/history; pending/unresolved link state itself is separately catalogued under Review or inline status. |
| `document.metadata_created`, `document.intake_assigned`, `document.file_attached`, and `document.version_replaced` | Live canonical SQL command paths ([definitions](../supabase/migrations/00037_document_materialization_commands.sql#L157), [current replay fences](../supabase/migrations/00083_document_command_idempotency_replay_fence.sql#L98)) | Activity | Material record/evidence lifecycle events. Use source-version-safe locator/snapshots; do not expose file paths. |
| `resource_trashed` / `resource_restored` | Live canonical SQL paths ([trash](../supabase/migrations/00090_trash_retention_policy_and_attention.sql#L396), [restore](../supabase/migrations/00088_root_scoped_trash_restore.sql#L502)) | Activity | Material lifecycle history, with the approved Trash-safe locator. No ordinary task/review/notification is created solely by Trash. |
| `resource_purged` rewrite of historical activity | Live canonical permanent-delete path ([tombstone rewrite](../supabase/migrations/00091_root_operation_permanent_delete.sql#L908)) | Activity | Preserve only content-free purge/tombstone history; the rewrite intentionally removes mutable description/metadata and disables reversal. |
| `organisation_invitation.*` lifecycle | Live SQL function ([event append](../supabase/migrations/00030_organisation_invitations_and_membership_rls.sql#L129)) | Activity | Material administration/security history; actor/target snapshots must remain non-disclosing after membership changes. |
| `document_processed`, `deadline_created`, `deadline_resolved`, note, matter, and deletion labels present only in the dashboard renderer | Compatibility/dead labels, not verified producers ([label table](<../src/app/(app)/dashboard/DashboardContent.tsx#L77>)) | removal | Do not backfill a producer from presentation strings. Resolve every historical `activity_logs.action` during later migration; unrecognised values need an explicit disposition. |
| Any `activity_logs` row resolved through live documents, links, or an admin user directory | Live legacy reader ([query](../src/lib/actions/notifications.ts#L70), [live reconstruction](../src/lib/actions/notifications.ts#L87)) | removal | Replace the reader with append-only Activity snapshots/typed locators. It currently depends on deleted records and privileged user enumeration. |

## Review reasons and sources

| Current source / reason | State | Destination | Disposition |
| --- | --- | --- | --- |
| Document `status = needs_review` and free-text `review_reason` queried by the Review page ([query](../src/lib/actions/notifications.ts#L279)) | Live legacy queue | Review | Replace with typed Review items; current generic dismiss is not an approved resolver. |
| Provenance `invalid_model_output`, `provider_failed`, `provenance_candidate_review_required`, and `provenance_review_required` ([writer](../supabase/migrations/00067_document_processing_provenance_write_path.sql#L368)) | Live worker/SQL producer | Review | Map to approved extraction invalid/conflict or supported processing-recovery decision with source version/evidence. A clean extraction must not create Review. |
| Exact duplicate return (`exact_duplicate`) ([worker](../src/trigger/jobs.ts#L148)) | Live worker result, but no normalized Review producer | Review | Approved possible-duplicate Review source; create it only in the later Review foundation, not from the status return itself. |
| Cross-matter reference (`Referenced document found in a different matter`) ([canonical SQL](../supabase/migrations/00078_document_processing_relationship_placement.sql#L386)) | Live canonical producer | Review | Approved inferred/conflicting-relationship decision; current document flag and notification are legacy adapters. |
| Fuzzy inferred `document_links.status = pending` ([canonical SQL](../supabase/migrations/00078_document_processing_relationship_placement.sql#L237)) | Live legacy queue | Review | Approved inferred/conflicting-relationship Review, with evidence and typed confirm/reject resolver. |
| Pending link with no target ([creation](../supabase/migrations/00078_document_processing_relationship_placement.sql#L403)) | Live source state | inline status | Keep as relationship/intake context until an actual ambiguity/conflict exists; do not turn routine incompleteness into Review. |
| Restore preflight `client_identifier_conflict`, `matter_identifier_conflict`, or `document_content_conflict` ([SQL fences](../supabase/migrations/00088_root_scoped_trash_restore.sql#L195)) and concurrent `uniqueness_conflict` ([UI model](../src/lib/trash/restore-model.ts#L8)) | Live restore conflict sources | Review | Approved restore-conflict Review type; preserve the safe conflict code/evidence boundary rather than treating it as routine inline failure. |
| Ordinary staged/unassigned intake or `pending_placement` | Live intake state ([schema](../supabase/migrations/00001_initial_schema.sql#L86)) | inline status | Document Hub owns it. It is explicitly not Review. |
| “Dismiss review flag” ([mutation](../src/lib/actions/document.ts#L441)) | Live legacy resolver | removal | Retire during Review cutover; only a type-specific decision may resolve/dismiss an approved Review item. |
| Legacy Review page’s note action-item tab ([four-table query](../src/lib/actions/notifications.ts#L302)) | Live compatibility consumer | removal | It double-counts note tasks and must disappear when Tasks/My Work replaces it. |

## Note action items

| Current source | State | Destination | Disposition |
| --- | --- | --- | --- |
| `case_notes.is_action_item`, assignee, due date, and resolved fields ([schema](../supabase/migrations/00001_initial_schema.sql#L253)) | Live legacy source | Task | One note action item becomes one Task with origin snapshot/locator, assignee, due contract, and completion state. Do not create an additional task for the note itself. |
| Note creation writes the action-item fields ([writer](../src/lib/actions/notes.ts#L97)) | Live caller | Task | Replace with a note command plus optional Task command; note edits/deletion cannot silently mutate the Task. |
| Note action-item completion toggle ([matter UI](../src/components/matters/MatterNotesTab.tsx#L141)) | Live legacy consumer | Task | Route to a Task transition after migration. The legacy `action_item_resolved` flag is not another Review state. |
| Action-item filters in Notes/Matter Notes ([query](../src/lib/actions/notes.ts#L30)) | Live compatibility consumer | removal | Replace with an origin-linked Task projection; retain note-only filtering separately. |

## Notifications and reminder delivery

| Current type/source | State | Destination | Disposition |
| --- | --- | --- | --- |
| `mention` | Schema/UI only; no current producer found ([enum](../supabase/migrations/00001_initial_schema.sql#L333)) | Notification | Approved allowlist family once a direct mention producer and authorised target exist. No invented mention parsing/delivery policy. |
| `org_invite` | Schema/UI legacy type; invitation lifecycle is live ([event path](../supabase/migrations/00030_organisation_invitations_and_membership_rls.sql#L129)) | Notification | Approved mandatory invitation/access family; build intents/deliveries from the invitation domain, not generic `activity_logs`. |
| `chain_suggestion` for progression inference, fuzzy link, or cross-matter detection ([helper](../src/lib/actions/chaining.ts#L239); [calls 69](../src/lib/actions/chaining.ts#L69), [103](../src/lib/actions/chaining.ts#L103), [124](../src/lib/actions/chaining.ts#L124), [317](../src/lib/actions/chaining.ts#L317), [328](../src/lib/actions/chaining.ts#L328); [canonical SQL insert](../supabase/migrations/00078_document_processing_relationship_placement.sql#L245)) | Live legacy producers | Review | Remove personal notification producers; the source becomes a typed relationship Review item. Review assignment/escalation may later notify via the approved allowlist. |
| `document_ready` | Schema/UI only; no current producer found ([enum](../supabase/migrations/00001_initial_schema.sql#L333)) | removal | Routine successful processing is not a notification. |
| `processing_failed` | Schema/UI only; no current notification producer found ([enum](../supabase/migrations/00001_initial_schema.sql#L333)) | Notification | Approved only when a failure requires a specific user’s action. Otherwise it remains operational telemetry/inline processing state. |
| `deadline_approaching` | Schema/UI only; scheduler is a no-op ([cron](../src/trigger/jobs.ts#L383)) | Notification | Approved only for verified deadline, assigned/subscribed recipient, and validated lead-time/dedupe policy. No current reminder is sent. |
| `staged_doc_ready` | Compatibility-only historical notification ([retirement rule](../src/lib/notifications/staged-retirement.ts#L1)) | removal | Retain historical row non-actionably until the later migration disposition; do not route it. |
| `wiki_ai_suggestion` | Schema/UI only; no current producer found ([enum](../supabase/migrations/00001_initial_schema.sql#L333)) | removal | Routine Case Brief refresh/suggestion is not a notification. |
| Legacy notification list, unread count, and boolean read mutations ([actions](../src/lib/actions/notifications.ts#L7)) | Live legacy consumer | removal | Replace with personal notifications, `read_at`/archive state, valid authorised target, intent/delivery dedupe, and secure counts. The current System tab is removed ([filter](<../src/app/(app)/notifications/NotificationsClientView.tsx#L86>)). |
| `sendDeadlineReminderEmail` / `sendMentionEmail` helpers | Dead code / callable helper with no caller found ([helpers](../src/lib/email.ts#L104)) | removal | Do not activate directly. Later delivery uses policy-controlled notification deliveries and content-minimised templates. |

## Processing failures, retries, and outbox

| Current source | State | Destination | Disposition |
| --- | --- | --- | --- |
| `document_processing_runs` terminal `failed` / `stage = failed` ([state update](../supabase/migrations/00039_document_processing_orchestration.sql#L90)) | Live processing state | inline status | Show safe state on the document/intake context; it is not Activity or Notification by default. |
| Retry/reconciliation and safe codes such as `scoped_reprocess_unavailable`, `search_index_retry_exhausted`, and `legacy_processing_recovery_required` ([recovery fence](../supabase/migrations/00057_scoped_reprocess_upgrade_recovery.sql#L270)) | Live recovery producer | Review | Approved supported processing-recovery decision when automatic replay is unsafe/exhausted; it must carry run/evidence/version, not be inferred from a retry. |
| Dispatch lease/ack/fail state and attempts ([dispatcher](../src/lib/outbox/dispatcher.ts#L155)) | Live infrastructure | operational telemetry | Durable delivery observation and retry only; do not render retries as Activity or notify users. |
| Successful processing, validation, extraction, embedding, and ordinary outbox wake/recovery | Live infrastructure | operational telemetry | Exclude from personal notifications and Review unless a typed exception above occurs. Material completed processing may later receive an approved Activity definition, but this catalogue does not create one. |

## Dashboard queries and compatibility routes

| Current dashboard query / feature | State | Destination | Disposition |
| --- | --- | --- | --- |
| Client, matter, document, and pending-review count cards ([page query](<../src/app/(app)/dashboard/page.tsx#L12>)) | Live | removal | Today excludes portfolio totals and vanity metrics. |
| `getNeedsReviewDocuments` ([query](../src/lib/actions/document.ts#L76)) | Live | Review | Replace with secured Review read model; no ordinary intake placement. |
| `getUpcomingDeadlines` future-only, organisation-wide query ([query](../src/lib/actions/notifications.ts#L237)) | Live | inline status | Deadline remains authoritative. Later Today/My Work derives verified assigned/subscribed deadline work and includes overdue; no Task copy. |
| Recent 15 `activity_logs`, client-side search/entity/time filter and pagination ([fetch](<../src/app/(app)/dashboard/page.tsx#L34>), [filter](<../src/app/(app)/dashboard/DashboardContent.tsx#L177>)) | Live | Activity | Replace with server-paginated Activity filters and a five-event Today preview; remove dashboard-local filtering. |
| Dashboard-owned `searchAll` ([caller](<../src/app/(app)/dashboard/DashboardContent.tsx#L155>)) | Live | removal | Search remains its own shell capability. |
| Trash-retention team attention ([dashboard use](<../src/app/(app)/dashboard/page.tsx#L34>)) | Live | inline status | Later Today Team attention keeps only authorised, deduplicated 24-hour root-Trash warning; it is not a task/review/notification. |
| `/dashboard` page | Live compatibility route | removal | Replace with compatibility redirect to canonical `/today` only after Today is built. |

## Known unresolved or missing sources

- No live producer was found for `mention`, `deadline_approaching`, `document_ready`, `processing_failed`, or `wiki_ai_suggestion`; their schema/UI presence is not evidence of a caller.
- The current deadline model has only 30/7-day sent booleans ([schema](../supabase/migrations/00001_initial_schema.sql#L231)); verification, recipients/subscriptions, timezone, lead-time policy, and actual delivery source are absent. This inventory does not invent them.
- Existing `activity_logs.action` values may include historical values not represented by a current producer. The later additive migration must classify each stored value explicitly before removal.
- Exact duplicate returns a worker result but does not currently materialise a normalized Review row. Current status flags do not provide the evidence/decision contract required for Review.

## Exact next coherent live foundation slice

Implement plan step 2: add the append-only Activity definition/event foundation and transactional outbox/projector contract (safe snapshots, typed locators, idempotency, RLS, and Trash behavior). This is the first live slice; it does **not** migrate the catalogue’s consumers or producers yet.
