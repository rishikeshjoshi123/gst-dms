---
title: Design Partner Pilot Execution Sequence
status: proposed
created: 2026-08-29
updated: 2026-09-14
owners:
  - product
  - engineering
related:
  - ../platform/2026-08-24-product-architecture-portfolio.md
  - ../platform/2026-08-26-organisation-administration.md
  - ../platform/2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../features/2026-08-25-work-review-activity-notifications.md
  - ../features/2026-08-25-document-hub-ingestion-and-workbench.md
  - ../features/2026-08-25-matter-workspace-and-procedural-timeline.md
  - ../features/2026-08-24-universal-search-and-evidence-retrieval.md
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
  - ../platform/2026-08-27-platform-operations.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Design Partner Pilot Execution Sequence

## Summary

Reorder implementation around a production-safe vertical slice for the first design-partner pilot without weakening the approved architecture or its independent QA standard. Reconcile the actual checkout and close build/authorization gaps, then move through identity, human Review, Document Hub/Workbench, a bounded Matter workspace, and pilot operations as one observable client journey. Use the delivery ledger for current progress rather than replaying an old checkpoint.

The client handoff is a production-hosted pilot with normal onboarding: the design partner opens the production URL, signs up by email, verifies the account, creates an organisation or explicitly accepts a pending invitation, and uploads original confidential litigation PDFs. Target release is October 12–15, 2026, with a short safety delay permitted but October 20 as the final target. An internal pre-production rehearsal may use synthetic or sanitised fixtures, but it is not the promised client deliverable. The production pilot opens only after tenant isolation, durable document processing, human-reviewed extraction, deployment, a tested backup/object-recovery boundary appropriate to the selected production tier, monitoring, and release acceptance pass.

## Context and Goals

The checkpoint narrative below is historical. The 2026-09-08 [delivery workflow](./2026-09-08-agent-delivery-workflow.md) and [ledger](../../delivery-ledger.md) govern current sequencing and evidence. This pilot plan remains `proposed`; the September 11 [Trash decision](../../decision-history/2026-09-11-trash-retention-activation.md) resolves the former retention-activation conflict and selects one daily midnight-IST purge sweep, while the other recorded release gates remain open.

The [September 14 first-release decision](../../decision-history/2026-09-14-first-production-release-scope.md) settles the product boundary and packet order. The remaining blocking discussion is [production go-live ownership, compliant hosting and incident response](../../approval-based-blockers.md#2026-09-14--production-go-live-ownership-hosting-recovery-and-incident-response). Preserve the already integrated chronology, read-only graph and governed manual relationship work. Product implementation may follow the ordered release scope, but confidential deployment still requires the separate go-live decision and exact deployed acceptance.

The architecture execution task established the correct foundations first: tenant identity/RBAC, immutable document assets and versions, canonical Intake and placement, durable outbox/reprocess authority, provenance runs/candidates/decisions, processing writes, and a current-version Search fence. It paused after `2196cd2`, which independently verified the bounded effective-metadata Search consumer, and `16b6bed`, which saved the assignment effective-metadata consumer as a developer-checked but not independently verified checkpoint.

Continuing the active AI plan consumer by consumer before implementing the primary product workspaces would be technically coherent but release-inefficient. It would defer the UI through which a design partner can validate the product, and it would consume limited weekly agent capacity on capabilities outside the first pilot journey.

The supplied design-partner corpus in a user-controlled local folder outside the repository contains 311 readable, unencrypted PDFs, about 201.7 MiB and 1,318 pages in aggregate. Individual files range from roughly 3.6 KiB to 7.0 MiB, so every file is below the approved 25 MiB per-file default, but the complete corpus exceeds the existing 100 MiB pilot-organisation storage entitlement. The corpus is confidential test input: filenames, extracted content, PDFs, and document-specific metadata must not be committed, published, or emitted into ordinary logs.

The goals are:

- expose one truthful end-to-end workflow to the design partner as early as possible;
- preserve tenant isolation, evidence identity, durable recovery, human authority, and independent QA;
- use client feedback on real workflow and layout before implementing lower-priority product breadth;
- rehearse internally before authorising the production environment to process confidential client documents;
- make every deferred or disabled capability explicit rather than presenting incomplete behavior as production-ready;
- keep the canonical portfolio contracts authoritative and resume them after the pilot gate.

The first pilot validates document-centric GST-litigation work. It is not a promise that every canonical feature domain is complete.

## Decisions

### September 10 user corrections

The user subsequently accepted the [non-critical execution/documentation recommendations](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md#non-critical-october-recommendations-accepted): focused increments, repeatable acceptance, bounded helpers/repairs, selective tracking, early staging preparation, an October 4 freeze target and stabilisation before the October 12–15 presentation. The September 14 decision now settles product scope and order. Production hosting/recovery compliance, named go-live authority and incident response remain unresolved and keep this plan proposed.

The [recorded user decisions](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md) establish disposable pre-pilot test data and normal signup/create-or-join entry. The September 11 Trash decision additionally activates automatic retention and selects one daily midnight-IST physical-purge sweep, without deploying production services. This pilot proposal still requires the graph-first October scope reconciliation described in the [current assessment](../../reviews/2026-09-10-october-release-reassessment.md).

### September 14 first-release scope

- Release one trusted design-partner organisation between October 12 and 15, with October 20 as the final permissible target after a short safety delay. The Owner creates the organisation and invites the remaining members; invitation acceptance is explicit and bound to the verified account.
- The mandatory journey is signup/verification → create or join → Client/Matter → global or Matter-origin PDF upload → truthful processing/manual recovery → applicable typed Review → placement → exact Workbench reopening → Matter inspection.
- Chronology and a truthful read-only graph are mandatory. Governed human relationship editing and quality-gated relationship suggestions are desirable; relationship suggestions are the highest-priority optional capability and the last conditional feature to cut. Disconnected documents remain visible and no inference is promoted merely to populate the graph.
- Source-grounded metadata extraction followed by efficient human review-by-exception is the mandatory ordinary workflow and must pass its approved gates. A flow that normally requires hand-typing each PDF's metadata is not release-acceptable. Manual entry/correction, placement and relationship fallback remain exceptional recovery paths for provider failure, unreadable sources and corrections. Matter/current-document cited retrieval is high-value but conditional and is cut before the core journey or stabilisation window is threatened.
- Manually verified legal deadlines with truthful due/missed/completion state are mandatory. Owned Tasks, Notes-to-Task, reminders, broad Financials and relationship suggestions are conditional. Dashboard/Today, Case Brief, organisation-wide semantic Search, advanced administration, broad Realtime, bulk/non-PDF ingestion and marketing/demo refinement are deferred.
- Invitations, member visibility and immediate Owner/Admin suspension are the minimum administration closure. Removal/resignation and full departure remain deferred; future Viewer access will be Matter-scoped only after its separate contract is implemented.
- Follow the ordered packets recorded in the [decision](../../decision-history/2026-09-14-first-production-release-scope.md#confirmed-user-decisions). This scope decision does not authorise provider configuration or production deployment.

### September review corrections and execution scope

- Use one implementation task and one active code writer; no parallel implementation worktrees are required. Bounded context-free helpers and risk-appropriate independent QA follow the delivery workflow. Complete one selected outcome-sized packet and stop; a later explicit continuation selects the next packet after reconciliation.
- D01/D02 precede a release claim: establish reproducible build/type/CI checks and close actual Viewer, note-author and directory-privacy bypasses across actions and database grants/policies. Existing foundations do not excuse unsafe legacy consumers.
- D03 records one enforced release matrix for routes, roles, signup, Wiki/Brief generation, development Usage, retention/purge, and workers. Disable unsupported entry points at the authority boundary, not merely in navigation. Preserve test-environment usage aggregation without exposing it to ordinary production tenant members.
- The pilot uses the approved automatic 30/60/90-day Trash policy. At the exact retention deadline, ordinary access and Restore end before asynchronous physical cleanup. One daily sweep at midnight `Asia/Kolkata` selects all due/overdue purges; only actual failures create bounded retries. The pilot does not surface the 24-hour Team-attention item; that presentation is parked with the future Today/Dashboard design.
- D04/D05 include direct private upload with the lifecycle plan's bounded in-session TUS resumption and **Attach PDF** to metadata-only records. PDF replacement/version-management UI is deferred. Existing historical access and immutable citation identity remain protected; later replacement requirements elsewhere are not pilot UI acceptance.
- D06–D11 close actual Hub/Workbench state, typed Review and Task projection, matter identity/Restore, move/copy, bounded reads and overdue visibility. An unsafe deferred mutation is disabled until its canonical replacement passes; deferring its full UI never leaves a bypass enabled.
- The document journey, mandatory source-grounded extraction, read-only graph, verified-deadline slice and actual deployed release acceptance are the priority. Relationship suggestions are the highest-priority conditional and the last optional capability cut when time is demonstrably short; cited retrieval, Tasks/reminders and limited Financials are lower-priority conditionals. Brief, organisation-wide semantic Search, advanced administration, broad Realtime, bulk/non-PDF ingestion, demo/marketing and platform-console breadth remain deferred under their owning contracts.

### Shift from horizontal foundations to vertical slices

- The foundation-first order was correct through the completed document lifecycle and provenance authorities. Those contracts prevent the UI from cementing mutable files, raw AI metadata, unsafe assignment, or unreliable background work.
- Reconcile prior checkpoint evidence against current code, then implement a pilot-first vertical sequence. A packet should normally end in an observable workflow increment, including its schema, server projection/command, UI, focused tests, and browser QA.
- Database, server, service, and UI boundaries remain separate in code and review, but they are delivered together per pilot capability rather than completing each layer portfolio-wide.
- No completed safety contract is rolled back or bypassed for speed. Pilot acceleration comes from narrowing scope and disabling unfinished capabilities.

### Pilot audience and operating envelope

- The pilot is one design-partner organisation with a small preauthorised user group and PDF-only source documents hosted through the production application URL.
- Signup follows the September 10 normal create-or-join decision: verify email, then offer organisation creation and pending invitations for that account. Creation atomically establishes the first Owner/Admin through the application. Prior invitation or manual internal provisioning is not required; one-membership and invitation security contracts remain. Production expansion still requires its owning operational gates.
- The internal rehearsal environment uses synthetic or sanitised representative documents. It is not sent as the client deliverable and contains no confidential client records or production credentials.
- The client handoff is a controlled confidential-data production pilot. It requires passing the release gate in this plan and begins with manual support, bounded storage/model quotas, and a documented incident path.
- The pilot organisation begins with `manual_suggestions` as its initial document-placement policy. Global uploads remain in Intake for a human assignment decision unless an Owner/Admin later makes an explicit, audited opt-in to an approved automatic mode after its evidence-quality gate passes; matter-context uploads retain the user's declared destination.
- Preserve the 25 MiB per-file default. Configure a reviewable 350 MiB unique-asset entitlement for the pilot organisation, subject to verified hosting capacity, so the supplied 201.7 MiB corpus has bounded room for processing, replacements, and incremental testing. The entitlement is trusted server configuration, not a browser constant.
- Written pilot terms must identify the authorised data set, permitted users, support path, retention/deletion procedure, and the client's authority to provide the litigation documents for processing.
- AI-derived consequential facts remain provisional or Review-gated. The pilot does not silently make unverified deadlines, amounts, legal conclusions, or relationships authoritative.
- The pilot has no agents, autonomous legal workflows, generated answers, workspace-wide memory, Note/chat distillation, or AI-maintained Case Brief. If its conditional embedding feature ships, it is limited to cited retrieval over meaningful chunks from current PDF versions, normally scoped to one Matter.
- Governed automatic purge is part of the pilot. Its secure exact-expiry readers, legal-hold/blocker handling, asynchronous cleanup, content-safe failure visibility and selected cost-bounded scheduler must pass release acceptance; no legacy hard-delete path is exposed.

### Pilot product contract

The first confidential-data pilot includes:

- a production application URL with production authentication redirects, verified-email signup, normal create-or-join onboarding, pending invitations, and one-organisation membership enforcement;
- production email delivery for verification, invitation, and mandatory security messages using a configured provider rather than local/default development mail behavior;
- a minimal Team/member view sufficient to understand access and invite the approved pilot users;
- client and matter navigation using secured organisation-scoped projections;
- global Inbox and matter PDF upload through canonical Intake, validation, duplicate detection, placement, and durable processing;
- one shared Document Workbench for authorised current-version PDF preview and effective-metadata inspection;
- human Review for material extraction, placement, duplicate, and recovery exceptions;
- a bounded Matter workspace containing stable identity, chronology/list, a truthful read-only graph, Files, Details, manually verified legal deadlines and Activity needed to find and reopen pilot documents;
- source-grounded structured PDF metadata extraction with evidence, approved acquisition/quality gates, typed Review and a complete manual correction/fallback path;
- visible processing/failure/retry states with a manual recovery path;
- a verified backup and recovery mechanism appropriate to the selected production tier, explicit private-Storage coverage/limitations, client retention of recoverable originals, a tested source-unavailable state, minimal operational monitoring, and a release runbook;
- lightweight internal usage measurement: unique asset-byte history, storage classes, processing pages/provider units, embedding chunk/vector counts and cost, safe feature outcomes, and aggregate provider reconciliation. Egress, CPU, memory, tokens, and vectors are not itemised to the pilot client;
- production deployment and rollback procedures for the Next.js application, Supabase migrations/configuration, Trigger workers/schedules, Vertex configuration, secrets, and environment-specific feature flags.

The first pilot treats these as conditional enhancements, included only if their own gates pass without consuming stabilisation. Relationship suggestions are attempted first and cut last among optional capabilities:

- governed human relationship editing/correction and relationship suggestions with contextual typed Review;
- owned Tasks, Notes-to-Task creation, reminders and limited Financials;
- bounded Matter/Current-document hybrid retrieval over current PDF chunks, with exact page citations and lexical/structured fallback and no generated answer or additional embedded content families.

The first pilot explicitly defers:

- organisation-wide semantic Search, embedding additional content families, saved-search breadth, cited-answer experiments, and every agent/intelligence layer beyond matter-scoped cited document retrieval;
- Today, complete My Work/Tasks, notification digests, and nonessential notification channels;
- every Case Brief route/generation/refresh until the required product rethink, plus full Notes migration;
- authoritative deadline and financial automation beyond manually verified existing capability;
- the deferred 24-hour Trash attention card in the future Today/Dashboard and advanced Trash administration beyond the approved retention/purge workflow;
- the complete Platform Operations console, billing-like usage presentation, and advanced operator configuration;
- broad Realtime rollout, external spreadsheet/GST acquisition, and non-PDF ingestion;
- public landing-page, portal, or marketing refinement that does not block pilot entry.

### UI concept work

- A separate design task may refine pilot layouts while backend work continues, but it follows the same canonical plans and Civic Ink contract.
- Concepts are produced in pilot dependency order: Document Hub/Workbench and Review first; Team/onboarding second; Matter shell, chronology, Files, and Details third. Deferred feature concepts do not consume the pilot critical path.
- Existing approved concepts for Matter Workspace and Deadlines/Financials remain references. They are not reopened unless implementation evidence exposes a concrete conflict.
- Concept work stays in `/dev` routes and plan/portal references until human visual approval. Parallel tasks must use an isolated worktree or coordinate exact files so they do not collide with production implementation or unrelated landing-page changes.
- Production UI implementation begins only from an approved concept or an already-settled shared design-system pattern. Desktop and mobile are designed and accepted together.

### Quality and release boundaries

- Independent implementation/QA separation remains mandatory for security, migration, async, and client-facing workflow packets.
- Focused checks run while implementing a packet. Independent QA runs its complete packet acceptance once against the exact commit. One broad release-candidate pass covers clean database replay, SQL acceptance, TypeScript, lint, production build, browser workflows, accessibility, responsive layouts, and cross-tenant denial.
- Internal pre-production rehearsal may begin before production recovery configuration because it contains no confidential records and is not a client handoff. The production link cannot be given to the design partner until the selected database-plus-Storage recovery boundary, client-original/object-loss statement, missing-object behavior, and the remaining confidential-data gates pass.
- Weekly agent quota affects calendar dates, not acceptance criteria. If capacity is exhausted, the team pauses at a committed checkpoint and uses the wait for manual concept review, fixture preparation, and partner feedback.
- A production URL or successful signup screen is not release evidence by itself. The exact upload-to-reopen journey, selected backup/recovery verification, missing-object behavior, and documented recovery boundary must pass in the deployed environment before the link is given to the client.

`Confidential-data gate passed` means evidence exists for the exact deployed revision and configuration—not merely planned code—that: signup/invitation and tenant/role/direct-ID denial hold; private upload, duplicate/retry/recovery and exact source reopening work; suspension revokes access; enabled AI is source/version-fenced and human-reviewable with a manual fallback; secrets and logs disclose no client content; the selected database-plus-Storage recovery boundary has been restored successfully; monitoring and rollback are operable; and the client data/users/purpose/retention/originals boundary plus named incident responsibility are recorded. If any required item fails, use synthetic staging only and do not accept confidential PDFs.

## Implementation Plan

### 0. Reconcile the current checkout and close release blockers

1. Read the current handoff, ledger, Git status and recent commits. Preserve unrelated work and determine which old assignment/effective-metadata checkpoints have already been superseded. Establish current build/type/test evidence; do not reimplement or QA an obsolete commit merely because it remains in this narrative.
2. Confirm the document inspector and assignment path consume the bounded current-version effective projection needed by the pilot. Do not continue to deadlines, financials, relationships, prompt evaluation, or multi-index Search merely because they are next in the full AI plan.
3. Preserve unrelated landing-page and organisation-concept work without including it in pilot commits.
4. Repair the application/worker import boundary, deterministic generated-type/refinement pipeline and enforced pre-deployment checks, then close the live authorization paths in D02/D03. Record checks not run and remaining baseline debt; no green status is inferred from source-only tests.

### 1. Freeze the pilot journey and fixtures

1. Record the exact enabled routes, roles, signup/invitation contract, feature flags, disabled consequential actions, supported PDF/storage limits, manual support path, and internal-versus-production data policy.
2. Create a small synthetic/sanitised release fixture set covering normal/direct resumable upload, first attachment, duplicate, malformed/encrypted PDF, intended-matter assignment, global placement, AI exception, current source and existing historical-link integrity, worker retry, revoked access, and long-content/mobile states. Replacement UI is not required.
3. Maintain the supplied 311-PDF corpus outside the repository as an authorised local evaluation input. Generate only content-free aggregate/run manifests with opaque IDs; do not commit documents, filenames, extracted text, legal references, prompts, or per-document provider errors.
4. Establish a release checklist and CI command that runs migration uniqueness, clean local reset and SQL acceptance, focused application tests, type checking, lint, and production build without deploying.

### 2. Complete pilot identity and entry

1. Preserve the verified Organisation Administration identity/RBAC and hash-only invitation authority.
2. Implement the minimum production Team, verified-email signup/invitation-return, no-membership, suspended/removed, and account-menu/onboarding UI needed by the pilot. Include the approved 30/60/90-day Trash retention setting while keeping advanced offboarding, notification preferences, and full organisation policy outside this tranche.
3. Verify every pilot role through UI, loader, command/RPC, direct-ID, signed-file, and cross-tenant tests.
4. Configure and verify the production site URL, allowed authentication redirect URLs, invitation links, email provider, cookie/security settings, and non-disclosing failed/expired invitation behavior.

### 3. Establish the human-decision spine

1. Implement the minimum canonical Activity and Review foundations required by document processing, placement, duplicate, and recovery exceptions. Do not build complete Tasks, Today, digests, or broad notification delivery yet.
2. Build the Review list/detail and evidence handoff needed to inspect and resolve pilot exceptions on desktop and mobile.
3. Ensure a clean extraction creates no gratuitous Review item, while material or conflicting AI output cannot become authoritative without the approved decision.

### 4. Deliver the primary Document Hub and Workbench slice

1. Build canonical loaders/routes and the shared current-version Workbench foundation: authorised PDF preview, stable toolbar, effective-metadata inspector, processing/provenance state, and Review handoff.
2. Rebuild the pilot Document Hub queue around canonical Intake with upload picker/drop, durable rows, stable filters/selection, Placement, discard only where safe, failure/retry state, and mobile detail navigation.
   Reuse the reserved direct-private-storage transport for global, matter and first-attachment entry points. Prove valid-empty refresh, late source-request fencing, bounded reads, explicit selected version/metadata context and actual 320px/360px viewer behavior.
3. Remove or disable the modal/raw-metadata/legacy viewer and misleading `Sync` or broad reevaluation actions only after equivalent pilot capability passes.
4. Run complete desktop/mobile/browser/accessibility QA on the upload-to-review-to-placement-to-reopen journey.

### 5. Deliver the pilot Matter workspace slice

1. Implement the secured Matter shell projection, compact stable chrome, URL-addressable sections, capability-aware primary actions, and explicit scroll ownership.
2. Build chronology/list before the procedural graph. Add the Files list/table, Workbench handoff, compact Details, and matter-filtered Activity needed for the pilot.
3. Retain or clearly label existing deferred sections only when they cannot corrupt canonical state. Hide capabilities that imply unimplemented authoritative automation.
4. Retain chronology and the accepted read-only graph as mandatory. Attempt the conditional relationship suggestion and typed Review scope before lower-priority optionals, and cut it only when current schedule evidence shows it would threaten mandatory acceptance or stabilisation; defer Case Brief, full Notes, broad Financials and broad Realtime.
5. Implement the approved private version-bound page-text/OCR artifact and mandatory source-grounded metadata extraction with review-by-exception plus an exceptional manual recovery path. Implement the changed-content chunk writer and matter/current-document hybrid retrieval only if conditional-feature budget remains; cut retrieval before the core release if its page-citation, tenant/current-version/Trash, lexical-fallback, relevance, latency or cost gates are not ready.

### 6. Establish production hosting and rehearse internally

1. Create separate pre-production and production application environments with explicit Supabase, Storage, Trigger, Vertex, email, secrets, redirect, feature-flag, and operator configuration. The current repository has a migration workflow and project-portal deployment, but no complete application deployment/release pipeline; add and verify that boundary before client handoff. Before deploying Trigger workers, complete the Platform Operations Node 24 runtime-alignment prerequisite, deploy the worker version without promotion, exercise every pilot task/schedule and rollback path, and only then promote it.
2. Deploy the release candidate to pre-production with only synthetic or sanitised fixtures. Exercise signup/invitation, upload, processing visibility, Review, placement, Workbench, Matter reopening, failure, retry, revoked access, and mobile/desktop flows.
3. Run the authorised local 311-PDF corpus through a bounded pre-production-like evaluation only after its data-handling destination is explicitly approved. Record aggregate success/failure, latency, provider usage, duplicate, validation, page-count, and Review rates without content-bearing logs. Do not bulk-upload the corpus to production merely to prove throughput.
4. Promote only the exact verified release revision and migrations to production. Verify rollback, health checks, authentication links, workers/schedules, and one synthetic canary before inviting the client.

### 7. Complete confidential-data pilot operations

1. Implement the minimum Platform Operations subset required before client handoff: the 350 MiB pilot organisation entitlement, platform/storage guard verification, model limits, safe job health and failure visibility, trusted operator/runbook access, content-safe logs, and critical alerts.
2. Apply the production hosting/backup decision from the go-live runbook. If Supabase Pro is selected, verify its managed restore points and the Storage exclusion. If Supabase Free is selected, production cannot open until scheduled off-site database dumps and private Storage copies are encrypted, monitored and restore-tested. In either case, make client retention of recoverable originals part of the written pilot boundary and exercise explicit missing-object behavior plus an exact-hash rehydration-match fixture without claiming bulk/automatic rehydration.
3. Record material organisation usage events and daily aggregates for unique asset storage, storage lifecycle classes, processing pages/provider units, embedding chunks/vectors, and safe feature outcomes. Snapshot aggregate provider usage for reconciliation; keep raw request/memory telemetry in provider observability and do not invent per-tenant egress billing.
4. Remove or disable legacy tenant-global Usage/service-role browser surfaces and every exposed destructive path that has not reached its canonical authority.
5. Run the release-candidate test matrix, production migration rehearsal, secrets/configuration review, rollback rehearsal, and owner sign-off.

### 8. Hand over the production link and begin the controlled pilot

1. After release approval, provide the production URL. The first client signs up, verifies the address and creates the organisation through the normal flow; subsequent members can accept invitations shown during onboarding. Complete one guided canary upload before broader original-PDF testing.
2. Onboard the design partner with explicit supported workflows, known deferred capabilities, manual Review policy, storage/model limits, support channel, retention/deletion procedure, and incident procedure.
3. Monitor every upload/processing failure, Review exception, signed-file denial, quota alert, managed-backup status, search-index failure, and unusual usage pattern during the initial observation window.
4. Expand enabled capabilities only through verified canonical tranches. Do not equate partner demand with permission to bypass source, authorisation, migration, or recovery contracts.

### 9. Resume the broader portfolio after the pilot gate

Resume in this order, adjusted by observed partner value:

1. Complete Tasks/My Work/Today and notification preferences around the established Activity/Review spine.
2. Complete Document Hub relationships, quotations, historical-version navigation, and remaining Workbench capability.
3. Expand Matter Workspace with the reviewed procedural graph and relationship decisions.
4. Expand verified Deadlines/Financials and Notes against shared evidence and Work contracts. Reconsider Case Brief only after its required product discussion revises the canonical direction.
5. Expand the verified matter-scoped document retrieval into organisation-wide Search only if pilot relevance, citation, latency, cost, and user-value evidence supports it; add other content families separately rather than embedding the workspace indiscriminately.
6. Implement selective Realtime for the completed consumers.
7. Expand the pilot's approved Trash/retention/purge and minimum job visibility into the full Platform Operations console before broader rollout.
8. Plan External Acquisition and Imports only after representative client spreadsheets are supplied.

## Interfaces and Data Changes

- Add a pilot release manifest or equivalent typed configuration identifying enabled routes/capabilities, pre-production/production environment, disabled destructive actions, supported limits, authorised pilot organisation, and release revision. It must not be a browser-authoritative permission mechanism.
- Add a release checklist/command that composes existing migration, database acceptance, application, build, and browser checks without deploying.
- Reuse existing `DomainCommandResult`, `ActivityEvent`, `OutboxEvent`, `ReviewItem`, provenance, source-locator, membership/capability, Intake, document-version, and processing-run contracts.
- Do not create pilot-only data models, page-local state machines, alternate PDF viewers, direct storage-path interfaces, or duplicate Review/Activity tables.
- Pre-production and production use separate environment/data policies. Confidential documents are processed only in an explicitly authorised destination and are never copied into public demos, repository fixtures, logs, portal assets, or screenshots.

## Testing and Acceptance Criteria

### Internal pre-production rehearsal

- The deployed direct-upload path accepts the configured 25 MiB PDF without sending its bytes through an application-host function request. Interrupted transfer, reload/reselection, revoked access, cancel/finalize and response-loss behavior match the lifecycle contract.
- First attachment preserves document identity and human metadata; matched metadata never merges distinct documents automatically. Existing quotes/historical links remain source-specific. Replacement UI is absent.
- The reviewed legacy defects are closed or their unsafe entry points are denied: valid-empty Hub refresh, wrong-source race, generic Review dismissal, stale Task Review rows, same-client/year Matter/Restore identity, non-atomic Move/Copy, and hidden overdue dates. Every enabled path has its ledger evidence.

- A test user can sign up through the deployed pre-production URL, create an organisation or accept a pending invitation, and complete the exact supported journey: open/create a matter, upload a representative synthetic/sanitised PDF through matter upload or global Inbox, observe truthful processing state, inspect or resolve a Review exception, place the document, open the exact current version in Workbench, and reopen it from the Matter workspace.
- The journey works with keyboard-only use and at desktop and phone widths without hidden primary actions, page-level horizontal overflow, nested-scroll traps, inaccessible status, or loss of context.
- Synthetic duplicate, malformed/encrypted PDF, processing failure, and revoked-access scenarios show bounded actionable states and cannot corrupt canonical document or AI state.
- Disabled or deferred capabilities are absent or explicitly labelled; no control claims automation, deletion, search quality, or authoritative AI behavior that is not implemented.
- If conditional cited retrieval is enabled, Matter/current-document submitted search combines exact/full-text/structured retrieval with at most one query embedding, returns the judged source passage with the immutable PDF page, and still works lexically when the embedding provider fails. Typing creates no paid embeddings; unchanged chunks are not rebuilt.
- No confidential client data, production credentials, or external production mutations enter the ordinary rehearsal fixture environment.
- The optional authorised corpus run reports aggregate validity, processing completion, Review, duplicate, latency, and usage outcomes for all 311 PDFs without emitting document content or filenames and without exceeding configured concurrency/provider limits.

### Production confidential-data pilot

- The production URL, verified-email signup, invitation acceptance, authentication redirects, email delivery, one-organisation membership, cookie/session behavior, and suspended/removed denial work from a clean browser session.
- Clean database replay, all pilot SQL acceptance suites, focused/unit tests, TypeScript, changed-file lint, production build, migration/schema checks, and the full guided browser journey pass from the release candidate.
- Cross-tenant, role, inactive-membership, direct-ID/RPC, signed-file, asset/version, Intake, Review, and Workbench tests fail closed.
- Upload/retry/replay tests prove one canonical asset/version and no duplicate model call, placement, Activity, Review, or processing side effect.
- A clean organisation and an unset/backfilled policy both keep global uploads manual by default. Automatic placement cannot occur until an Owner/Admin explicitly saves an approved mode, and reverting to manual affects future unassigned Intake without moving documents already assigned.
- AI output is schema-validated and source/version fenced; material or conflicting facts remain provisional or Review-gated, and the pilot makes no unsupported legal-answer claim.
- Only the governed Owner/Admin permanent-delete path and approved automatic retention workflow can purge. Exact expiry ends ordinary access before physical cleanup, legal holds/blockers fail safely, and no legacy hard-delete path remains.
- The selected database and Storage backup boundary is exercised through a restore drill and stated plainly. Missing-object access is explicit, preserves metadata/hash identity, and the pilot terms confirm that the partner retains recoverable originals; the release makes no recovery claim that its actual evidence cannot support.
- Job failures, backup/restore evidence failure, storage/model limits, enabled indexing failures, and provider outage create visible operational signals without logging legal content, filenames, prompts, signed URLs, paths, raw queries, or secrets.
- Usage measurement reconciles provider totals without claiming exact tenant allocation. Daily storage aggregates distinguish active, history, Trash, and Intake; AI/indexing records actual provider units where available; raw per-request memory/CPU and clickstream data do not enter the transactional database.
- The production pilot organisation accepts the complete supplied corpus within the approved 350 MiB entitlement while preserving the 25 MiB per-file boundary; quota exhaustion fails safely before upload and never triggers deletion.
- The design partner receives the supported-scope statement, data handling boundary, known deferred-capability list, support contact, and incident/rollback procedure before confidential documents are uploaded.

### Pilot success signal

- The partner completes the primary journey without engineering intervention for ordinary success cases.
- Every intervention required during the observation window is classified and reproducible; no P0/P1 tenant-isolation, evidence-loss, silent-stale-write, unrecoverable-upload, misleading recovery-boundary, or backup-status defect remains open.
- Workflow feedback can be mapped to an existing canonical domain or a deliberately proposed plan change; the pilot does not create undocumented architecture.

## Assumptions

- The design partner expects a production URL and normal self-service signup, followed by verified-account organisation creation or invitation acceptance. No manual first-owner setup is assumed.
- The initial confidential pilot is deliberately small, closely monitored, and limited to PDF workflows already governed by the canonical document and provenance contracts.
- The client has authority to provide the original litigation PDFs for testing; that authority, permitted processing purpose, retention, return/deletion, and user list will be confirmed before production upload.
- The weekly Codex quota may pause implementation. Timeline commitments use active engineering ranges plus the account's displayed reset date rather than assuming uninterrupted execution.
- Existing POC functionality may remain behind compatibility routes only when it cannot bypass canonical write, permission, evidence, or lifecycle contracts.
- The production hosting environment, credentials, selected Supabase tier, backup destination/key where required, and operator identities require explicit user-authorised setup before client handoff. A Free-tier production choice makes independently tested database and Storage recovery a first-client gate rather than a later expansion gate.

## Open Questions

None.
