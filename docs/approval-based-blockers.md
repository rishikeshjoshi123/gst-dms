# Approval-based blockers

This is the short, human-readable queue for decisions that need review before a
tranche can safely continue. It prevents one approval boundary from stopping
the rest of the approved portfolio.

## How it works

- Add an **Open** entry when a user decision, visual review, external authority,
  or material policy choice blocks a tranche.
- State the plan, the exact decision, why it cannot be safely inferred, the
  recommended option, and the safe next action after approval.
- Update the open index whenever an entry changes scope or is resolved. The
  detailed entry and actual user decision govern if an index summary is stale.
- Record the affected delivery-ledger outcome/release gate, the task owning
  resumption, the user's actual decision and date, and the commit implementing
  that decision. Unknown owner/commit fields remain `unassigned`/`not implemented`.
- Check this queue at packet boundaries while a task is running. Editing the
  file does not wake a finished task; resume it with a message or the reusable
  implementation prompt. Settled technical repairs belong in the ledger.
- A blocked item does not authorise portfolio expansion. Inspect its approved
  prerequisites or alternatives within the selected objective, but complete
  only the current outcome-sized packet. Preserve explicit exclusions and do
  not treat this file as approval by itself.
- When the user resolves an entry, preserve its dated decision in
  `docs/decision-history/` and keep a short link under **Resolved**. Retain its
  canonical-plan link and implementation evidence; an approved decision is not
  proof that dependent implementation is finished. Preserve existing anchors.

## Open decision index

September 10–12 decisions resolve onboarding, Trash activation, departure/removal deferral, OCR thresholds, Matter identity and the Review visual gate. The September 14 [first-production release decision](decision-history/2026-09-14-first-production-release-scope.md) resolves the product boundary and packet order. Production ownership, compliant hosting/recovery and incident response remain open below; implementation and deployment acceptance remain separate.

Read this index at startup and the affected entries below. Detailed history is under [Resolved](#resolved); read a dated record only when its decision is relevant.

- [2026-09-14 — Production go-live ownership, hosting, recovery and incident response](#2026-09-14--production-go-live-ownership-hosting-recovery-and-incident-response)

## Open

### 2026-09-14 — Production go-live ownership, hosting, recovery and incident response

**Status:** Open; priority brainstorming session requested by the user, with the production-environment/recovery portion targeted for October 1–2, 2026.

**Decision needed:** name go-live and rollback authority, production-account owners and backup operators, client support/incident responsibilities, the compliant application host, and the tested database-plus-Storage recovery mechanism for the chosen Supabase tier.

**Why it cannot be inferred:** the user proposes zero-cost production services. Supabase Free has no automatic backups, so it does not satisfy the earlier managed-backup assumption without an independently scheduled and restore-tested alternative. Vercel Hobby documents a non-commercial-use restriction that may not cover a business design-partner deployment. No named operator, sign-off, support or incident authority has been selected.

**Recommendation:** use the [priority ownership discussion](discovery/production-go-live-ownership-and-incident-response.md) and separate [environment/recovery options](discovery/production-environment-and-recovery-options.md) session to produce a small responsibility matrix and runbook. Select a compliant host; either use a tier with verified managed database recovery or implement encrypted scheduled database and private-Storage copies with a successful restore drill. Keep staging and production accounts, branches, secrets and data isolated.

**Affected outcome / gate:** D13 confidential-data release. Product implementation may continue within the September 14 scope, but no confidential production upload or provider/deployment action is authorised by this entry.

**Safe work while pending:** implement and verify the approved local release packets, build the staging/release checks and draft the runbook without configuring or mutating remote services. Use synthetic data until the production data boundary passes.

**Resume owner / action:** product owner completes the priority brainstorm, records the chosen authority/hosting/recovery boundary, then authorises the exact remote setup and deployed rehearsal separately.

## Resolved

### 2026-09-14 — First production release scope and packet order

[Recorded user decision](decision-history/2026-09-14-first-production-release-scope.md). The one-organisation confidential pilot targets October 12–15 with October 20 as the final date. It fixes the mandatory journey, both upload origins, read-only graph, verified deadlines, critical Review cases and mandatory gated extraction; classifies Tasks/reminders, relationship enhancements, cited retrieval and limited Financials as conditional; defers Dashboard/Today, Case Brief, organisation-wide semantic Search and other breadth; and fixes the ordered packet/cut rule. Production authority remains open above.

### WORK-REVIEW-CONCEPT-2026-09-01 — Review workspace direction

**Resolved 2026-09-12:** the user approved the iteratively refined fixture-only `/dev/review-workspace-concept`. [Recorded decision, approved UI contract, review friction, and resume conditions](decision-history/2026-09-12-review-workspace-concept-approval.md). D08 and the Review-dependent portions of D05/D11/D13 no longer wait for a visual decision, but their live typed producer/resolver, authority, concurrency, Activity, pagination, accessibility, integration, and deployment acceptance remain unimplemented. Task-reader repair remains independent.

### 2026-09-11 — Matter identity, document references, and extraction normalization

[Recorded user decision](decision-history/2026-09-11-matter-identity-and-extraction-normalization.md). One independently progressing/challengeable proceeding chain is one Matter regardless of how many periods it covers; client/financial year is not identity. D09-T01/T02 implement governed identifier authority and the creation/Restore cutover; D09-T03/T04 complete typed extraction observations. Bidirectional out-of-order matching, targeted reevaluation and shared-asset repair still require bounded implementation and acceptance.

### 2026-09-11 — OCR acquisition benchmark thresholds and page eligibility

[Recorded user decision](decision-history/2026-09-11-ocr-acquisition-benchmark-thresholds.md). The benchmark now has explicit critical-fact, routing, text-quality, latency, and OCR-cost gates. Reliable pages may proceed independently after the remaining Search gates; field-level human Review does not certify an unreliable full-page transcript. D12/D13 remain open for benchmark execution, implementation reconciliation, and deployed acceptance.

### 2026-09-11 — Pilot departure/removal deferral and foundation-first handover

[Recorded user decision](decision-history/2026-09-11-pilot-departure-removal-deferral.md). The pilot has neither member removal nor self-service resignation. D15 is deferred until CaseChain can show the Owner a complete, truthful responsibility inventory and atomically reassign every pending item before departure. The approved Team/departure visual concept remains a future implementation reference, not pilot scope.

### 2026-09-11 — Pilot Trash retention activation and logical expiry

[Recorded user decision](decision-history/2026-09-11-trash-retention-activation.md). The pilot uses automatic 30/60/90-day retention; ordinary access and Restore end at the exact recorded expiry before asynchronous cleanup. Physical purge uses one routine daily sweep at midnight `Asia/Kolkata`, with database-backed overdue recovery and failure-specific retries. The pilot does not surface the 24-hour Team-attention item, which is parked with the future Today/Dashboard design. Both the retention activation and scheduler-cadence approvals are resolved; implementation and deployed acceptance remain open in D03/D13.

### 2026-09-11 — Associate working access and internal expenses

[Recorded user decision](decision-history/2026-09-11-associate-working-access-policy.md). Associates receive ordinary legal-work capabilities, including shared intake, without a first-release feature-grant catalogue. Owner/Admin adds application administration; internal expenses retain the approved Matter-specific `view`/`edit` access. Confidential-Matter restrictions are parked for future discussion and are not current scope.

### 2026-09-10 — Pre-pilot data and normal onboarding

[Recorded user decisions](decision-history/2026-09-10-planning-and-pre-pilot-policy.md). D03/D13 require normal create-or-join implementation; prior restriction receipts are historical. No reset or implementation resumption occurred.

Dated receipts are preserved separately. Earlier links remain valid through these pointers. Read relevant decisions; old next-action text does not replace the current handoff.

### ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01 — Departure and Team impact workflow

**Resolved 2026-09-08:** the user approved the current revised concept. [Recorded decision and resume conditions](decision-history/2026-09-08-organisation-departure-team-concept.md). D15 may proceed when technical prerequisites are ready; its live implementation remains pending.

### 2026-09-08 — Source scope and single-task implementation workflow

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-08--source-scope-and-single-task-implementation-workflow).

### 2026-09-05 — Document Hub and Workbench concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-05--document-hub-and-workbench-concept).

### 2026-09-03 — Mumbai OCR processor promotion

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-03--mumbai-ocr-processor-promotion).

### 2026-09-01 — Independent backup destination for the design-partner release

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--independent-backup-destination-for-the-design-partner-release).

### 2026-09-01 — Search page-text source and first-release embedding scope

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--search-page-text-source-and-first-release-embedding-scope).

### 2026-09-01 — Page acquisition, English metadata, and India processing boundary

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--page-acquisition-english-metadata-and-india-processing-boundary).

### 2026-09-01 — Task comments workspace direction

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-comments-workspace-direction).

### 2026-09-01 — Task RPC organisation-selection authority

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-rpc-organisation-selection-authority).

### 2026-09-01 — Dedicated Tasks workspace concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--dedicated-tasks-workspace-concept).

### 2026-08-31 — Local browser QA authority for permanent-delete verification

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--local-browser-qa-authority-for-permanent-delete-verification).

### 2026-09-01 — Task and legacy note action-item compatibility

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-and-legacy-note-action-item-compatibility).

### 2026-08-31 — Trash permanent-delete concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--trash-permanent-delete-concept).

### 2026-08-31 — Retention for historical soft-deleted records

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--retention-for-historical-soft-deleted-records).
