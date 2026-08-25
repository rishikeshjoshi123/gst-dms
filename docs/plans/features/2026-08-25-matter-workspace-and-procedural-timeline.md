---
title: Matter Workspace and Procedural Timeline
status: proposed
created: 2026-08-25
updated: 2026-08-25
owners:
  - product
  - engineering
related:
  - ../platform/2026-08-24-product-architecture-portfolio.md
  - ../platform/2026-08-24-document-record-and-file-lifecycle.md
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
  - ../platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md
  - ./2026-08-25-document-hub-ingestion-and-workbench.md
  - ./2026-08-25-work-review-activity-notifications.md
  - ./2026-08-24-universal-search-and-evidence-retrieval.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Matter Workspace and Procedural Timeline

## Summary

Rebuild the Matter page as CaseChain's flagship evidence workspace rather than a collection of unrelated tabs. Keep matter identity, status, scoped Search, freshness, navigation, and the current primary action in compact stable chrome; give each section one deliberate content region; and preserve deep-linkable state across Timeline, Files, Case Brief, Notes, Deadlines, Financials, Activity, and Details.

Make Timeline a left-to-right procedural map of active proceeding documents and effective, evidence-backed relationships. It is not a file browser, a raw citation network, or a chat feed. A dense chronology table provides an equally authoritative desktop reading mode, while phones and constrained tablets use a compact chronological list instead of shrinking the graph. Fixed-size nodes, a versioned relationship-label catalogue, conservative candidate review, a useful document inspector, and one shared Document Workbench replace the current decorative nodes, hover cards, unsafe link drawing, and page-specific PDF route.

Make Files the supporting-evidence library for the matter. It uses a compact desktop table and mobile drill-down list, searchable categories, explicit links to proceeding documents, honest content availability, the shared Workbench, and the classification/reclassification contracts already approved by the Document Lifecycle and Document Hub plans. Matter Activity reuses the canonical Activity stream, and Details owns concise matter identity and lifecycle editing without recreating a second oversized matter header.

## Context and Goals

### Current-state audit

The production Matter route currently loads the matter, all proceeding/supporting documents, legacy links, CaseWiki sections, Notes, every organisation member, and administrator-auth user email data before rendering. `MatterTabs` keeps five feature-local state copies and attaches broad Postgres Changes subscriptions to `documents`, `document_links`, `wiki_sections`, and `case_notes`. The route has no URL-addressable active section or selected document state, and section failures cannot degrade independently.

The current Timeline has several architectural and interaction problems:

- it passes proceeding and supporting documents into the same graph, even though supporting material is not part of the procedural chain;
- Dagre lays the graph top-to-bottom while the approved product direction is left-to-right;
- node dimensions supplied to layout do not match the larger rendered cards, and visual type colours misuse danger/success semantics;
- hover cards repeat raw metadata and create a second, inconsistent document-detail experience;
- relation direction is inverted in presentation code without a typed inverse-label contract;
- unknown or pending legacy relationships can be drawn beside effective links, and always-visible connection handles encourage accidental mutation;
- connecting a node to itself is not stopped in the browser, even though an old database constraint attempts to reject it;
- drawing over an existing edge opens deletion, while clicking an edge intentionally does nothing;
- `Re-evaluate Links` exposes an implementation repair operation that should be event-driven;
- supporting-document visibility, the minimap, Help, and repair actions consume a permanent toolbar even when they do not improve the normal reading task;
- graph node positions are mixed with mutable React state and can jump when live data changes.

The current Files section is a card grid built from storage-path filenames. It has no useful table columns, filter contract, content/readability status, evidence-to-proceeding association, or unified Workbench. The current Details section repeats the matter title/header in a large card, uses feature-local buttons and modals, combines procedural forum values with record status, and directly mutates documents when financial year changes. CaseWiki and Notes are loaded eagerly even when their tabs are never opened.

The reviewed development concept at `/dev/matter-workspace-concept` established the approved visual direction: compact matter identity, the full section strip with a modest shadow, horizontal Timeline, a single opposite-view control, a desktop chronology table, compact mobile chronology cards, a right-side document inspector, a dense Files table, Activity before Details, Details at the far right, a rupee Financials icon, and a truthful `Live` indicator beside matter metadata. The concept remains a design reference, not production data or interaction code.

### Goals

- Make the Matter route immediately communicate the client, dispute, current state, and next useful action without spending a large portion of the viewport on duplicated headings.
- Let a lawyer understand procedural sequence, branches, decisions, unresolved relationships, and the material effect of each proceeding at a glance.
- Preserve evidence fidelity: every document, key fact, edge, Activity item, and later Case Brief claim can open the exact authorised source/version/page in the shared Workbench.
- Keep the graph readable and safe as documents are added, reclassified, reassigned, replaced, trashed, restored, or corrected.
- Make Timeline, chronology, Files, Activity, and Details complete on desktop and mobile with explicit scroll ownership, keyboard behavior, loading/empty/error/partial states, and no page-level horizontal overflow.
- Load only the shell and active section initially; isolate failures and avoid sending privileged user-directory data to a general matter route.
- Consume the approved lifecycle, relationship, Activity, Search, Trash, and Realtime contracts rather than creating page-local status machines or duplicate storage.
- Give implementation agents a settled route, projection, component, permission, migration, and acceptance contract.

### Scope boundaries

- The detailed Notes/mentions/quotations/task conversation and Case Brief block/version/refresh model will be specified in the separate Notes and Case Brief plan. This plan fixes their Matter navigation, lazy loading, unread count, scroll, read-only, and deep-link integration only.
- Canonical deadline and financial schemas, verification, reminders, charts, internal-cost privacy, and organisation-wide pages will be specified in the separate Deadlines and Financials plan. This plan fixes their Matter navigation and projection integration only.
- Document ingestion, placement, immutable versions, extraction, relationship resolution, Workbench, PDF quotations, reclassification, and scoped retries remain owned by the approved Document Hub and lifecycle plans.
- The Timeline does not visualize supporting evidence, statutes, sections, rules, circulars, note replies, tasks, deadlines, financial events, or ordinary cross-matter citations as document nodes/edges.
- Shared custom organisation fields and matter-level access control are deferred to Organisation Administration. Details does not render arbitrary JSON or imply that a responsibility label changes document access.

## Decisions

### Matter workspace route and state

- `/matters/{matterId}` remains the canonical Matter route. Use URL state rather than component-only tabs:
  - `section=timeline|files|case-brief|notes|deadlines|financials|activity|details`;
  - `view=graph|chronology` only for Timeline;
  - `document={documentId}` for a selected Timeline/Files inspector subject;
  - `inspector=overview|relationships|notes` when a document inspector subview is deep-linked;
  - repeated typed filter parameters for shareable Timeline, Files, or Activity filters.
- Timeline is the default section and graph is the default desktop view for an ordinary matter. Constrained viewports always use chronology. A returning deep link or explicit Back navigation preserves the supplied section/view/filter/document state; the application does not silently choose the last private section for a shared bare URL.
- Canonical document inspection and PDF routes use `/documents/{documentId}` plus version/source-locator/return context. Legacy `/matters/{matterId}/documents/{documentId}` routes redirect while preserving page, highlight, version, and return state.
- Browser-local graph viewport and temporary dragged positions may be remembered for the current user/device against a matter relationship revision. They are view preferences, never shared legal state, never stored on document rows, and are discarded when topology changes materially or the user chooses `Reset layout`.
- The route loader returns the compact workspace shell and section counts first. Each active section has a secured loader/projection and Suspense/error boundary. Do not eagerly fetch Notes, Case Brief, Activity, full document metadata, user directory, deadlines, and financials on every Matter visit.

### Compact stable chrome

- The authenticated top context bar remains compact and shows `Matters / {client}`; the matter title is not repeated as a third breadcrumb because the identity header immediately below owns it. Search uses the shell Search contract in `Current matter` scope and retains `Search this matter` plus `Cmd/Ctrl+K`.
- The matter header uses two compact lines:
  - line one: matter title, equal-rhythm status badge, and the current contextual primary action plus More actions;
  - line two: matter code, primary financial year/tax context, current forum/authority summary when available, separators, and the Realtime/freshness treatment.
- Keep header vertical padding compact. At ordinary desktop density, the top context bar and matter header together should not consume roughly a quarter of a 751px viewport. Long title and metadata behavior is deliberate: title truncates to one desktop line with accessible full text and may wrap to two lines on mobile; action placement does not collide or cause horizontal page scroll.
- The status badge uses the shared fixed geometry. It does not contain unexplained leading space or feature-local padding. Legal direction badges inside nodes/rows use the shared incoming/outgoing variants.
- `Live` follows the matter metadata, for example `CGST · Pune | Live`. The green dot subtly pulses only while live, and reduced motion removes the pulse. The tooltip truthfully names the initially live projections: Timeline document state, effective relationships, selected document overview, and Notes/unread state. It does not claim that Activity, Case Brief, Files, Deadlines, Financials, or Details are live.
- When Realtime is not available, show muted `Refreshed 12 min ago` or `Offline · Refreshed 12 min ago`; do not add an in-page Refresh action or polling. The timestamp is the last successful authoritative fetch.
- A closed matter remains readable. New proceeding/supporting uploads and relationship mutations are disabled until reopened, while authorised Notes and Activity remain available. Trashed matters use the normal route and all ordinary sections in read-only mode under the Trash plan.
- A trashed matter displays one persistent, restrained danger strip immediately below the top context bar: `In Trash — read only`, deletion root/retention context, and the authorised `Restore matter` action. Do not tint the entire application red or replace the familiar page. A child inherited through a trashed client explains that the client deletion root must be restored.

### Section navigation and primary actions

- Desktop section order is fixed: `Timeline`, `Files`, `Case Brief`, `Notes`, `Deadlines`, `Financials`, `Activity`, `Details`. Activity precedes Details and Details is the rightmost item. Financials uses the rupee icon.
- Use the reviewed full, opaque section strip with a modest shadow. It does not collapse, fade to low opacity, become glass, or require hover to discover navigation. The strip remains outside the active section scroller and does not move when its table/feed/body scrolls.
- On the Timeline canvas the strip overlays the upper canvas region so the graph can use the full bounded body. Nodes/layout reserve a safe top zone beneath it. On non-canvas desktop sections, reserve only the strip's compact height plus a small gap; do not add another hero heading such as `CHRONOLOGY`, `SUPPORTING MATERIAL`, or `Matter files` before the real content.
- On mobile, do not horizontally scroll eight section buttons. Use a fixed five-destination bottom bar: Timeline, Files, Case Brief, Notes, and More. More opens an accessible bottom sheet containing Deadlines, Financials, Activity, and Details and identifies the active secondary section. The bar never covers the last content row or primary bottom action.
- Counts have typed meanings:
  - Timeline: active proceeding-document count;
  - Files: active supporting-document count;
  - Notes: unread count for the current user, omitted at zero;
  - Deadlines: unresolved attention count defined by the Deadlines plan, not a raw lifetime total.
- The primary document action is contextual and direct:
  - Timeline: `Add proceeding` opens the native PDF picker immediately and supplies proceeding/matter intent;
  - Files: `Add supporting file` opens the native picker immediately and supplies supporting/matter intent;
  - other sections: `Add document` opens a small anchored choice menu for those two intents, then opens the native picker. This menu chooses legal classification intent; it is not an upload modal or extra Submit step.
- Creating a metadata-only record is a secondary labelled action in More when implemented by the lifecycle/import contract. Uploading never bypasses the one intake pipeline or durable upload tray.
- Matter More actions are `Edit details`, authorised `Change client`, `Close/Reopen matter`, and authorised `Move matter to Trash`, plus contextual repair actions only when a real stage has failed. There is no generic `Sync` or `Re-evaluate links` action.

### Scroll ownership and responsive structure

- The application shell, top context bar, matter identity header, and desktop section strip are stable. The remaining Matter body is a bounded `min-height: 0` workspace.
- Desktop Timeline graph owns no document-page scroll: React Flow owns pan/zoom inside the bounded canvas. Its inspector has one independent vertical scroller beneath a stable inspector header.
- Desktop chronology, Files, Activity, and Details each own one vertical body scroller. Table/feed headers or filters that interpret moving rows remain stable. The outer page does not also scroll them.
- Mobile uses one principal section/detail scroller beneath a compact matter identity region and above the bottom section bar. Filters use a drawer; selected document inspection becomes full-screen Workbench/list-detail navigation with a clear Back route and preserved list position.
- The graph is offered at `lg` and wider only. Tablets/phones use chronology. Browser zoom to 200% may therefore cross into chronology rather than create a clipped miniature graph.
- Every loader reserves near-final header/control dimensions. Live updates patch in place and never reorder a row or move a control under the pointer. Newly arrived items above a scrolled list use an affordance instead of forcing scroll movement.

### Timeline philosophy and source data

- Timeline answers: `Which proceeding happened, what did it do, and how did it change or advance this matter?`
- Timeline nodes are active logical documents with `document_class = proceeding`, including metadata-only records whose PDF has not yet been attached. A metadata-only node is labelled `PDF not attached`; it is not hidden or given fabricated passage evidence.
- Timeline edges are active, effective, intra-matter, timeline-visible `document_relationships` from the approved relationship model. Reference mentions, unresolved targets, fuzzy candidates, rejected/suspended/stale relationships, cross-matter citations, and supporting-document associations are not default effective edges.
- The relationship catalogue marks each type with canonical active phrase, inverse/progression phrase, Timeline visibility, acyclic requirement, allowed endpoint classes, and display priority. Initially Timeline-visible types are `responds_to`, `issued_pursuant_to`, `arises_from`, `challenges`, `decides`, `modifies`, `supersedes`, `remands`, and `gives_effect_to`. `refers_to` and `other` remain inspectable but are not graph edges by default.
- Timeline-visible effective relationships must remain acyclic within a matter. The relationship command takes a matter-scoped transaction/advisory lock and uses a recursive cycle check before activation. The existing database self-link, tenant, endpoint-state, duplicate-type, and proceeding-class constraints remain mandatory. Cycle failure returns a safe natural-language explanation and makes no partial mutation.
- Multiple effective types between the same pair remain separate canonical rows but render as one bundled edge. The highest display-priority relationship labels the edge and `+N` opens the full relationship list.
- Documents with no effective Timeline edge remain visible in a chronological unlinked lane/component. They are not silently attached to a guessed chain. Unknown dates sort after dated peers and carry `Date unavailable`.

### Horizontal layout and graph behavior

- Present case progression left to right. Use the current `@xyflow/react` foundation and a deterministic layered Dagre adapter with `rankdir = LR`, fixed measured node dimensions, stable ID tie-breaking, and adequate rank/node/edge-label separation. Keep the layout adapter isolated so a measured need for ELK or worker layout does not change domain contracts.
- Topology determines rank first. Effective document date orders peers within a rank and disconnected documents; it does not reverse an evidence-backed relationship merely to make dates look neat. Date contradictions are visible Review/provenance concerns.
- Canonical relationship direction remains `source document performs relationship action on target document`, as approved by the relationship plan. The visual Timeline normally draws earlier antecedent to later procedural result and uses the catalogue's inverse phrase. Example: canonical `Reply responds_to SCN` renders `SCN → Reply` with `answered by`; selecting it states the canonical sentence `Reply responds to Show Cause Notice`. The UI never reverses stored endpoints or invents its own label with string replacement.
- `Fit timeline`, zoom in, and zoom out remain visible compact controls with accessible names/tooltips. Add `Reset layout` only after a user drags a node. Do not show a permanent minimap for ordinary matters; offer it adaptively for a graph that exceeds the viewport substantially or through the graph More menu.
- Nodes are temporarily draggable for inspection only. Dragging never changes chronology, canonical relationships, or another user's view. Adding/removing/reclassifying documents preserves existing world coordinates where possible and does not auto-fit; `Fit timeline` is explicit.
- Default graph remains available for large matters, but the application may default a previously unconfigured matter with more than 60 active proceeding documents to chronology for legibility. The user can still choose Graph and filter it. React Flow lazy-loads only in graph mode and uses visible-element rendering. Acceptance covers 10, 50, 100, and 250-node fixtures.

### Timeline background pattern

- Use a restrained semantic dot grid at approximately 24px spacing to support orientation and panning. It uses `--border-subtle`/`--border` at low contrast and adapts through the same tokens in light/dark appearance.
- The pattern is functional canvas affordance, not a decorative scene. Do not add gradients, stars, legal-watermark imagery, paper texture, glow, or high-contrast graph paper. It does not appear behind chronology or other sections.

### Node contract

- Every desktop Timeline node uses one fixed rectangular `184px × 120px` contract with `var(--radius-md)`, neutral surface/border, and identical internal slots. Layout dimensions and rendered dimensions are the same.
- Content priority is fixed:
  1. short document type/code and legal direction badge;
  2. effective title, maximum two lines;
  3. effective date;
  4. concise procedural effect, maximum two lines;
  5. one optional highest-priority key fact such as operative demand, hearing date, or pre-deposit.
- Missing content keeps slot rhythm without printing empty labels. Long content truncates and is available in the inspector/Workbench. A node never expands because one PDF has a long reference or summary.
- Colour conveys approved semantics only: selected uses primary; incoming/outgoing uses their typed badge; processing is neutral with a spinner; Review is warning; failed/unavailable source is danger; metadata-only is muted. SCN/OIO document types are not painted danger merely because they are adverse documents.
- A node is a focusable button with an accessible name containing title/type, reference, date, direction, and attention state. Hover/focus may reveal only clipped text/help; it does not open a second quick-view card. Click/Enter selects the node and opens the inspector.
- Connection handles are hidden in reading mode. `Add relationship` enters an explicit mode with source/target instructions; self-selection is prevented immediately. Manual confirmation shows canonical and Timeline display sentences before applying the typed domain command.

### Edge and relationship interaction contract

- Effective edge base treatment is a solid, restrained semantic stroke with a clear progression arrow. Selected/path-emphasized edges use primary; Review candidates use warning only inside relationship-review mode; suspended/stale edges do not appear as effective paths.
- Edge labels are compact semantic surfaces containing the catalogue phrase in sentence case, never uppercase enum text. At low zoom they hide to prevent collisions; keyboard/hover/selection and the relationship inspector expose the full phrase. Labels and arrows must remain legible in light/dark and cannot rely on colour alone.
- Suggested relationships do not continuously animate on the ordinary graph. A compact `N relationships to review` warning action opens the matter-scoped Review list or candidate-review mode. In that mode one selected candidate may render dashed warning treatment with evidence; acceptance/rejection uses the canonical Review resolver.
- Clicking or keyboard-selecting an effective edge opens the Relationships inspector with both documents, canonical direction, display direction, type, evidence, verification, actor/policy, and correct/archive actions. Clicking an edge never silently deletes it.
- Manual deletion is expressed as `Archive relationship`, requires a reason when it changes procedural interpretation, appends Activity, and preserves the relationship decision history. Drawing over an existing edge does not initiate deletion.
- `How the timeline works` lives in the graph More menu/help popover with a textual relationship legend and link to chronology. It is not a permanent large toolbar button.

### Timeline filters and graph/chronology switch

- Use one `Filter` action and one opposite-view action. Graph shows `Chronology`; chronology shows `Graph`. Do not render both choices as a three-button segmented control. On constrained viewports Graph is unavailable, so no unusable opposite-view action is shown.
- Initial Timeline filters are:
  - reference/title text;
  - document type;
  - incoming/outgoing direction;
  - effective document date range;
  - relationship type;
  - attention state (`Review`, `Processing`, `Failed`, `PDF not attached`);
  - `Unlinked proceedings`;
  - `Has deadline` and `Has financial effect` only after their canonical projections exist.
- Filters apply to Graph and chronology and remain URL-addressable. The Filter button shows an active count and provides `Clear filters`. When an endpoint is filtered out, its edge is hidden rather than rerouted. The UI states `Showing N of M proceedings` in the compact toolbar/filter summary so the partial graph cannot be mistaken for the whole matter.
- The initial unfiltered state has no bulky count/description header. Total proceeding count already appears in the Timeline section item; relationship review count is a compact action.

### Desktop chronology and mobile timeline

- Desktop chronology is a semantic table, not a row of very wide cards. It uses the available workspace width with a compact sticky header and columns:
  - Date;
  - Document;
  - Direction;
  - Procedural effect;
  - Key fact;
  - Relationship/attention indicator and row affordance.
- A subtle chronology marker/line may live in the Date column, but it does not consume a separate wide rail. Rows are approximately 56–64px, tolerate two lines where necessary, and open the same inspector. There is no `CHRONOLOGY / N proceeding documents` hero above the table.
- Sorting defaults to effective document date ascending, then created time/ID, with undated records last. Users may sort Date or Document, but a non-chronological sort clearly removes the connecting chronology line.
- Phones/tablets use compact chronological cards/list rows because column relationships cannot be preserved. A card groups icon, title/reference, direction, date, one procedural effect, and one optional key fact in a tight layout; metadata does not become one full-width line per field. Selecting it opens the full-screen Workbench/detail route and Back restores the list position.
- Mobile empty/loading/error states use the same single scroller and do not leave large blank top padding before the first chronology row.

### Document inspector and Workbench handoff

- On desktop, selecting a node/chronology row opens a `392px` right inspector. The canvas/table viewport changes width without recomputing node world positions; if the selected node would be obscured, pan it into the visible region without fitting the whole graph again.
- The inspector has a stable identity header, close action, and `Open document` primary action. Its body has `Overview`, `Relationships`, and `Notes` subviews and one vertical scroller.
- Overview prioritizes `What changed`, one consequential deadline, one consequential financial effect, effective identity facts, processing/readability/version warning, and evidence links. It does not dump arbitrary `raw_metadata` or show a fake AI confidence percentage. `View all metadata` opens the shared Workbench inspector.
- Relationships lists incoming/outgoing effective relationships, bundled types, unresolved reference mentions, and authorised Review/manual actions with evidence. Notes shows a small document-scoped preview and `Open Notes`/`Add note`; the separate Notes plan owns composition and unread semantics.
- `Open document` opens the shared Workbench at the current immutable version and preserves the Matter return locator. Timeline, Files, Search, Activity, Trash, and Review never create another PDF viewer or metadata panel.
- On mobile, selection goes directly to the canonical Workbench/full-screen detail instead of layering an inspector over a narrow chronology scroller.

### Files supporting-evidence library

- Files contains active logical documents with `document_class = supporting`; proceeding documents remain in Timeline. A supporting document may have native/OCR/extracted metadata, metadata only, or no reliable text. The UI states the actual availability instead of implying every file was AI-read.
- Remove the large `SUPPORTING MATERIAL / Matter files` heading and explanatory paragraph. The selected section and table columns establish context. Use a compact toolbar with Search, Filters, result count when filtered, and `Add supporting file`.
- Desktop uses a semantic table with `File`, `Category`, `Added`, `Linked to`, `Content`, and More actions. File identity includes type/icon, title/original filename, size, and content/indexing state without reading a storage path in the browser.
- Mobile uses a compact list: icon plus title/filename, a single metadata line, category badge, linked-proceeding summary, and More. It must not vertically stack category, date, link, and menu into oversized cards.
- Category navigation lives inside Filters, not a permanent left category card. Seed a supporting-file category catalogue with stable keys/labels:
  - `evidence` — Evidence;
  - `financial_records` — Invoices & financial records;
  - `correspondence` — Correspondence;
  - `research_authorities` — Research & authorities;
  - `media_site_material` — Media & site material;
  - `other` — Other.
- Categories are rows in `supporting_file_categories`, with system rows and future organisation rows, instead of another PostgreSQL enum. The document stores `supporting_category_id`; inactive categories remain renderable for history. `Other` is the fallback, not a dumping rule that prevents later correction.
- Add `document_evidence_associations` for optional same-matter supporting-to-proceeding links. It stores organisation/matter, supporting document, proceeding document, kind (`supports`, `submitted_with`, `attachment_to`, `background`), optional concise note, actor, and timestamps. Constraints enforce source class supporting, target class proceeding, same matter/organisation, active endpoint lineage, and unique active pair/kind. These associations appear in Files/Workbench but never as procedural Timeline edges.
- Selecting a file opens the shared Workbench. More actions follow capabilities: Edit record, Link to proceeding, Change category, Promote to proceeding with impact preview, Replace PDF, Download original, and Move to Trash. There is no page-specific PDF modal.
- Size/quota policy remains the lifecycle plan's 25 MB/PDF, 100 MB/organisation, and 750 MB platform guard. Files displays organisation storage warning only through the shared quota projection and never invents a matter-local hard limit.

### Matter Activity

- Activity is a matter-filtered view over canonical `activity_events`; do not create `matter_activity` rows or reconstruct free-form descriptions from current entities.
- Remove a large introductory header. Use a compact filter toolbar and a dense feed grouped by Today, Yesterday, then calendar date. Filters reuse the Activity plan's actor, category/event, entity, source, and date-range contracts and remain URL-addressable.
- Every item uses the shared versioned renderer, actor/subject snapshots, matter lineage, and authorised typed locator. It can open the exact document/version, relationship decision, note, Review item, deadline, financial entry, or Trash route.
- Activity is not an initial live projection. Opening/reopening it performs an authoritative fetch; the matter's selective Live connection does not claim to stream the feed. New Activity events never move the user's scrolled list unexpectedly.

### Matter Details and status normalization

- Details is the only full matter-profile editor. It does not repeat the full matter title/status/action hero already present in stable chrome.
- Read mode uses compact grouped rows for:
  - identity: title, organisation-unique matter code, client, financial year, synopsis;
  - procedure: work state, current forum/stage, verified external matter/proceeding identifiers;
  - client identifiers: authorised GSTIN/PAN display sourced from the Client record, not copied into Matter;
  - audit: creator, created time, last material update, and Activity link.
- Keep `matter_code` stable and organisation-unique. Changes require Owner/Admin capability, explicit reason, collision check, and Activity; ordinary title edits never regenerate it.
- Split the overloaded legacy `matter_status` into:
  - `work_state`: `active | stayed | disposed | closed`;
  - `current_forum`: `adjudication | first_appeal | tribunal | high_court | supreme_court | remand | other`.
- Additive backfill maps legacy values deterministically: `active → active/adjudication`; `stayed → stayed/adjudication`; `disposed → disposed/adjudication`; `appeal_pending → active/first_appeal`; `tribunal → active/tribunal`; `high_court → active/high_court`; `supreme_court → active/supreme_court`; `closed → closed/current inferred forum or other`. Flag ambiguous current forum for optional correction; never fabricate a court from document text during migration.
- Record/Trash state remains separate under the Trash plan. Changing work state/forum does not move a resource to Trash or rewrite document metadata.
- Use the approved `matter_identifiers` contract from the Document Hub plan for external case/proceeding/portal identifiers and their verification/provenance. Financial year is an attribute and placement signal, not matter identity; multiple matters for one client/year remain valid.
- `Edit details` uses a desktop side sheet and mobile dedicated form with shared inputs, not a feature-local modal. Title/synopsis/work state/forum edits use optimistic concurrency. Client reassignment and matter-code change are separate Owner/Admin impact-preview commands because they affect Search, placement, Activity lineage, and identifiers.
- Arbitrary custom JSON fields, decorative cards, and duplicate Client-edit controls are excluded. Organisation-defined custom-field architecture requires its own administration contract before appearing here.

### Permissions and mutation boundaries

- Server projections return capability keys; clients do not infer permission solely from role strings. RLS and domain commands revalidate organisation, parent lineage, current record/Trash state, source revision, and capability.
- Viewer can read authorised active and Trash-readable Matter sections, chronology, relationships, supporting associations, and Workbench evidence. Viewer cannot upload, edit, relate, reclassify, retry, close/reopen, restore, or trash.
- Associate can upload proceedings/supporting files, edit ordinary title/synopsis/work-state/forum fields, manage permitted manual relationships and evidence associations, correct permitted metadata, and use scoped retry when assigned/allowed. As already approved, Associates may trash/restore individual documents; they cannot trash/restore a whole matter or client by default.
- Owner/Admin can change matter client/code, manage identifiers, resolve privileged conflicts, close/reopen, trash/restore the matter, and administer category catalogue rows. Permanent purge remains Owner/Admin-only under the Trash plan and is never offered from the ordinary active Details screen.
- A trashed matter and inherited child resources are fully read-only except for permitted restore/purge workflows. A closed active matter blocks document/relationship mutations but may still accept authorised Notes/tasks and status reopening.
- Every material mutation appends canonical Activity and an outbox event where projections/async work are affected. Direct page code never edits legacy `raw_metadata`, storage paths, relationship rows, Search vectors, deadlines, or financial facts.

### Selective Realtime and freshness

- Replace `MatterTabs` broad table subscriptions with the one shared private topic `org:{org_id}:matter:{matter_id}` and connection manager specified by the Realtime plan.
- Initial matter events invalidate only named projections: Timeline document summary/count, effective relationships/review count, selected document inspector, Notes unread/message state, and compact shell counts where explicitly allowlisted.
- Coalesce related invalidations and fetch the smallest authorised projection. The initiating mutation updates its own UI from the domain command response and does not wait for event echo. Do not combine a targeted fetch with unconditional `router.refresh()`.
- Files rows, Case Brief content, Deadline/Financial bodies, Details, and Activity remain fetch-on-open/navigation projections initially. Their eventual domain events can update compact counts only when approved and measured.
- The shared connection leaves after the route/scope unmounts or the page has been hidden for five minutes, reconciles once on foreground/reconnect, performs no periodic polling, and shows Live only after authorised subscription plus successful reconciliation.

### Failure, loading, empty, and partial behavior

- Shell failure distinguishes inaccessible/not found, trashed but authorised, and temporary loading failure without leaking cross-tenant existence.
- A section failure leaves matter identity and navigation usable and provides a section-scoped Retry only for an ordinary data-read failure. This is not a generic data Sync or graph rebuild.
- Timeline empty state says `No proceeding documents yet` and offers `Add proceeding` when permitted. If only supporting files exist, link to Files without promoting them implicitly. Read-only states explain why creation is unavailable.
- Graph layout failure falls back to chronology with a safe message and telemetry; it does not block access to documents. A relationship-processing failure shows its real stage and authorised `Retry relationship matching` through More/Review.
- Disconnected, undated, metadata-only, source-unreadable, processing, provisional, failed, historical-version, and partially backfilled documents have explicit typed states. Missing data renders `Not available` rather than empty decorative cards.
- Files empty state says what supporting files are and offers upload when permitted. Filtered empty state preserves filters and exposes `Clear filters`.
- Activity/Details/other delegated sections implement loading/empty/error/partial states inside their scroll owner without shifting stable chrome.

## Implementation Plan

1. **Freeze fixtures and current behavior.** Capture the current Matter route, five tabs, graph/link editing, Files grid, Details mutations, broad Realtime, closed/deleted behavior, legacy document route, and representative 0/1/5/50/100/250-document matters. Add fixtures for branches, merges, disconnected/undated/metadata-only documents, multiple relation types, cycles, self-links, supporting files, stale candidates, Trash roots, long identity text, and partial projection failures.
2. **Add workspace projections and capability contract.** Implement the secured shell projection, section counts, active-section loaders, capability keys, status/forum mapping, and typed route/query parser. Remove service-role auth-user listing from the Matter read path and use the canonical organisation-member profile projection only in the sections that need it.
3. **Normalize matter status additively.** Add `work_state` and `current_forum`, backfill/report legacy mappings, dual-read through a typed adapter, cut consumers over, verify ambiguous rows, then retire the overloaded enum only in a later contract migration.
4. **Complete relationship prerequisites.** Use the Document Hub plan to add/backfill effective relationships, catalogue display/inverse phrases, Timeline visibility/acyclic metadata, candidates/decisions, and integrity/cycle commands. Do not build the final graph over mutable legacy `document_links` semantics.
5. **Build the shared Matter shell.** Implement compact context/header, scoped Search entry, contextual upload action, More actions, stable desktop strip, mobile five-item bar/More sheet, read-only danger strip, URL state, lazy section boundaries, and explicit scroll containers with Civic Ink primitives.
6. **Build Timeline projection and chronology first.** Implement proceeding-only summaries, deterministic ordering, filters, desktop semantic table, compact mobile list, inspector selection/deep links, loading/empty/error/partial states, and Workbench handoff. This creates an accessible authoritative fallback before the graph cutover.
7. **Rebuild the graph.** Add the isolated LR Dagre adapter, fixed node/edge catalogue contracts, progression-direction transformer, bundled edges, unlinked lane, semantic dot grid, keyboard nodes/edges, selective controls, temporary drag/viewport state, explicit relation mode, inspector integration, adaptive minimap, lazy load, and large-graph behavior.
8. **Build relationship review interaction.** Connect the `N relationships to review` action to typed Review, render only the selected candidate in review mode, and implement accept/correct/reject/archive through canonical resolvers with evidence, stale revision handling, Activity, and no page-local deletion semantics.
9. **Rebuild Files.** Add supporting category catalogue and evidence associations, migrate legacy category values/links, implement compact toolbar/filter drawer, desktop table/mobile list, content availability, Workbench route, classification/reclassification impact flows, and direct supporting upload.
10. **Integrate Activity and Details.** Reuse the canonical matter-filtered Activity renderer and URL filters. Replace the duplicate Details hero/modals with compact grouped rows, shared side sheet/form, optimistic concurrency, identifiers, capability-gated client/code/status commands, and Activity links.
11. **Integrate delegated sections.** Mount Case Brief, Notes, Deadlines, and Financials through their own projections while preserving the shell, URL, section count, read-only, Realtime/freshness, scroll, mobile navigation, and Workbench source-locator contracts in this plan.
12. **Migrate Realtime.** Instrument the current subscriptions, add the private matter Broadcast topic/manager, map allowlisted invalidations to targeted section projections, implement truthful freshness states, run parity observation, then remove four broad Postgres Changes subscriptions and feature-local state copies.
13. **Backfill and cut over.** Backfill status/forum, categories/evidence associations, relationship catalogue/display data, and Activity targets in resumable matter/org batches. Compare legacy/new proceeding/supporting/link/count/render coverage, keep route/read adapters during rollback, and stop legacy writes only after every row has an explicit disposition.
14. **Remove replaced UI/contracts.** Remove old `MatterTabs`, Files card grid, CaseWiki label, hover quick view, page-local PDF/detail route, supporting-in-Timeline toggle, permanent minimap/Help/repair toolbar, unsafe draw-to-delete behavior, `Re-evaluate Links`, raw metadata inspector reads, and feature-local edit/delete modals after equivalent capability passes.
15. **Validate and document reusable contracts.** Add Matter workspace, Timeline node/edge/inspector, section strip, mobile section More, chronology table, and supporting-file patterns to `/dev/design-system` and the relevant design-system documentation. Keep `/dev/matter-workspace-concept` as a reviewed reference or remove it after the production gallery fully represents the contract.

## Interfaces and Data Changes

### Workspace projection

```ts
type MatterSection =
  | 'timeline'
  | 'files'
  | 'case-brief'
  | 'notes'
  | 'deadlines'
  | 'financials'
  | 'activity'
  | 'details'

type MatterCapability =
  | 'matter.read'
  | 'matter.edit_content'
  | 'matter.edit_identity'
  | 'matter.close_reopen'
  | 'matter.trash_restore'
  | 'document.add_proceeding'
  | 'document.add_supporting'
  | 'relationship.manage'
  | 'relationship.review'
  | 'supporting_association.manage'
  | 'processing.retry_relationships'

type MatterWorkspaceShell = {
  matter: {
    id: string
    clientId: string
    clientName: string
    title: string
    matterCode: string
    financialYear: string | null
    workState: 'active' | 'stayed' | 'disposed' | 'closed'
    currentForum:
      | 'adjudication'
      | 'first_appeal'
      | 'tribunal'
      | 'high_court'
      | 'supreme_court'
      | 'remand'
      | 'other'
    recordState: 'active' | 'trashed'
    revision: number | string
  }
  counts: {
    proceedings: number
    supportingFiles: number
    unreadNotes: number
    deadlineAttention: number
    relationshipReview: number
  }
  capabilities: MatterCapability[]
  trashContext?: {
    operationId: string
    rootType: 'client' | 'matter'
    rootId: string
    deletedAt: string
    purgeEligibleAt: string | null
  }
}
```

- Server code derives organisation, access, counts, capabilities, and Trash context. The browser supplies only stable route IDs/filter state and cannot request another organisation's projection.
- Every section result includes its source revision and `fetchedAt` for stale-response and freshness handling.

### Timeline projection

```ts
type TimelineDocumentSummary = {
  id: string
  revision: number | string
  title: string
  documentType: string | null
  referenceNumber: string | null
  effectiveDate: string | null
  direction: 'incoming' | 'outgoing' | null
  proceduralEffect: string | null
  keyFact?: {
    kind: 'amount' | 'deadline' | 'hearing' | 'outcome' | 'other'
    label: string
    value: string
    verification: 'human' | 'verified' | 'provisional'
    locator?: DocumentSourceLocator
  }
  contentAvailability:
    | 'metadata_only'
    | 'source_attached'
    | 'source_indexed'
    | 'source_unreadable'
  attentionState: 'none' | 'processing' | 'review' | 'failed'
}

type TimelineRelationshipSummary = {
  id: string
  revision: number | string
  canonicalSourceDocumentId: string
  canonicalTargetDocumentId: string
  displayFromDocumentId: string
  displayToDocumentId: string
  type: DocumentRelationshipType
  canonicalPhrase: string
  progressionPhrase: string
  verification: 'human' | 'policy_confirmed' | 'provisional'
  bundledRelationshipIds: string[]
}

type MatterTimelineProjection = {
  matterId: string
  revision: number | string
  documents: TimelineDocumentSummary[]
  relationships: TimelineRelationshipSummary[]
  relationshipReviewCount: number
  filtersApplied: number
  fetchedAt: string
}
```

- The projection never includes raw provider output, full document text, embeddings, storage keys, or unrestricted `raw_metadata`.
- The edge transformer uses the relationship catalogue; it does not infer inverse labels from enum names at render time.

### Matter and Files data changes

- Add `matters.work_state`, `matters.current_forum`, and a revision/optimistic-concurrency field. Keep legacy `status` during additive migration.
- Continue the approved `matter_identifiers` table for verified external identifiers and source locators.
- Add `supporting_file_categories`: ID, nullable organisation for system rows, stable key, display label, sort order, active state, creator/timestamps, and uniqueness scoped to system/organisation.
- Replace free-text/new writes to `documents.document_category` with `documents.supporting_category_id` after backfill. Retain legacy value through compatibility until verified.
- Add `document_evidence_associations`: ID, organisation, matter, supporting document, proceeding document, association kind, optional note, lifecycle state, creator/timestamps, revision, and unique active pair/kind constraint.
- Relationship catalogue additions needed by Timeline: canonical phrase, inverse/progression phrase, Timeline-visible flag, acyclic flag, display priority, and version.
- No table stores graph coordinates, expanded inspector section, active Matter section, or current graph zoom as shared legal state.

### Commands and events

- Commands: load workspace/section projection; update ordinary matter profile; change matter code/client with impact preview; change work state/forum; close/reopen; reserve/finalize contextual upload; create/correct/archive effective relationship; manage evidence association; change supporting category; reclassify; obtain Workbench route/source access; scoped relationship retry; Trash/restore through the Trash domain.
- Events: `matter.profile_updated`, `matter.identity_changed`, `matter.work_state_changed`, `matter.forum_changed`, `matter.closed`, `matter.reopened`, `matter.trashed`, `matter.restored`, document/classification/version events from Lifecycle, effective relationship/candidate events from Relationships, evidence-association events, and canonical Activity/outbox events.
- Realtime invalidations carry only IDs, revisions, event kind, and safe projection names. They contain no matter title, client identity, filename, note body, extracted fact, quote, signed URL, or storage path.

## Testing and Acceptance Criteria

### Shell, routing, and responsive behavior

- Direct links restore each section, Timeline view, filters, selected document, and inspector subview after reload, authentication redirect, Workbench return, and Back/Forward navigation. Invalid or inaccessible query IDs degrade without leaking existence.
- Matter identity, selected section, and primary action remain available while every desktop body/pane scrolls. Scrolling chronology, Files, Activity, Details, or the inspector moves only its intended body.
- At 320px, common phone, tablet/200% zoom, 1470×751, and wide desktop, there is no page-level horizontal overflow, accidental nested scroll, oversized mobile file card, blank chronology top region, or bottom bar covering content.
- The desktop strip remains fully opaque with modest shadow and never collapses/fades. Mobile exposes all eight sections through four direct destinations plus More without a horizontal scrollbar.
- Header/status/count badges retain consistent geometry for long titles, unknown FY, Live/freshness, Trash, and closed states. Context bar plus matter header does not dominate the usable viewport.

### Timeline and relationships

- Timeline contains only active proceeding documents. Supporting, independently trashed, inaccessible, cross-matter, and purged records never appear as ordinary nodes; metadata-only proceedings do appear with honest state.
- The same deterministic fixture produces stable left-to-right ranks and ordering. Branch, merge, disconnected, undated, same-day, multiple-edge, and large-graph fixtures remain usable and do not overlap nodes/labels at the approved fit level.
- Node layout dimensions exactly equal `184px × 120px`; long content never resizes a node. Danger/success colours are used only for their semantic status, not document type decoration.
- Canonical direction and progression display direction are both correct for every initial relationship type. `Reply responds_to SCN` renders the reviewed earlier-to-later phrase while the inspector exposes the canonical sentence.
- Self-links, cross-organisation endpoints, supporting endpoints, unavailable endpoints, duplicate active type edges, impossible inverses, and timeline-visible cycles fail at browser, command, and applicable database layers. Concurrent cycle attempts cannot both commit.
- Exact citations without procedural meaning, fuzzy matches, unresolved references, cross-matter references, and Review candidates do not become default Timeline edges. Candidate review requires typed evidence and stale-revision validation.
- A rejected candidate does not reappear unchanged. Manual corrections remain authoritative after extraction/model/relationship reruns, reassignment, replacement, reclassification, Trash, and restore.
- Opening/closing the inspector and receiving a live document/edge update preserve graph world coordinates and focus. A selected obscured node pans into view without an unsolicited fit/re-layout.
- Graph nodes/relationships are operable and understandable by keyboard/screen reader through focusable nodes, relationship lists, accessible labels, and chronology fallback; essential information is not canvas-only or hover-only.

### Chronology, Files, Activity, and Details

- Desktop chronology uses actual table semantics and approved columns with compact rows; mobile uses compact rows/cards. Both select the same document and open the same inspector/Workbench evidence.
- Timeline filters apply consistently across Graph/chronology, survive the view switch, state the partial count, and never visually reconnect around a filtered endpoint.
- Files category/search/content/association filters are server-authorised and URL-addressable. Built-in, inactive historical, and future organisation categories render correctly; missing category falls back safely.
- Evidence associations accept only same-organisation, same-matter supporting→proceeding pairs and never appear as procedural edges. Reclassification/move/Trash produces the approved impact/suspension behavior without orphan links.
- Files desktop rows and mobile list expose useful identity, category, content availability, linked proceedings, and actions without storage-path parsing. Every file opens the shared Workbench rather than a PDF-only modal.
- Matter Activity count/render/filter results equal the canonical organisation Activity stream restricted by stored matter lineage, including after rename, Trash, restore, and purge tombstone behavior.
- Legacy status backfill produces the documented work-state/forum mapping and reports every ambiguous/unmapped row. Changing FY or forum never bulk-overwrites verified document metadata.
- Viewer/Associate/Owner/Admin capability tests cover every visible/missing action and direct command/RPC attempt. Associates cannot use client/code/matter-trash commands merely by forging UI payloads.

### Realtime, migration, reliability, and performance

- One Matter route uses one shared socket/topic, performs targeted revision-aware refreshes, leaves after the approved hidden timeout, reconciles after gaps, and starts no periodic polling. Non-live sections are not falsely advertised as streaming.
- Duplicate, reordered, stale, missed, malformed, and cross-tenant Realtime events cannot duplicate/regress data or reveal matter existence. Quota/auth refusal shows freshness, not Live, and does not reconnect aggressively.
- A section read/layout/relationship-stage failure leaves the shell and other sections usable. Layout failure exposes chronology; provider/relationship failure exposes a scoped recovery state, never a generic Sync.
- Additive backfill reports active/trashed matters, status/forum mappings, proceeding/supporting counts, legacy/new relationship disposition, category mappings, evidence associations, invalid links/cycles/self-links, missing documents/assets, and unmigrated rows. Cutover is blocked until every legacy row has a terminal disposition.
- Automated visual/accessibility tests cover light/dark, reduced motion, 200% zoom, keyboard/focus, screen-reader names, long content, loading/empty/error/partial/read-only states, fixed node/card geometry, and screenshot baselines at phone/desktop.
- Performance fixtures measure shell query, active-section query, layout, first meaningful paint, interaction latency, and Realtime refetches at 10/50/100/250 nodes. Target p95 under 500ms for the secured shell/ordinary first-section database projection on representative pilot data, with graph code/layout lazy and non-blocking; publish measured results rather than hiding latency behind fabricated loading progress.
- `npx tsc --noEmit`, changed-file ESLint, relevant unit/integration/RLS/E2E/accessibility tests, `git diff --check`, production build, and in-app Browser verification pass before legacy Matter components/routes are removed. Interrupted or timed-out checks are reported honestly.

## Assumptions

- Supabase/PostgreSQL, Next.js, `@xyflow/react`, Dagre, private Storage, the shared Document Workbench, and Civic Ink remain the initial implementation stack.
- Matter access is organisation-wide in the controlled pilot; projections/capabilities retain tenant and matter lineage so future matter-level restrictions do not require a new UI/data model.
- The approved lifecycle, ingestion/relationship, Activity/Review, Trash, Search, and Realtime plans remain authoritative where this plan consumes their domains.
- The reviewed development concept establishes direction but may use fixture-only content and feature-local code that must not be copied around shared contracts.

## Open Questions

None.
