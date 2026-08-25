---
title: Selective Realtime Delivery, Freshness, and Unread State
status: proposed
created: 2026-08-25
updated: 2026-08-25
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ../features/2026-08-25-document-hub-ingestion-and-workbench.md
  - ../features/2026-08-25-work-review-activity-notifications.md
---

# Selective Realtime Delivery, Freshness, and Unread State

## Summary

Use Supabase Realtime only where immediate delivery materially improves collaboration, conflict avoidance, or visibility of active background work. Realtime is a lossy delivery hint over durable CaseChain state, never a source of truth, durable job queue, or substitute for an authoritative fetch. Replace broad Postgres Changes subscriptions with compact private Broadcast topics scoped to a user, matter, intake queue, or Review queue; disclose connection freshness honestly; perform no periodic polling; and use explicit per-user cursors for unread notes and mentions.

## Context and Goals

The current application has two Realtime consumers:

- `MatterTabs` opens one channel while the Matter page is mounted and attaches broad `postgres_changes` subscriptions for `documents`, `document_links`, `wiki_sections`, and `case_notes`. Document and relationship events are narrowed in the browser because the current filter path is unreliable locally, and relevant events trigger follow-up server reads.
- `InboxClientView` subscribes to all RLS-visible `staged_documents` changes, applies a partial payload, then fetches the authoritative joined queue and refreshes the route.

This makes tenant-visible table traffic, full-row payloads, per-subscriber Postgres Changes authorization, duplicate invalidation, and follow-up reads larger than the user experience requires. Neither consumer exposes a truthful connection/freshness state. The Matter page logs some subscription failures; the Document Hub does not report subscription state.

The intended outcome is:

- live delivery exists only on surfaces where latency changes a user's decision or preserves collaborative context;
- one browser tab multiplexes approved channels over one Supabase client/WebSocket and releases it when no live surface remains;
- every event is tenant- and aggregate-scoped, compact, versioned, non-sensitive, and authorised;
- disconnected pages remain fully usable without polling and clearly show when their data was last fetched;
- reconnecting never presents stale data as current;
- unread/new state is user-specific, durable, and semantically separate from record age, notifications, and workflow status;
- connection count, delivered events, payload bytes, joins/retries, refetches, and event-to-render latency are observable before rollout expands.

## Decisions

### Realtime is selective and non-authoritative

- Canonical rows, domain commands, transactional outbox events, activity events, and durable jobs remain authoritative. A Realtime message means only “this secured projection may have changed.”
- Realtime payloads do not contain document text, note bodies, extracted legal facts, client names, storage paths, credentials, or other sensitive content. They contain an event kind, secured aggregate/entity identifiers, revision, timestamp, and optional safe invalidation metadata.
- A client receiving an event fetches or patches only the affected secured projection. Domain mutation responses update the initiating user's UI immediately; they do not wait for the event to echo.
- Realtime loss, refusal, disconnect, duplicate delivery, and reordering cannot corrupt canonical state. Event handlers are idempotent and revision-aware.
- There is no periodic data polling fallback and no in-page refresh action. Navigation, browser reload, returning a hidden tab to the foreground, and successful reconnect may each perform a bounded authoritative fetch.

### Approved initial live surfaces

| Surface | Initial behavior | Reason |
| --- | --- | --- |
| Document Hub active queue | Live while the Hub is visible and an active/reviewable intake queue is present | Processing, failure, duplicate, and placement changes affect the user's immediate next action |
| Matter workspace | One compact matter-scoped channel while the workspace is visible | Documents, relationships, notes, and selected derived projections may change the flagship shared record |
| Matter Notes conversation | Note events are consumed from the matter topic while Notes is active; unread state remains durable when it is not active | Immediate message delivery has high collaboration value |
| Review queue | Live only while Review is open | Claim/resolution changes must prevent two users acting on stale work |
| Direct user attention | Defer a shell-wide channel in the controlled pilot; notification/My Work counts refresh on navigation, mutation, or manual refresh | Avoid keeping every ordinary app session connected merely for a badge |

Search results, collection tables, Today, My Work, Activity, Case Brief reading, Files, Deadlines, Financials, Details, Settings, Team, usage reports, and ordinary dashboards do not receive live subscriptions initially. Their domain mutations still create durable Activity/notification/work projections. A later surface must demonstrate a latency-sensitive user outcome and an acceptable connection/message budget before joining the allowlist.

Typing indicators, online presence, live cursors, and “who is viewing” are excluded initially. Chat-quality note delivery does not require Presence. These ephemeral features may be reconsidered only after real collaboration traffic and quota measurements justify them.

### Transport and topic contract

- Use Supabase private Broadcast from the database for the target design. Supabase Postgres Changes may remain only during a bounded migration window.
- Topic names are scoped and opaque to unrelated clients:
  - `org:{org_id}:matter:{matter_id}`
  - `org:{org_id}:intake`
  - `org:{org_id}:review`
  - `org:{org_id}:user:{user_id}` only when direct-attention Realtime is later enabled
- RLS on `realtime.messages` authorises joins through indexed membership/role checks and verifies matter/user lineage. Possessing or guessing a topic name never grants access.
- A database trigger or trusted transactional event adapter emits one compact invalidation only after the owning domain mutation succeeds. Avoid overlapping triggers that emit the same logical change more than once.
- The initial event envelope is:

```ts
type RealtimeInvalidationV1 = {
  version: 1
  eventId: string
  kind: string
  orgId: string
  aggregateType: 'matter' | 'intake' | 'review' | 'user'
  aggregateId: string
  entityType: string
  entityId: string
  revision: number | string
  occurredAt: string
}
```

- The event catalogue is allowlisted and versioned. Initial families are intake stage/placement/failure, document bound/reclassified/trashed/restored, relationship proposed/confirmed/rejected, note created/edited/deleted, Review claimed/resolved/superseded, and approved deadline/financial verification changes.
- Events invalidate named projections rather than send whole rows. Multiple events for the same projection inside a short render window are coalesced into one fetch. No handler calls both a data fetch and a full `router.refresh()` unless separate server-rendered state demonstrably requires both.
- Use one singleton browser Supabase client per tab. Channel lifecycle is owned by one shared connection manager so route components cannot create duplicate channels or reconnect loops.

### Connection lifecycle and resource conservation

- Join a channel only after an authenticated session is available. Remove it on route/scope unmount and when the last approved live surface no longer needs it.
- If the document has been hidden for five minutes, leave live channels and close the socket when no channel remains. On foreground return, fetch the active projection once, then reconnect if the visible route still qualifies.
- Visible high-value surfaces may remain connected while no application events are flowing; the connection still occupies one concurrent connection and sends small protocol heartbeats. It is not replicated across each channel in the same tab.
- Use the Supabase client's ordinary exponential reconnect for transient network/heartbeat loss. Do not add a second retry loop. Authentication, tenant-disabled, private-channel-policy, or quota refusal becomes a paused/manual state rather than an aggressive join loop.
- After any gap, a successful subscription performs one revision-aware reconciliation fetch before the UI returns to `Live`. A WebSocket subscription is not treated as replay or proof that no event was missed.
- Feature flags can disable all Realtime, one event family, or one surface without disabling canonical mutations.

### Truthful freshness UI

- `connecting`: compact neutral `Connecting…`; never claim the page is live.
- `live`: green dot plus `Live`. The dot may pulse subtly, and animation respects reduced-motion preference. Tooltip: `Live updates connected. Changes from other users and background processing appear automatically.`
- `reconnecting`: neutral `Reconnecting…`; retain the last successful fetch timestamp.
- `paused`: muted `Refreshed 12 min ago` calculated from the last successful authoritative fetch. Tooltip: `Live updates are unavailable. Reload this browser tab to check for changes.`
- `offline`: muted `Offline · Refreshed 12 min ago`.
- `Live` appears only after the required channel is subscribed and the reconciliation fetch has succeeded. A socket open without authorised channel delivery is not Live.
- Connection/freshness state belongs with workspace interpretation metadata, not beside or inside the primary action. In the Matter header it follows the matter metadata, for example `CGST · Pune | Live`.
- Freshness timestamps describe when this client last fetched authoritative data; they do not claim when the server was last modified.

### Notes, unread state, and “New” treatment

- “New” means unseen by the current user, not recently created globally. It requires durable per-user state and is not inferred from browser memory or a relative time window.
- Add `note_read_cursors` keyed by organisation, user, and conversation stream. The initial stream is a matter's Notes conversation; the schema can later support explicit threads. Store the greatest seen server ordering key (`created_at`, `id`) and `updated_at`. Cursor advancement is monotonic and tenant constrained.
- Server queries compute unread notes after the cursor, excluding notes authored by the current user, deleted/inaccessible notes, and rows outside the conversation. A direct mention separately creates an unread personal notification; reading the conversation may mark the mention seen but does not resolve a task or Review item.
- The Notes tab shows an unread count. Inside the conversation, use a single `N new notes` divider at the read boundary instead of adding a repetitive `New` chip to every message.
- If a note arrives while Notes is open, the window is focused, and the newest note is visible, append it without moving the user's context and advance the cursor after it is rendered. If the user is scrolled away, keep it unread and show a `N new notes` jump affordance.
- Opening Notes does not mark unseen content read before it is successfully loaded and presented. Edits use an `Edited` provenance marker; editing an old note does not make the note globally new.
- Do not add generic “New” tags to timeline documents, Files, Activity, or collection tables without an owning read/unread contract. Intake stage, Review state, notification unread state, and document lifecycle already communicate more precise meanings.

### Security, privacy, and failure behavior

- Topic policies enforce current tenant membership, role, resource access, Trash visibility, and direct-recipient identity. Revoked access prevents future joins and the next token refresh/reconciliation removes inaccessible state.
- A client never trusts `orgId`, `matterId`, event kind, or revision from a message as authorisation to fetch or mutate. All follow-up reads and commands reapply server/RLS checks.
- Payloads and logs use opaque IDs and safe codes. They do not contain note text, extracted metadata, filenames, client identity, or legal content.
- Duplicate, delayed, reordered, unknown-version, unauthorized, and stale-revision events are ignored or reconciled safely. Malformed events are counted without logging their raw payload.
- `too_many_connections`, `too_many_channels`, repeated join failures, and reconnect storms surface in operational metrics and place the UI in paused state.

### Quota and observability policy

- Track Supabase Realtime peak connections, messages, egress, Postgres/Broadcast events, payload size, joins, response errors, and lag. Add application metrics for channels per tab, reconnect attempts, coalesced events, projection refetches, and event-to-render latency.
- Establish pilot alerts at 50%, 70%, and 85% of the current plan's connection, message, and egress allowances. Crossing an alert does not silently remove a user's active channel; operators disable a surface/event family through feature flags if required.
- Review delivered-event value quarterly: events that commonly cause an unchanged fetch or no visible action are removed or narrowed.
- Load estimates multiply events by recipients and payload size. Database writes alone are never used as the message or egress estimate.

## Implementation Plan

1. Instrument the current Matter and Document Hub channels before migration: channel lifecycle, subscribed/error/timeout/closed state, delivered table/event family, follow-up fetches, and reconnects. Establish a short controlled-pilot baseline.
2. Add the shared Realtime connection manager, typed status model, last-successful-fetch clock, visibility lifecycle, bounded reconnect handling, and feature flags. Ensure all channels in one tab reuse the same browser client/socket.
3. Add private Broadcast topic authorisation policies and automated cross-tenant/topic-forgery tests. Keep event payloads non-sensitive and versioned.
4. Add database/trusted-event emitters for the allowlisted intake, matter, note, and Review invalidations. Guarantee one logical event per committed mutation and coalesce related projection refreshes.
5. Migrate Document Hub from broad `staged_documents` Postgres Changes to `org:{org_id}:intake`, remove full-row merging, and fetch only the changed queue item/projection.
6. Migrate the Matter workspace from four broad table subscriptions to `org:{org_id}:matter:{matter_id}`. Refresh only Timeline, Notes, counts, or the selected inspector projection named by the event.
7. Implement the truthful `Connecting`, `Live`, `Reconnecting`, `Refreshed … ago`, and `Offline` treatments with accessible tooltips, reduced motion, and the approved Matter-header placement. Do not add an in-page refresh control.
8. Add `note_read_cursors`, secured unread-count queries/commands, Notes-tab count, new-notes divider, jump affordance, and viewport/focus-aware cursor advancement. Integrate direct mentions with the canonical notification read model.
9. Add the Review live topic when the rebuilt Review queue is implemented. Keep other surfaces non-live until separately approved.
10. Run a bounded dual-observation period, comparing legacy and Broadcast invalidations without double-updating UI. Remove legacy Postgres Changes subscriptions only after event parity, RLS, disconnect/reconnect, and resource metrics pass.

## Interfaces and Data Changes

- New private Broadcast topic and RLS contract on `realtime.messages`.
- New `RealtimeInvalidationV1` envelope and allowlisted event catalogue.
- New browser connection manager API:

```ts
type RealtimeStatus = 'idle' | 'connecting' | 'reconciling' | 'live' | 'reconnecting' | 'paused' | 'offline'

type LiveProjectionState = {
  status: RealtimeStatus
  lastFetchedAt: string | null
  lastEventAt: string | null
  reconcile(): Promise<void>
}
```

- New `note_read_cursors` table with `org_id`, `user_id`, stream type/id, last-seen ordering key, and timestamps; unique by user and stream.
- New secured note unread-count query and monotonic mark-seen command.
- Existing broad `postgres_changes` subscriptions are removed after migration.

## Testing and Acceptance Criteria

- One tab with multiple approved channels uses one WebSocket; leaving the final channel closes it. Repeated route transitions do not accumulate channels.
- A hidden tab leaves channels after five minutes; foreground return performs one reconciliation fetch and returns to Live only after success.
- No timer periodically fetches Matter, Notes, Document Hub, or Review data when Realtime is unavailable.
- Cross-tenant users, revoked members, Viewers without resource access, guessed topics, and anonymous clients cannot join or infer event existence.
- Events contain no legal text, note body, filename, client identity, extracted metadata, storage path, or credential.
- An unrelated organisation or matter mutation creates no delivery or refetch for the current client.
- Duplicate, reordered, missing, and malformed events do not duplicate records or regress revisions. Reconnect after a missed event converges to authoritative state.
- Quota/auth refusal never shows Live, never starts a rapid retry loop, and exposes only the muted `Refreshed … ago` freshness state.
- Live is keyboard discoverable, has an accessible description, and its pulse stops with reduced motion.
- A new note increments only other eligible users' unread counts. The author's own note is read for the author. The divider and jump affordance preserve scroll position, and the cursor advances only after content is presented.
- Mentions remain addressable notification items; reading a note does not complete related tasks or Review work.
- Application and Supabase reports expose connection, message, egress, join/error, refetch, and event-to-render metrics. Pilot thresholds and feature-flag rollback are exercised.
- Legacy subscriptions are not removed until parity tests cover insert/update/delete, Trash/restore, processing, note, relationship, and Review events.

## Assumptions

- Supabase Realtime remains the initial delivery provider, but domain contracts do not depend on Supabase payload shapes.
- One normal user belongs to one organisation during the initial pilot.
- The transactional outbox/activity architecture remains the durable integration path; Realtime is an additional low-latency projection signal.
- The controlled pilot values predictable quota use over making every shell badge instantaneous.

## Open Questions

None.
