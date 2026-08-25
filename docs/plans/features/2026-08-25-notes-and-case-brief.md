---
title: Matter Notes and Cited Case Brief
status: proposed
created: 2026-08-25
updated: 2026-08-25
owners:
  - product
  - engineering
related:
  - ./2026-08-25-matter-workspace-and-procedural-timeline.md
  - ./2026-08-25-document-hub-ingestion-and-workbench.md
  - ./2026-08-25-work-review-activity-notifications.md
  - ./2026-08-24-universal-search-and-evidence-retrieval.md
  - ../platform/2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md
---

# Matter Notes and Cited Case Brief

## Summary

Replace the current card-and-modal Notes implementation with a matter-scoped professional discussion workspace, and replace CaseWiki with a cited, block-based **Case Brief**. Notes support threads, chronological messages, same-organisation mentions, exact document quotations, and links to first-class tasks. Case Brief provides a concise current orientation to the matter, with evidence-backed claims, protected human edits, incremental refresh, and review-by-exception.

The two features share evidence locators, provenance, activity, search, permissions, and selective realtime delivery, but they remain distinct products: Notes records human collaboration; Case Brief is a curated reading layer over verified matter facts and proceeding evidence. The implementation reference is `/dev/notes-case-brief-concept`; it demonstrates interaction and information architecture, not production fixtures or a feature-local design system.

## Context and Goals

The current `case_notes` record combines message content, document attachment, reply shape, personal pinning, and task fields. Global Notes and Matter Notes duplicate interaction logic, mentions do not exist, and document quotations contain only text and a page number. A quote cannot reliably reopen the exact immutable PDF version or a highlighted region on a scanned page.

The current CaseWiki stores three broad JSON/Markdown sections. Regeneration reads document metadata and can preserve a whole manually edited section, but it cannot cite exact source pages, preserve human-authored spans, update only affected blocks, show a trustworthy history, or distinguish a safe refresh from a contradiction requiring review. Periodic full regeneration would spend tokens without guaranteeing user value.

This plan serves lawyers, associates, reviewers, and organisation administrators working inside a Matter. Success means:

- a user can discuss a matter without leaving it, mention an authorised teammate, quote exact evidence, and create or link a task;
- a quote always routes to the immutable document version and PDF page, with text or scanned-region highlighting when available;
- unread state is personal, durable, and accurate across Matter Notes and the organisation Notes projection;
- the Case Brief lets a reader understand current posture, disputed issues, positions/findings, turning points, and unresolved questions without reading every document;
- every material generated claim identifies its evidence, and absence of evidence is never presented as certainty;
- human-authored content is never silently overwritten by AI refresh;
- Case Brief generation is demand- and change-driven rather than scheduled token consumption;
- desktop and mobile retain the same capability with explicit, non-nested scrolling.

Out of scope are general chat rooms, direct messages, typing indicators, emoji reactions, simultaneous rich-text co-editing, voice/video, AI-generated legal advice, arbitrary Case Brief section templates, and using Notes as the canonical task/deadline store.

## Decisions

### Product boundaries

- **Notes** is the durable human collaboration record for a Matter. It is not an instant-messaging clone and does not use alternating chat bubbles.
- **Organisation Notes** is a filtered projection of the same matter threads and messages. It does not own a second notes model or separate authoring logic.
- **Case Brief** replaces the user-facing CaseWiki name. It is a cited orientation layer, not a longer Timeline, a document summary dump, or an automatically generated legal opinion.
- Timeline owns procedural sequence and relationships. Case Brief explains current meaning and open questions. Notes records human discussion. Activity records durable system/user events. Tasks own actionable work.
- Notes do not automatically become Case Brief facts. A human may promote a note excerpt into a proposed Brief change, which still requires provenance and the normal Brief review rules.

### Notes information architecture

- A Matter has zero or more note threads. A thread has a short title, category, participants derived from visible messages/mentions, optional primary document context, creation/archival state, and timestamps.
- Initial categories are `strategy`, `client_instruction`, `research`, and `general`. Categories are filters, not separate authorization boundaries.
- Messages are displayed chronologically in a left-aligned professional feed. A message may reference one earlier message, but deeply nested reply trees are not introduced.
- Desktop uses a thread list, active discussion, and an on-demand source/context pane. Each pane owns its vertical scroll; headers and composer do not scroll with the message body.
- Mobile uses one principal scroller. The user moves from thread list to a full conversation with a visible Back action; the thread identity and composer remain fixed outside the message scroller.
- The Matter section strip follows the Matter Workspace plan. Notes content starts immediately below the compact strip; no large explanatory hero is used.
- Thread search covers thread title, message body, mentioned members, linked document title/reference, and linked task title within the current permission scope.
- Personal pinning/muting is stored per member. A global `is_pinned` on the note is not reused because one member's preference must not reorder everyone else's workspace.
- Thread archive removes a thread from the default list but preserves messages, activity, search policy, and links. It is reversible by an authorized user.

### Message authoring and lifecycle

- The composer supports minimal structured rich text, `@` mentions, exact document quotations, file/document links, and task creation/linking. It always has a visible **Send** action.
- `Enter` inserts a newline. `Cmd+Enter`/`Ctrl+Enter` sends. Keyboard shortcuts are displayed in composer help and do not replace visible controls.
- Same-organisation active members who can access the Matter are the only mention candidates. The server revalidates membership, Matter access, and active state at send time.
- A mention is a persisted relationship, not text parsing at notification time. Editing a message creates notification intent only for newly added valid mentions; removing a mention does not retract an already delivered notification.
- Mention email delivery follows the recipient's notification settings and the Work/Review/Notifications plan. In-app unread state does not depend on email delivery.
- Message edits append immutable versions and show an `Edited` marker. The author may edit their own message; an Admin/Owner may moderate it with a required reason. Original versions remain audit-visible to authorized roles.
- Message deletion is a soft tombstone that retains author/time and says the message was removed. It does not delete replies, source quotes, tasks, or Activity history. Admin moderation records actor and reason.
- Creating a task from Notes calls the first-class task domain. The message stores a link to the task; changing or deleting the message does not delete the task.
- Viewer is read-only. Associate and above may create threads/messages, edit/delete their own messages, and mention accessible teammates. Admin/Owner may archive threads and moderate. Trashed Matters and all descendants are fully read-only.

### Exact document quotations

- `note_document_quotes` stores a typed `DocumentSourceLocator`, not only copied quote text. It identifies `document_id`, immutable `document_version_id`, one-based PDF page number, and one or more page-coordinate regions when available.
- A text-native PDF stores normalized quoted text, text offsets where the extraction contract supports them, and page-coordinate regions. A scanned PDF stores OCR text plus the page region. If OCR confidence is inadequate, the user may draw a region and add a manual excerpt clearly marked as manually transcribed.
- The copied excerpt is preserved for history and search, but the locator is authoritative for reopening evidence.
- Clicking a quote opens the shared Document Workbench at the exact PDF version and actual PDF page number, highlights all stored regions, and reveals the Notes context. It never resolves to “latest version” silently.
- If the immutable asset is temporarily unavailable, the note still shows its preserved excerpt and an explicit source-unavailable state. Purge dependency checks account for surviving quote references according to the Trash plan.
- A quotation may reference a proceeding document or a supporting file that the user is authorized to read. Reclassification does not break the locator.

### Unread and realtime behavior

- Personal `note_read_cursors` track the highest observed message sequence per thread. Aggregate unread counts on the Notes tab and Organisation Notes are projections from these cursors.
- A thread is marked read only after the active message viewport has observed the newest message, not merely when the route loads in the background.
- Opening a thread with unread messages places a durable `N new notes` divider before the first unread message and offers jump-to-first-unread behavior for long threads.
- Private Matter Broadcast delivers invalidation/events only while Matter Notes is active. It has no typing, presence, or generic `New` tags.
- Realtime is non-authoritative. On connection loss, the UI retains loaded data and shows quiet freshness text such as `Updated 12 min ago`; it does not poll and does not add an in-screen refresh action. Normal browser/tab refresh retrieves current state.
- Reconnect triggers one bounded reconciliation fetch from the last durable message sequence. Duplicate deliveries are ignored by message/event ID.

### Case Brief purpose and sections

- A Brief is first generated when an authorized user requests **Create Case Brief**. Matters without a Brief show a useful empty state explaining its cited orientation purpose; they do not incur scheduled generation.
- Default section order is:
  1. **Current posture** — present procedural position, operative outcome, and immediate next milestone.
  2. **Issues in dispute** — questions that remain contested, with status and evidence.
  3. **Positions and findings** — material party positions, authority findings, and conflicts.
  4. **Key turning points** — a small set of developments that changed exposure or strategy; this is explanatory, not a full chronology.
  5. **Open questions** — unresolved evidence conflicts, missing material, and uncertainties. It does not invent deadlines or tasks.
- Verified canonical deadlines and financial facts may appear in compact current-posture facts. Their owning domains remain Deadlines and Financials.
- Supporting files are not automatically treated as procedural truth. They contribute only when explicitly cited by a human or promoted into an evidence-backed proposal.
- Each section contains ordered structured blocks rather than one Markdown blob. Initial block types are paragraph, heading, list, factual callout, quotation, and change notice.

### Brief evidence, provenance, and human control

- Every material AI-authored claim has one or more `DocumentSourceLocator` citations or a typed link to a verified canonical fact with its evidence. Generated uncited claims are rejected before publication.
- Brief content uses a versioned rich-text AST with stable block and segment IDs. Each text segment records provenance: `ai`, `human`, or `accepted_ai_change`, plus actor/run and timestamp.
- Human editing uses a minimal rich-text editor: bold, italic, bulleted/numbered list, block quote, and citation insertion. Raw Markdown/HTML is not the normal authoring interface.
- Human-authored ranges receive a subtle non-color-only provenance treatment. Hover/focus reveals `Edited by <member> · <time>`. Full versions remain available in history.
- AI refresh never overwrites a human-authored segment. A contradictory source creates a proposed change adjacent to the protected text with evidence and an explanation. The user can accept, keep, or edit.
- Safe automatic refresh is limited to AI-managed blocks where all claims are cited, schema/grounding validation passes, no protected human segment is touched, and no conflict involves operative outcome, financial amount, deadline, party identity, or legal reference.
- Consequential, conflicting, low-confidence, or human-touching changes create a first-class Review item. Review acceptance writes a new Brief version and Activity event atomically.
- Brief version history records block diffs, actor or AI run, source set, prompt/model version, token usage, and the reason for refresh. Restore creates a new version; it does not erase later history.

### Incremental refresh and cost control

- After first generation, only material proceeding-document or verified canonical-fact events can request refresh. Note messages, routine Activity, and unchanged supporting files do not.
- Material triggers include a proceeding document becoming ready, a verified extraction correction, relationship/procedural classification change, verified deadline/financial change used by the Brief, or accepted Review decision.
- Triggers enter a durable outbox and coalesce per Matter over a short debounce window. The worker calculates source-set and section-input hashes, skips unchanged sections, and records a zero-generation no-op run.
- The worker first selects affected sections deterministically from changed facts/document classification. AI regenerates only those sections, with current protected segments and citations supplied as constraints.
- Every run has an idempotency key, status, attempts, input/source hashes, model/prompt/schema versions, token usage, cost metadata where available, validation result, and error code.
- Failed refresh preserves the last published Brief and shows a non-alarming stale/failed-refresh state to authorized editors. It never blanks the Brief.
- Organisation settings may disable automatic maintenance after the first Brief. Manual refresh obeys the same incremental, citation, protection, and Review rules; it is not a force-overwrite path.

### Brief presentation

- Desktop uses a compact outline, a readable article column, and an on-demand source/change pane. The article is the primary scroller; outline and source panes keep their own headers and may scroll independently.
- Mobile uses one article scroller. Outline opens as a menu/drawer and citations open a dismissible context surface before routing to the Workbench.
- The Brief toolbar compactly exposes `updated`, source count, refresh state, proposed-change count, history, and the permitted Edit/Refresh actions. It does not repeat the Matter title or add a hero banner.
- Inline citation markers are keyboard accessible and open source context. Source context states document, immutable version, page, excerpt, evidence status, and **Open PDF at highlighted text**.
- Each section shows its last successful refresh and source count without overwhelming normal reading.
- Empty, generating, partially cited/migrated, stale, refresh-failed, no-access, and read-only Trash states are designed explicitly.

### Activity, search, and notifications

- Thread creation/archive, message creation/edit/moderation, mention, Brief creation/refresh/review acceptance, and Brief human edit emit domain Activity events via the transactional outbox. Routine reads and cursor movement do not.
- Mentions create personal notification intent with a deep link to thread and message. A Case Brief proposal creates a Review item for its assignee, not a generic notification card.
- Search indexes authorized note messages and published Brief blocks. Note results route to the thread/message; Brief results route to the block and expose underlying source locators.
- Soft-deleted message bodies and superseded unpublished Brief proposals are excluded from ordinary search. Immutable versions remain available through privileged history/audit paths.

## Implementation Plan

### 1. Establish shared contracts

1. Adopt the shared `DocumentSourceLocator` from the Document Workbench plan, including immutable version, actual PDF page, region list, excerpt, and evidence status.
2. Reuse first-class `tasks`, Review, Activity/outbox, member permissions, and notification preferences. Do not add feature-local substitutes.
3. Define typed Notes and Case Brief domain commands and server-side authorization. Client components receive projections, not unrestricted table access.

### 2. Expand and migrate Notes data

1. Add thread, message, version, mention, quotation, thread-preference, and read-cursor tables with `org_id`, timestamps, constraints, and RLS.
2. Backfill each live legacy `case_notes` row into a thread/message. Use a deterministic grouping policy: root note and its replies become one thread; standalone notes become one thread. Preserve stable legacy IDs in migration mapping fields.
3. Convert legacy `document_id`, `quote`, and `page_number` to best-effort locators. Mark quotations `legacy_unresolved` until a document version/page region can be resolved; never fabricate coordinates.
4. Convert legacy note task fields into first-class tasks once the Work domain is available, retaining a message-task link and migration provenance.
5. Dual-read through one repository during verification, compare organisation/matter counts, then cut over. Remove legacy mutations only after rollback and parity checks pass.

### 3. Build the Notes domain and UI

1. Implement thread/message commands with immutable versions, moderation, mention-delta calculation, Activity/outbox writes, and idempotency.
2. Implement exact quotation creation through the Workbench selection/region tool and source-locator validation.
3. Build shared Notes workspace components used by Matter Notes and Organisation Notes: thread list, thread header, message feed, unread divider, composer, mention picker, linked-task card, quote card, and context pane.
4. Add personal cursors and selective Matter Notes Broadcast according to the Realtime plan.
5. Add search indexing and deep-link handling after message commits through durable outbox consumers.

### 4. Expand and migrate Case Brief data

1. Add Brief, section, block, segment/version, citation, refresh-run, proposal, and source-snapshot tables.
2. Backfill current `wiki_sections` into matching Brief sections. Treat the legacy body as one block, preserve `is_user_edited` as protected human provenance, retain `last_ai_content` only as migration/audit input, and mark uncited generated content `citation_pending`.
3. Publish migrated content with a visible partial-citation state; do not invent page references. A user or validated refresh may resolve citations section by section.
4. Keep legacy CaseWiki routes as temporary redirects to Matter Case Brief, then remove legacy writes after migration verification.

### 5. Implement Brief generation and refresh

1. Implement on-demand initial generation from proceeding documents, verified effective metadata, canonical facts, and exact source locators.
2. Add grounding validation that rejects missing, inaccessible, version-mismatched, or unsupported citations before publishing.
3. Implement durable trigger coalescing, affected-section selection, input hashing, idempotent runs, protected-segment constraints, and no-op detection.
4. Implement risk classification: publish safe AI-only block updates; route consequential/conflicting/human-touching diffs into Review.
5. Store usage telemetry for initial and incremental runs and expose aggregate use only to authorized administration surfaces.

### 6. Build Case Brief UI and integrations

1. Build the compact outline/article/source-pane desktop layout and single-scroller mobile adaptation shown by the concept.
2. Implement minimal rich-text section editing, citation insertion, provenance marks, history, proposed-change comparison, and accessible source opening.
3. Add Search indexing, Activity events, Review routing, read-only Trash behavior, and document purge dependency handling.
4. Remove the user-facing CaseWiki label after redirect and migration monitoring complete.

### 7. Cut-over and observe

1. Roll out per organisation/matter behind flags: Notes read projection, Notes writes, Brief read projection, Brief generation, automatic maintenance.
2. Monitor migration parity, message command errors, Broadcast channel usage, cursor lag, mention delivery, citation-open success, Brief no-op ratio, validation rejection, proposal rate, token usage, and refresh latency.
3. Contract old tables/fields only after the observation window, rollback window, and data-retention requirements are satisfied.

## Interfaces and Data Changes

### Notes tables

- `note_threads`: `id`, `org_id`, `matter_id`, `title`, `category`, optional `primary_document_id`, `created_by`, `archived_at/by`, timestamps, sequence metadata.
- `note_messages`: `id`, `org_id`, `thread_id`, `author_id`, optional `reply_to_message_id`, current structured body, monotonic thread sequence, `edited_at`, tombstone/moderation fields, timestamps.
- `note_message_versions`: immutable body, editor/AI actor, edit reason/type, created timestamp.
- `note_mentions`: message, mentioned member/user, creator, created timestamp; unique per message/member.
- `note_document_quotes`: message, source locator fields, copied excerpt, OCR/manual-transcription status, confidence, created timestamp.
- `note_message_tasks`: message/task relationship; task lifecycle remains outside Notes.
- `note_thread_preferences`: member/thread pin, mute, archive-display preferences.
- `note_read_cursors`: member/thread, highest observed sequence, observed timestamp.

### Case Brief tables

- `case_briefs`: one per Matter, publication state, last successful refresh, source/input hash, settings snapshot.
- `case_brief_sections`: stable section key, order, title, refresh/source metadata.
- `case_brief_blocks`: stable block identity, type, order, current version pointer, lifecycle state.
- `case_brief_block_versions`: structured content AST, actor/run, source hash, version reason, created timestamp.
- `case_brief_segment_provenance`: stable segment ID, provenance type, actor/run, protected state, timestamps.
- `case_brief_citations`: block/segment, typed source locator or canonical-fact locator, claim range, evidence status.
- `case_brief_refresh_runs`: durable run/attempt/model/prompt/schema/input/source/token/validation/error data.
- `case_brief_change_proposals`: target blocks/segments, before/after diff, risk reasons, review item, decision metadata.
- `case_brief_source_snapshots`: versioned source-set membership used by a generation/refresh run.

All tenant rows carry `org_id`; composite constraints or trusted functions enforce organisation consistency with Matter, Document, member, task, and Review parents. Indexes cover Matter/thread ordering, unread sequence queries, member mentions/preferences, active Brief order, pending proposals, and locator dependencies.

### Domain commands and queries

- `createNoteThread`, `postNoteMessage`, `editNoteMessage`, `removeNoteMessage`, `archiveNoteThread`, `markNoteThreadObserved`, `createDocumentQuote`, and `linkNoteTask`.
- `createCaseBrief`, `requestCaseBriefRefresh`, `editCaseBriefSection`, `reviewCaseBriefProposal`, `restoreCaseBriefVersion`, `getPublishedCaseBrief`, and `getCaseBriefSourceContext`.
- Commands return stable typed errors for unauthorized member, inaccessible Matter/document, invalid reply/thread, stale edit version, invalid mention, invalid locator, protected-segment conflict, unsupported citation, and idempotent duplicate.

### Events

- `note.thread_created`, `note.thread_archived`, `note.message_created`, `note.message_edited`, `note.message_removed`, `note.member_mentioned`.
- `case_brief.created`, `case_brief.refresh_requested`, `case_brief.refresh_completed`, `case_brief.refresh_failed`, `case_brief.proposal_created`, `case_brief.proposal_decided`, `case_brief.human_edited`.
- Broadcast payloads contain stable IDs, sequence/version, event type, and occurred time; they do not contain full legal text.

## Testing and Acceptance Criteria

### Automated coverage

- Schema and RLS tests prove cross-organisation thread/message/mention/quote/Brief/citation access is impossible and role permissions match this plan.
- Domain tests cover same-organisation/access revalidation, mention edit deltas, message version/tombstone behavior, thread sequencing, personal pins, and task independence.
- Source-locator tests cover text-native selection, multi-region quote, scanned-region quote, manual transcription label, immutable version routing, reclassification, unavailable asset, and purge dependency.
- Unread tests cover first open, viewport observation, multiple devices, out-of-order/duplicate Broadcast, reconnect reconciliation, deleted message, and Organisation Notes aggregate counts.
- Brief tests cover first generation, section selection, source hashing/no-op, coalesced triggers, idempotent retry, citation validation, protected human segment, consequential fact change, conflicting evidence, review acceptance/rejection, failure preservation, and version restore.
- Search tests prove only authorized published/live content is indexed and all result deep links resolve to the correct thread/message or Brief block/source.
- Migration tests compare legacy/live counts per organisation/matter, preserve human-edited CaseWiki content, never fabricate legacy citation coordinates, and support rollback before contract phase.
- Component/accessibility tests cover keyboard composer, mention picker, focus-visible citations, screen-reader provenance/change states, 44px mobile targets, long names/content, empty/loading/error/read-only states, and reduced motion.

### Manual acceptance

- On desktop, the Matter identity and section navigation remain fixed; thread list, message feed, and optional source pane scroll independently without page horizontal overflow.
- On mobile, the thread list opens a full conversation, Back restores the list, the message feed is the principal scroller, and composer/navigation do not cover the last message.
- Typing `@` shows only active accessible Matter teammates. Posting produces one persisted mention and one eligible notification intent; retry does not duplicate either.
- Selecting text in a text PDF or a region in a scanned PDF creates a note quote. Clicking it reopens the exact immutable PDF page with highlight and preserved context.
- The Case Brief explains current posture without duplicating the full Timeline. Every material generated claim has an operable citation.
- Editing a sentence as a human visibly records provenance. A later conflicting proceeding document produces a proposal and leaves that sentence unchanged until a decision.
- Adding unchanged source content causes a recorded no-op rather than a token-consuming section rewrite. Adding a material proceeding document refreshes only affected sections.
- Realtime loss does not remove content or start polling; the UI shows quiet freshness text. Reconnect reconciles without duplicates.
- In Trash, all Notes and Case Brief content remains readable and every mutation control is absent/disabled until root restoration.

Completion requires typecheck, lint for touched files, unit/integration/RLS/migration tests, responsive browser verification, keyboard/screen-reader review, and observability dashboards/alerts for the rollout metrics above.

## Assumptions

- The shared Workbench supplies immutable document versions, page rendering/OCR coordinates, and typed source locators before exact quotation cut-over.
- The Work/Review/Activity plan supplies first-class tasks, Review items, outbox, notification intent, and configurable mention email delivery.
- Initial rich-text storage uses a sanitized versioned JSON AST with a controlled renderer/editor; raw arbitrary HTML is never accepted.
- Case Brief auto-maintenance is opt-out per organisation after first creation and may remain feature-flagged during the pilot.
- One user may be a member of multiple organisations; cursors, preferences, mentions, and searches remain organisation-scoped.

## Open Questions

None.
