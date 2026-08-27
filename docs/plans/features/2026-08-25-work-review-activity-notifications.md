---
title: Work Orchestration, Review, Activity, Notifications, and Today
status: approved
created: 2026-08-25
updated: 2026-08-27
owners:
  - product
  - engineering
related:
  - ../platform/2026-08-24-product-architecture-portfolio.md
  - ../platform/2026-08-24-document-record-and-file-lifecycle.md
  - ../platform/2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
  - ./2026-08-24-universal-search-and-evidence-retrieval.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Work Orchestration, Review, Activity, Notifications, and Today

## Summary

Replace CaseChain's overlapping dashboard, pending-review queries, note action items, ad hoc activity logs, and noisy notifications with five explicit capabilities:

- **Activity** is immutable organisation and matter history.
- **Tasks** are owned work with an assignee and lifecycle.
- **Review** contains a specific human decision that cannot safely be automated.
- **Notifications** are personal interruptions caused by direct responsibility or urgent risk.
- **My Work** and **Today** are secured read models over tasks, review assignments, verified deadlines, mentions, failures, recent work, and activity; they do not duplicate source state.

Make `/today` the authenticated command centre and keep `/dashboard` as a compatibility redirect. Today uses deterministic urgency groups rather than vanity statistics or opaque AI ranking. Organisation Review, Activity, and Notifications receive dedicated workspaces with valid source locators, server-side filters, stable counts, and mobile-equivalent flows.

## Context and Goals

The current Dashboard counts clients, matters, documents, and review rows, performs a small dashboard-owned search, omits overdue deadlines, and filters only 15 fetched activity rows in the browser. The current Review page merges `documents.status = needs_review`, pending links, note action items, and staged assignment into tabs even though these require different ownership and decisions. `case_notes` stores task fields on messages, so a task has no independent lifecycle or audit. `activity_logs` stores free-form descriptions and reconstructs meaning later from live/deleted records and an administrator user listing, which makes historical rendering unstable. Notifications include routine document completion, staging readiness, link suggestions, and Case Brief refreshes, while many target routes are incomplete.

The overhaul must answer five separate questions without ambiguity:

- What happened? Activity.
- What work do I own? Tasks and My Work.
- What decision is waiting for a human? Review.
- What needs to interrupt me? Notifications.
- What should I do or resume today? Today.

Success means the same source item has one lifecycle, counts agree everywhere, routine automation does not create notification noise, every review row provides evidence and a valid decision, and every item deep-links to the exact accessible context.

The domain separation, Today/My Work philosophy, Review and Activity models, notification policy, configurable weekly email digest, and gated optional AI overview were approved on 2026-08-25.

## Decisions

### Domain separation

- Tasks are not Review items. Staged placement is not Review unless the intake pipeline produces a typed ambiguity/conflict exception. Routine processing is neither Review nor Notification.
- A deadline remains a deadline, a mention remains a mention, and a processing failure remains a processing run. My Work and Today return typed references to them rather than copying them into tasks.
- An item may generate Activity, appear in My Work/Today, and create a Notification, but each representation references the authoritative source and has its own explicit state.
- Domain commands write authoritative state plus an Activity event and required outbox event atomically. Projectors consume outbox events idempotently; pages never infer notifications by polling Activity.
- Use stable typed source locators from the architecture portfolio for every Activity event, Review item, Notification, and read-model result.

### Activity event model

- Replace free-form `activity_logs` with append-only `activity_events`. Updates and generic log deletion are forbidden; undo/reversal is a new domain command and compensating event.
- Seed an `activity_event_definitions` registry keyed by event type and version. It defines category, allowed subject type, safe metadata schema, default visibility, and renderer. Producers cannot invent event names or arbitrary client-visible metadata.
- Each event stores organisation; optional client/matter lineage; actor kind (`user`, `system`, `integration`); actor ID where applicable; safe actor and subject label snapshots; event type/version; human summary snapshot; structured metadata; target locator; correlation/causation/idempotency IDs; and occurrence/record timestamps.
- Actor and subject snapshots make history renderable after rename, member removal, Trash, or purge. They must not include unnecessary email addresses, raw document text, credentials, signed URLs, embeddings, or provider payloads.
- Material business events enter Activity: record creation/update/reclassification/trash/restore, assignment, task transitions, Review decisions, verified deadline changes, note/mention events, relationship decisions, processing completion/failure, and configuration/security changes.
- High-frequency internal stages, retries, query telemetry, UI views, and routine background heartbeats remain operational telemetry rather than Activity.
- Matter Activity and organisation Activity use the same rows. Matter filtering uses stored lineage, never live entity reconstruction.
- The event is immutable even if its target later becomes inaccessible. Rendering follows current access: show its safe tombstone/context or suppress restricted details without changing the event.

### Tasks

- Introduce first-class `tasks`; remove action-item state from note messages after migration.
- A task has organisation lineage, optional client/matter/document context, concise title, optional description, creator, one active assignee, priority (`low`, `normal`, `high`, `urgent`), status (`open`, `in_progress`, `completed`, `cancelled`, `suspended`), optional date/time due contract, origin locator, and audit timestamps.
- A note message may create/link a task, but editing or deleting the message does not silently delete the task. The task retains an origin snapshot and authorised link to the message/version.
- Initial tasks have one assignee. Multi-assignee tasks, subtasks, recurrence, dependencies, private personal tasks, time tracking, and external-client assignment are out of scope.
- Owner/Admin and Associate may create tasks and assign them to active operational members. Viewer is read-only and cannot be a task or Review assignee in the first release.
- Reassignment, due-date change, priority change, completion, cancellation, reopening, and suspension are domain transitions with optimistic concurrency and Activity.
- Removing a member unassigns their open tasks in one audited operation and surfaces urgent/unassigned work to Owner/Admin. It never deletes or marks tasks complete.
- Task completion does not notify the whole matter. Assignment/reassignment creates a direct notification; completion is visible through Activity unless a later explicit watcher policy is approved.
- Task dates follow organisation timezone. A date-only task remains date-only; an optional time is interpreted and displayed with its stored timezone rather than silently becoming UTC midnight.

### Review items and decisions

- Add normalized `review_items`, `review_item_evidence`, and append-only `review_item_decisions`.
- Initial Review types are extraction invalid/conflict, possible duplicate, ambiguous placement, inferred/conflicting relationship, deadline verification, financial verification, Case Brief contradiction/proposed change, import validation exception, restore conflict, and supported processing recovery decisions.
- Staged documents waiting for an ordinary user assignment remain in Document Hub. Note tasks remain in My Work. They never appear in Review merely because they are unfinished.
- Each Review item contains one decision boundary, reason code, impact statement, source and subject locators, client/matter/document lineage, priority, age, state, assignee, evidence, allowed actions, dedupe key, and source version/revision.
- Group related extraction candidates into one coherent document Review item where one decision flow can resolve them. Do not create a queue row for every harmless AI field.
- State is `open`, `in_progress`, `resolved`, `dismissed`, `superseded`, or `suspended`. `Dismiss` exists only for Review types whose policy permits no-action resolution and always records a reason; it is not a generic hide button.
- Every type has a typed decision schema and owning resolver. A generic Review endpoint cannot apply arbitrary JSON changes to domain tables.
- Claim and resolution use a row revision/optimistic lock. Before applying a decision, revalidate current source version, tenant access, Trash state, and conflict facts. Stale items become superseded or return refreshed evidence instead of applying an outdated choice.
- Resolution atomically applies the domain command, appends the decision and Activity, closes/supersedes related items, and emits only the required notifications.
- Identical low-risk Review decisions may support evidence-preserving bulk resolution. Deadline, financial, restore, destructive, or mixed-impact decisions remain individual.

### My Work

- `/my-work` is personal responsibility, not an organisation backlog. It projects open/in-progress tasks and Review assigned to the current user, verified assigned deadlines, provisional urgent deadlines awaiting that user's verification, unread mentions, and failures explicitly assigned to that user.
- Unassigned Review and tasks appear only in authorised organisation queues and an Admin/Owner attention projection, not in every member's My Work.
- Group default results into Overdue, Today, Next 7 days, Later, and No due date. Within a group use consequence/priority, then due time/date, then age; do not use AI relevance.
- Filters support work type, client, matter, priority, due window, status, and origin. Default is `Assigned to me`; `Created by me` is separate. State is URL-addressable and server-paginated.
- My Work actions are type-specific. Completing a task, opening a Review decision, viewing a deadline, or opening a mention use the source domain's command/route rather than a generic complete button.
- Opening a mention marks it seen but does not invent task completion. Mentions may remain available in recent history after being seen.

### Notification policy

- Notifications are addressed personal interruptions. The initial allowlist is direct note mentions; task assignment/reassignment; Review assignment/escalation; approaching or overdue verified deadlines assigned/subscribed to the user; organisation invitations and material security/access changes; processing failures requiring that user's action; and urgent storage/operational risk directed to authorised administrators.
- Do not notify for ordinary upload completion, successful extraction, document processed/ready, staged intake ready, routine relationship creation, Case Brief refresh, generic Activity, or another person's normal task completion.
- Create `notification_intents` from domain/outbox events, then fan out idempotently into personal `notifications` and channel `notification_deliveries`. A deterministic dedupe key prevents repeated retries or schedulers from producing duplicates.
- `notifications` stores recipient, event family, reason, concise title/body snapshot, source event, target locator, action label, unread/read/archive timestamps, dedupe key, and creation/expiry data. Replace `is_read` with `read_at`; archiving is separate from reading.
- Every notification has a valid authorised target and one clear action. If the target enters Trash, the link opens its approved read-only Trash route. If access is revoked, the notification becomes non-disclosing and cannot leak identity through counts or text.
- Direct-accountability in-app notifications cannot be disabled: direct mention, task/Review assignment, verified assigned deadline, invitation/security event, and assigned failure. Email and non-direct subscriptions remain configurable.
- Notification delivery is independent of source success. Email failure never rolls back task assignment or Review resolution; it is retried with safe operational status.
- Default notification centre views are Action required, Unread, All, and Archived. Remove the current generic System category.
- Reading a notification is not resolving its task, Review item, deadline, or failure. Resolution may automatically archive the notification through a source-state event.
- Keep archived/personal delivery rows for 180 days initially, then purge them without deleting Activity or the source record. Security-retention requirements may override this later.

### Preferences and delivery

- Replace boolean email columns with per-event-family preferences for in-app and email, delivery mode (`immediate`, `weekly_email_digest`, `off` where allowed), verified-deadline lead times, quiet hours, timezone, and email-digest schedule.
- Optional email families and the weekly digest default to `off` for new users and require explicit opt-in. Mandatory access/security delivery is not exposed as an optional toggle and cannot be disabled.
- Initial configurable email families are mentions, task assignments, Review assignments, verified deadline reminders, and assigned failures. Invitation/security delivery follows its mandatory access policy and is not presented as an optional toggle. Routine processing has no preference because it is not a notification.
- Deadline offsets support a validated set such as 30, 14, 7, 3, and 1 day plus due/overdue policy. Deduplicate by deadline, recipient, effective due date, and offset. Correcting a deadline cancels stale scheduled deliveries and creates new ones only after verification.
- Quiet hours defer ordinary immediate deliveries until the next allowed time. Security events, invitations nearing expiry, and verified deadlines within 24 hours may bypass quiet hours under explicit policy.
- A **weekly email digest** is a configurable bundled email of eligible non-urgent notifications and work that would otherwise arrive separately. Each user can turn it off, choose the included families, weekday, local send time, and timezone. Organisation settings may provide defaults but cannot force non-mandatory email on a user.
- The deterministic core groups existing items by family and links to Today, My Work, Review, or the exact source. It includes assigned/open work, verified upcoming deadlines, mentions, Review assignments, failures requiring action, and a restrained activity summary; it never invents facts or copies sensitive legal content into email.
- Urgent verified deadlines, direct security/access events, and other explicitly immediate families do not wait for the weekly digest even when the digest is enabled.
- The weekly digest omits resolved, trashed, revoked, or inaccessible items at send time. It is a delivery preference only and does not appear as a separate Today/Dashboard card; Today already provides the live in-app view of current work.
- An optional **AI-written weekly overview** is deferred behind a separate evaluation flag. If later enabled, it may only turn the digest's already-authorised structured facts into a short narrative such as what changed and what needs attention next week. It cannot read raw PDFs or full notes for this purpose, calculate deadlines, provide legal advice, add new claims, or alter ranking.
- Every AI-written sentence must be traceable to one or more deterministic digest items, the section is visibly labelled `AI-written overview`, and the email still sends its deterministic core when generation fails. The feature is opt-in, records model/prompt/usage, respects recipient access at send time, and ships only after factuality, citation, privacy, cost, and prompt-injection evaluation passes.
- Email bodies contain minimal tenant context and no PDF contents, extracted quotations, full note bodies, credentials, or signed links. Application routes perform authentication.

### Today command centre

- Make `/today` canonical and redirect legacy `/dashboard` URLs. Navigation label is Today.
- Today is personal and action-first. Remove client/matter/document count cards and the dashboard-owned search implementation; Search remains a shell capability with its dedicated workspace.
- Use deterministic groups rather than a hidden numeric score: Needs action now, Due today, Coming up during the next seven days, Resume, and a five-event Recent activity preview.
- Needs action includes overdue verified deadlines/tasks, urgent assigned Review, and assigned failures. Coming up is grouped by date.
- Overdue deadlines are always included; the current future-only query behavior is removed. Provisional deadlines are clearly labelled and appear only when the user must verify them.
- Owner/Admin may see a compact Team attention section for unassigned urgent Review, unassigned urgent tasks, and systemic failures. Do not add portfolio totals or vanity metrics.
- Use actual source state to derive the first-use checklist: organisation profile, first client, first matter, first upload, and team invitation where authorised. Do not store completion flags that can drift.
- Track per-user recent resource views with tenant-scoped rows, bounded history, and explicit access/Trash filters. Viewing Activity or a list page does not overwrite substantive resume context.
- Keep a restrained greeting/date if useful, but no motivational quotes, decorative illustrations, generated summaries, or theatrical motion.

### Workspace interaction contracts

- **Today:** one principal scroller below stable identity/actions. Each urgency group has a bounded preview and clear route to My Work or Review; live updates do not reorder an item under the pointer.
- **My Work:** dense grouped list/table on desktop with server filters and prioritized drill-down list on mobile. Type and urgency remain understandable without colour.
- **Review:** desktop list/detail workspace with stable queue filters and evidence/decision pane; mobile uses list-to-detail navigation with preserved list position. Every row states why, impact, age, owner, evidence availability, and one primary decision.
- **Activity:** dense chronological feed grouped by Today, Yesterday, and calendar date. Server filters cover actor, category/event, client, matter, entity, source, and date range; URL state is shareable. Matter Activity reuses the same renderer.
- **Notifications:** stable chronological list. Newly received items show a `New notifications` affordance instead of shifting the scrolled list. Each row explains why the user received it and exposes its action.
- All pages use Civic Ink shared components and stable workspace chrome. Desktop and mobile define one deliberate scroll owner and retain full capability.

### Permissions and lifecycle integration

- RLS and domain commands derive organisation/user scope from authenticated identity. Caller-supplied assignee, subject, event, and locator IDs are revalidated against membership and resource access.
- Viewer can read permitted Activity and receive informational mentions/deadline notifications, but cannot create/complete tasks, be assigned actionable tasks/Review, or resolve Review.
- Associate can manage operational tasks and resolve permitted extraction, relationship, placement, and deadline Review. Owner/Admin has organisation triage, reassignment, configuration, and privileged decision capabilities. Financial/internal-cost and destructive permissions remain with their owning plans.
- Future matter-level access automatically limits Activity, My Work, Review, notifications, counts, and locators. No projection reveals inaccessible existence or counts.
- Trash suspends dependent tasks/Review/reminders and removes them from active Today/My Work. Restore re-evaluates relevance; it does not send accumulated notifications or reopen stale decisions blindly.
- Member removal archives their personal notifications, preserves Activity actor snapshots, unassigns open work, and triggers Admin/Owner attention for urgent orphaned responsibilities.

## Implementation Plan

1. **Freeze catalogues.** Inventory every current activity action, notification type, review reason, note action item, deadline reminder, processing failure, and dashboard query. Map each to Activity, Task, Review, Notification, inline status, operational telemetry, or removal.
2. **Add event foundations.** Create Activity definitions/events and transactional outbox/projector contracts with RLS, append-only enforcement, metadata schemas, snapshots, locators, idempotency, correlation, and Trash/purge behavior.
3. **Introduce Tasks.** Add task tables/state transitions, commands, assignment validation, due semantics, origin links, Activity/outbox emission, member-removal handling, and note-task migration adapters.
4. **Introduce Review.** Add items/evidence/decisions, typed resolvers, dedupe/revision logic, transitions, and producers for AI, duplicates, placement, relationships, deadlines, financials, Case Brief, import, restore, and recovery.
5. **Rebuild notification generation/delivery.** Add intents, personal notifications, channel deliveries, preferences, schedules, quiet hours, digests, retry/dedupe, target validation, read/archive state, and retention. Stop routine-processing producers.
6. **Create secured read models.** Implement RLS-safe RPCs/views for My Work, Today, queue/badge counts, overdue/upcoming work, Admin attention, recent views, and Activity filters. Derive scope from `auth.uid()` and paginate server-side.
7. **Build Activity surfaces.** Add `/activity`, matter Activity, shared rows/details, stable snapshots, typed changes, filters, deep links, and Trash-aware rendering.
8. **Build My Work and Review.** Replace Review's four-table query, move note action items to My Work, keep ordinary staged placement in Document Hub, and implement desktop/mobile list-detail workflows.
9. **Build Notifications and preferences.** Replace broken routing/System tabs, add action/reason/read/archive states, realtime insertion without scroll jumps, and Settings controls.
10. **Replace Dashboard with Today.** Add `/today`, deterministic urgency groups, overdue handling, recent views, first-use state, Admin attention, and Activity preview; redirect `/dashboard` and remove its local search/stat/activity implementations.
11. **Migrate legacy data additively.** Backfill Activity snapshots, convert note action items to tasks, convert actual document/link exceptions to Review, keep staged placement in Intake, migrate eligible notifications, and explicitly archive/remove routine or unresolvable notification rows.
12. **Cut over producers/consumers.** Audit every Server Action/worker for exact-once approved events. Shadow counts, switch navigation/badges/pages, stop dual writes, then remove legacy logs, note task columns, notification enums/preferences, and page-specific aggregate queries in rollback-bounded migrations.

## Interfaces and Data Changes

### Core tables

- `activity_event_definitions`: event type/version, category, subject contract, visibility, metadata schema/version, renderer key, and lifecycle.
- `activity_events`: organisation/client/matter lineage, actor kind/ID/snapshot, event type/version, subject/label snapshot, summary, safe metadata, target locator, correlation/causation/idempotency IDs, and timestamps.
- `tasks`: organisation lineage, context locators, title/description, creator/assignee, priority/status, due date/time/timezone, origin locator, revision, transition data, and timestamps.
- `review_items`: organisation lineage, type/reason, subject/source locators and versions, impact, priority/state, assignee, dedupe key, revision, escalation and lifecycle timestamps.
- `review_item_evidence`: review item, typed evidence locator, label, excerpt/structured facts, ordering, and access state.
- `review_item_decisions`: review item/revision, validated decision type/payload, actor/reason, result locator, and timestamp; append-only.
- `notification_intents`: source event, family, recipients/subscribers, reason, target, dedupe key, scheduling, and projection state.
- `notifications`: recipient, family, reason/title/body snapshots, source event, target/action, read/archive timestamps, dedupe key, expiry, and created time.
- `notification_deliveries`: notification/recipient/channel, state, provider reference, attempts, scheduling/sent/failure timestamps, and safe error.
- `notification_preferences`: user/organisation/family/channel, delivery mode, deadline offsets, quiet hours/timezone, weekly-digest families/day/time, optional evaluated AI-overview opt-in, and timestamps.
- `recent_resource_views`: user/organisation, typed accessible resource locator, last-viewed time, and bounded ranking metadata; no content snapshot.

### Read-model result

```ts
type WorkItem = {
  kind: 'task' | 'review' | 'deadline' | 'mention' | 'failure'
  sourceId: string
  orgId: string
  clientId?: string
  matterId?: string
  title: string
  context: string
  priority: 'low' | 'normal' | 'high' | 'urgent'
  dueOn?: string
  dueAt?: string
  verification?: 'verified' | 'provisional'
  target: SourceLocator
  primaryAction: { label: string; commandOrRoute: string }
}
```

`commandOrRoute` is a typed server-owned action key or application route identifier, never a caller-provided URL or executable command.

### State machines

```ts
type TaskStatus = 'open' | 'in_progress' | 'completed' | 'cancelled' | 'suspended'

type ReviewStatus =
  | 'open'
  | 'in_progress'
  | 'resolved'
  | 'dismissed'
  | 'superseded'
  | 'suspended'

type DeliveryStatus = 'pending' | 'sent' | 'failed' | 'suppressed' | 'cancelled'
```

Read/archive timestamps define notification state; do not add another ambiguous notification status enum.

## Testing and Acceptance Criteria

- Every material mutation emits exactly one allowed Activity event with stable snapshots, correct lineage/locator, safe metadata, and idempotency. Retries do not duplicate it.
- Historical Activity renders after rename, member removal, Trash, restore, source replacement, and purge without live administrator user enumeration or raw UUID descriptions.
- Legacy note action items migrate one-to-one to Tasks with assignee, due date, completion state, origin, and legacy provenance. Note edits/deletion do not silently mutate the task.
- Tasks, ordinary staged placement, and routine processing never appear in Review. Every Review item identifies a current decision, evidence, impact, assignee/state, and valid typed resolver.
- Concurrent Review claim/resolution and stale-version tests prevent double resolution or outdated writes. Dismiss is unavailable when an explicit decision is required.
- Clean AI extraction creates no gratuitous Review rows; risk-based exceptions bundle related fields under the AI plan.
- Routine upload, processing, Case Brief, and link events create no personal notification. Eligible events create one deduplicated notification per intended recipient with a valid authorised target and reason.
- Read, archive, source resolution, and task/review/deadline completion remain distinct. Source resolution can archive related notifications without corrupting Activity.
- Preferences, weekly schedule/timezone, included families, deadline corrections, lead-time dedupe, quiet hours, digest filtering, email retry/failure, revoked access, member removal, and Trash suspension behave deterministically.
- The optional AI overview cannot add a fact absent from the deterministic digest fixture, exposes source traceability, is clearly labelled, fails open to the deterministic email, records AI usage, and remains disabled until its separate evaluation gate passes.
- Viewer cannot be assigned actionable Tasks/Review or invoke mutations; Associate/Admin/Owner capabilities hold through UI, RPCs, direct IDs, and cross-tenant attempts.
- Today includes overdue verified deadlines/tasks, uses the approved deterministic groups, excludes vanity totals and routine processing, and filters inaccessible/trashed items.
- My Work, Review, notification badges/pages, and Today show consistent counts from the same secured source state. Queries are server-paginated and never derive totals from capped client arrays.
- Activity filters/URLs work at organisation and matter scope. Realtime preserves focus/list position and offers a new-items affordance.
- Backfill reports source/migrated/excluded/unresolvable counts and conflicts. Cutover waits until every legacy row has an explicit disposition.
- At 10,000 Activity events and 1,000 active work items, target p95 under 500 ms for Today/My Work counts and first page, excluding cold infrastructure start.
- Desktop/mobile acceptance covers stable chrome, scroll ownership, list-detail navigation, back-position preservation, keyboard/screen reader, 44px targets, light/dark, reduced motion, 200% zoom, long labels, loading/empty/error/partial states, and no page-level horizontal overflow.

## Assumptions

- One organisation per normal user remains the initial tenancy rule.
- Matter access is organisation-wide today, but contracts support future matter-level permissions.
- Deadlines, Notes mentions, Case Brief suggestions, financial verification, and processing runs will expose the source/version/state hooks required here in their owning plans.
- In-app notifications ship independently of an email provider. Email uses a replaceable adapter and is enabled only after retry/privacy tests pass.
- Deterministic rules are sufficient for Today prioritisation. AI-generated prioritisation and summaries are out of scope.

## Open Questions

None.
