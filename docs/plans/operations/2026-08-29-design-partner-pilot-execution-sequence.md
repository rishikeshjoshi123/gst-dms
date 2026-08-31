---
title: Design Partner Pilot Execution Sequence
status: proposed
created: 2026-08-29
updated: 2026-08-29
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
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
  - ../platform/2026-08-27-platform-operations.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Design Partner Pilot Execution Sequence

## Summary

Reorder implementation around a production-safe vertical slice for the first design-partner pilot without weakening the approved architecture or its independent QA standard. Complete the current effective-metadata assignment checkpoint, then move through identity, human Review, Document Hub/Workbench, a bounded Matter workspace, and pilot operations as one observable client journey instead of completing every database and service domain before returning to UI.

The client handoff is a production-hosted, invite-bound pilot: the design partner opens the production URL, signs up with a preauthorised email, verifies the account, enters the pilot organisation, and uploads original litigation PDFs. An internal pre-production rehearsal may use synthetic or sanitised fixtures, but it is not the promised client deliverable. The production pilot opens only after tenant isolation, durable document processing, human-reviewed AI, deployment, backup/restore, monitoring, and release acceptance pass. The broader canonical portfolio continues after the pilot gate.

## Context and Goals

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

### Shift from horizontal foundations to vertical slices

- The foundation-first order was correct through the completed document lifecycle and provenance authorities. Those contracts prevent the UI from cementing mutable files, raw AI metadata, unsafe assignment, or unreliable background work.
- After independent QA of `16b6bed`, implementation changes to a pilot-first vertical sequence. A tranche should normally end in an observable workflow increment, including its schema, server projection/command, UI, focused tests, and browser QA.
- Database, server, service, and UI boundaries remain separate in code and review, but they are delivered together per pilot capability rather than completing each layer portfolio-wide.
- No completed safety contract is rolled back or bypassed for speed. Pilot acceleration comes from narrowing scope and disabling unfinished capabilities.

### Pilot audience and operating envelope

- The pilot is one design-partner organisation with a small preauthorised user group and PDF-only source documents hosted through the production application URL.
- Signup is self-service from the client's perspective but invite-bound or email-allowlisted during the pilot. The user opens the link, creates and verifies the account, and completes the approved organisation invitation. Public unauthorised organisation creation is not part of this release.
- The internal rehearsal environment uses synthetic or sanitised representative documents. It is not sent as the client deliverable and contains no confidential client records or production credentials.
- The client handoff is a controlled confidential-data production pilot. It requires passing the release gate in this plan and begins with manual support, bounded storage/model quotas, and a documented incident path.
- Preserve the 25 MiB per-file default. Configure a reviewable 350 MiB unique-asset entitlement for the pilot organisation, subject to verified hosting capacity, so the supplied 201.7 MiB corpus has bounded room for processing, replacements, and incremental testing. The entitlement is trusted server configuration, not a browser constant.
- Written pilot terms must identify the authorised data set, permitted users, support path, retention/deletion procedure, and the client's authority to provide the litigation documents for processing.
- AI-derived consequential facts remain provisional or Review-gated. The pilot does not silently make unverified deadlines, amounts, legal conclusions, or relationships authoritative.
- Permanent purge and unattended destructive automation remain unavailable in the pilot. If hierarchy-aware Trash is not complete, destructive controls are removed or disabled and the limitation is explained; no legacy hard-delete path remains exposed.

### Pilot product contract

The first confidential-data pilot includes:

- a production application URL with production authentication redirects, verified-email signup, invite-bound organisation entry, and one-organisation membership enforcement;
- production email delivery for verification, invitation, and mandatory security messages using a configured provider rather than local/default development mail behavior;
- a minimal Team/member view sufficient to understand access and invite the approved pilot users;
- client and matter navigation using secured organisation-scoped projections;
- global Inbox and matter PDF upload through canonical Intake, validation, duplicate detection, placement, and durable processing;
- one shared Document Workbench for authorised current-version PDF preview and effective-metadata inspection;
- human Review for material extraction, placement, duplicate, and recovery exceptions;
- a bounded Matter workspace containing stable identity, chronology/list, Files, Details, and Activity needed to find and reopen pilot documents;
- visible processing/failure/retry states with a manual recovery path;
- daily encrypted database and private-object backup, a verified isolated restore rehearsal, minimal operational monitoring, and a release runbook;
- production deployment and rollback procedures for the Next.js application, Supabase migrations/configuration, Trigger workers/schedules, Vertex configuration, secrets, and environment-specific feature flags.

The first pilot explicitly defers:

- the final semantic/page-aware Universal Search rollout and cited-answer experiments;
- the full procedural graph and advanced relationship automation;
- Today, complete My Work/Tasks, notification digests, and nonessential notification channels;
- the cited Case Brief overhaul and full Notes migration;
- authoritative deadline and financial automation beyond manually verified existing capability;
- full hierarchy-aware Trash UI, automatic retention/purge, and permanent purge;
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

- Independent implementation/QA separation remains mandatory for security, migration, async, and client-facing workflow tranches.
- Focused checks run per tranche. One broad release-candidate pass covers clean database replay, SQL acceptance, TypeScript, lint, production build, browser workflows, accessibility, responsive layouts, and cross-tenant denial.
- Internal pre-production rehearsal may begin before backup/restore is complete only because it contains no confidential records and is not a client handoff. The production link cannot be given to the design partner until backup/restore and confidential-data gates pass.
- Weekly agent quota affects calendar dates, not acceptance criteria. If capacity is exhausted, the team pauses at a committed checkpoint and uses the wait for manual concept review, fixture preparation, and partner feedback.
- A production URL or successful signup screen is not release evidence by itself. The exact upload-to-reopen journey and recovery/restore gates must pass in the deployed environment before the link is given to the client.

## Implementation Plan

### 0. Close the paused checkpoint

1. Independently QA `16b6bed` against the assignment/effective-metadata plan criteria, remediate defects, replace the WIP checkpoint with a verified follow-up, and update the AI plan/status ledger.
2. Confirm the document inspector and assignment path consume the bounded current-version effective projection needed by the pilot. Do not continue to deadlines, financials, relationships, prompt evaluation, or multi-index Search merely because they are next in the full AI plan.
3. Preserve unrelated landing-page and organisation-concept work without including it in pilot commits.

### 1. Freeze the pilot journey and fixtures

1. Record the exact enabled routes, roles, signup/invitation contract, feature flags, disabled consequential actions, supported PDF/storage limits, manual support path, and internal-versus-production data policy.
2. Create a small synthetic/sanitised release fixture set covering normal upload, duplicate, malformed/encrypted PDF, intended-matter assignment, global placement, AI exception, replacement/current-version access, worker retry, revoked access, and long-content/mobile states.
3. Maintain the supplied 311-PDF corpus outside the repository as an authorised local evaluation input. Generate only content-free aggregate/run manifests with opaque IDs; do not commit documents, filenames, extracted text, legal references, prompts, or per-document provider errors.
4. Establish a release checklist and CI command that runs migration uniqueness, clean local reset and SQL acceptance, focused application tests, type checking, lint, and production build without deploying.

### 2. Complete pilot identity and entry

1. Preserve the verified Organisation Administration identity/RBAC and hash-only invitation authority.
2. Implement the minimum production Team, verified-email signup/invitation-return, no-membership, suspended/removed, and account-menu/onboarding UI needed by the pilot. Keep advanced offboarding, preferences, retention settings, and full organisation policy outside this tranche.
3. Verify every pilot role through UI, loader, command/RPC, direct-ID, signed-file, and cross-tenant tests.
4. Configure and verify the production site URL, allowed authentication redirect URLs, invitation links, email provider, cookie/security settings, and non-disclosing failed/expired invitation behavior.

### 3. Establish the human-decision spine

1. Implement the minimum canonical Activity and Review foundations required by document processing, placement, duplicate, and recovery exceptions. Do not build complete Tasks, Today, digests, or broad notification delivery yet.
2. Build the Review list/detail and evidence handoff needed to inspect and resolve pilot exceptions on desktop and mobile.
3. Ensure a clean extraction creates no gratuitous Review item, while material or conflicting AI output cannot become authoritative without the approved decision.

### 4. Deliver the primary Document Hub and Workbench slice

1. Build canonical loaders/routes and the shared current-version Workbench foundation: authorised PDF preview, stable toolbar, effective-metadata inspector, processing/provenance state, and Review handoff.
2. Rebuild the pilot Document Hub queue around canonical Intake with upload picker/drop, durable rows, stable filters/selection, Placement, discard only where safe, failure/retry state, and mobile detail navigation.
3. Remove or disable the modal/raw-metadata/legacy viewer and misleading `Sync` or broad reevaluation actions only after equivalent pilot capability passes.
4. Run complete desktop/mobile/browser/accessibility QA on the upload-to-review-to-placement-to-reopen journey.

### 5. Deliver the pilot Matter workspace slice

1. Implement the secured Matter shell projection, compact stable chrome, URL-addressable sections, capability-aware primary actions, and explicit scroll ownership.
2. Build chronology/list before the procedural graph. Add the Files list/table, Workbench handoff, compact Details, and matter-filtered Activity needed for the pilot.
3. Retain or clearly label existing deferred sections only when they cannot corrupt canonical state. Hide capabilities that imply unimplemented authoritative automation.
4. Defer the graph, advanced relationship review, Case Brief, full Notes, authoritative Deadlines/Financials, and broad Realtime until their later portfolio tranches.

### 6. Establish production hosting and rehearse internally

1. Create separate pre-production and production application environments with explicit Supabase, Storage, Trigger, Vertex, email, secrets, redirect, feature-flag, and operator configuration. The current repository has a migration workflow and project-portal deployment, but no complete application deployment/release pipeline; add and verify that boundary before client handoff.
2. Deploy the release candidate to pre-production with only synthetic or sanitised fixtures. Exercise signup/invitation, upload, processing visibility, Review, placement, Workbench, Matter reopening, failure, retry, revoked access, and mobile/desktop flows.
3. Run the authorised local 311-PDF corpus through a bounded pre-production-like evaluation only after its data-handling destination is explicitly approved. Record aggregate success/failure, latency, provider usage, duplicate, validation, page-count, and Review rates without content-bearing logs. Do not bulk-upload the corpus to production merely to prove throughput.
4. Promote only the exact verified release revision and migrations to production. Verify rollback, health checks, authentication links, workers/schedules, and one synthetic canary before inviting the client.

### 7. Complete confidential-data pilot operations

1. Implement the minimum Platform Operations subset required before client handoff: the 350 MiB pilot organisation entitlement, platform/storage guard verification, model limits, safe job health and failure visibility, trusted operator/runbook access, content-safe logs, and critical alerts.
2. Create daily encrypted logical database backup plus an independent encrypted copy of all private object bytes and a hash manifest. Complete an isolated restore rehearsal and retain safe evidence.
3. Remove or disable legacy tenant-global Usage/service-role browser surfaces and every exposed destructive path that has not reached its canonical authority.
4. Run the release-candidate test matrix, production migration rehearsal, secrets/configuration review, rollback rehearsal, and owner sign-off.

### 8. Hand over the production link and begin the controlled pilot

1. Send the production URL and invite/preauthorise the approved client email. The client signs up, verifies the address, joins the pilot organisation, and completes one guided canary upload before broader original-PDF testing.
2. Onboard the design partner with explicit supported workflows, known deferred capabilities, manual Review policy, storage/model limits, support channel, retention/deletion procedure, and incident procedure.
3. Monitor every upload/processing failure, Review exception, signed-file denial, quota alert, and backup result during the initial observation window.
4. Expand enabled capabilities only through verified canonical tranches. Do not equate partner demand with permission to bypass source, authorisation, migration, or recovery contracts.

### 9. Resume the broader portfolio after the pilot gate

Resume in this order, adjusted by observed partner value:

1. Complete Tasks/My Work/Today and notification preferences around the established Activity/Review spine.
2. Complete Document Hub relationships, quotations, historical-version navigation, and remaining Workbench capability.
3. Expand Matter Workspace with the reviewed procedural graph and relationship decisions.
4. Implement verified Deadlines/Financials and then Notes/Case Brief against shared evidence and Work contracts.
5. Complete Universal Search index-version rollout, page-aware chunks, deep links, shadow evaluation, and cutover.
6. Implement selective Realtime for the completed consumers.
7. Complete hierarchical Trash/retention/purge and the full Platform Operations console before broader rollout.
8. Plan External Acquisition and Imports only after representative client spreadsheets are supplied.

## Interfaces and Data Changes

- Add a pilot release manifest or equivalent typed configuration identifying enabled routes/capabilities, pre-production/production environment, disabled destructive actions, supported limits, authorised pilot organisation, and release revision. It must not be a browser-authoritative permission mechanism.
- Add a release checklist/command that composes existing migration, database acceptance, application, build, and browser checks without deploying.
- Reuse existing `DomainCommandResult`, `ActivityEvent`, `OutboxEvent`, `ReviewItem`, provenance, source-locator, membership/capability, Intake, document-version, and processing-run contracts.
- Do not create pilot-only data models, page-local state machines, alternate PDF viewers, direct storage-path interfaces, or duplicate Review/Activity tables.
- Pre-production and production use separate environment/data policies. Confidential documents are processed only in an explicitly authorised destination and are never copied into public demos, repository fixtures, logs, portal assets, or screenshots.

## Testing and Acceptance Criteria

### Internal pre-production rehearsal

- An invite-bound test user can sign up through the deployed pre-production URL and complete the exact supported journey: open/create a matter, upload a representative synthetic/sanitised PDF through matter upload or global Inbox, observe truthful processing state, inspect or resolve a Review exception, place the document, open the exact current version in Workbench, and reopen it from the Matter workspace.
- The journey works with keyboard-only use and at desktop and phone widths without hidden primary actions, page-level horizontal overflow, nested-scroll traps, inaccessible status, or loss of context.
- Synthetic duplicate, malformed/encrypted PDF, processing failure, and revoked-access scenarios show bounded actionable states and cannot corrupt canonical document or AI state.
- Disabled or deferred capabilities are absent or explicitly labelled; no control claims automation, deletion, search quality, or authoritative AI behavior that is not implemented.
- No confidential client data, production credentials, or external production mutations enter the ordinary rehearsal fixture environment.
- The optional authorised corpus run reports aggregate validity, processing completion, Review, duplicate, latency, and usage outcomes for all 311 PDFs without emitting document content or filenames and without exceeding configured concurrency/provider limits.

### Production confidential-data pilot

- The production URL, verified-email signup, invitation acceptance, authentication redirects, email delivery, one-organisation membership, cookie/session behavior, and suspended/removed denial work from a clean browser session.
- Clean database replay, all pilot SQL acceptance suites, focused/unit tests, TypeScript, changed-file lint, production build, migration/schema checks, and the full guided browser journey pass from the release candidate.
- Cross-tenant, role, inactive-membership, direct-ID/RPC, signed-file, asset/version, Intake, Review, and Workbench tests fail closed.
- Upload/retry/replay tests prove one canonical asset/version and no duplicate model call, placement, Activity, Review, or processing side effect.
- AI output is schema-validated and source/version fenced; material or conflicting facts remain provisional or Review-gated, and the pilot makes no unsupported legal-answer claim.
- No exposed browser action can permanently purge or invoke a legacy hard-delete path. A support procedure exists for mistaken uploads while canonical Trash is deferred.
- A complete encrypted backup set covers the database and every private object version. An isolated restore proves hashes, object availability, tenant isolation, memberships/capabilities, and the critical pilot projections.
- Job failures, backup failure/overdue state, storage/model limits, and provider outage create visible operational signals without logging legal content, filenames, prompts, signed URLs, paths, or secrets.
- The production pilot organisation accepts the complete supplied corpus within the approved 350 MiB entitlement while preserving the 25 MiB per-file boundary; quota exhaustion fails safely before upload and never triggers deletion.
- The design partner receives the supported-scope statement, data handling boundary, known deferred-capability list, support contact, and incident/rollback procedure before confidential documents are uploaded.

### Pilot success signal

- The partner completes the primary journey without engineering intervention for ordinary success cases.
- Every intervention required during the observation window is classified and reproducible; no P0/P1 tenant-isolation, evidence-loss, silent-stale-write, unrecoverable-upload, or backup/restore defect remains open.
- Workflow feedback can be mapped to an existing canonical domain or a deliberately proposed plan change; the pilot does not create undocumented architecture.

## Assumptions

- The design partner expects a production URL and self-service signup. During the controlled pilot, this means invite-bound or preauthorised-email signup rather than anonymous public organisation creation.
- The initial confidential pilot is deliberately small, closely monitored, and limited to PDF workflows already governed by the canonical document and provenance contracts.
- The client has authority to provide the original litigation PDFs for testing; that authority, permitted processing purpose, retention, return/deletion, and user list will be confirmed before production upload.
- The weekly Codex quota may pause implementation. Timeline commitments use active engineering ranges plus the account's displayed reset date rather than assuming uninterrupted execution.
- Existing POC functionality may remain behind compatibility routes only when it cannot bypass canonical write, permission, evidence, or lifecycle contracts.
- The production hosting environment, credentials, independent backup destination, and operator identities will require explicit user-authorised setup before client handoff.

## Open Questions

None.
