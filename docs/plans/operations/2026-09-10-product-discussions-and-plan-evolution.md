---
title: Product Discussions and Plan Evolution
status: approved
created: 2026-09-10
updated: 2026-09-10
owners:
  - product
  - engineering
related:
  - ./2026-09-08-agent-delivery-workflow.md
  - ./2026-08-29-design-partner-pilot-execution-sequence.md
---

# Product Discussions and Plan Evolution

## Summary

Support short product discussions starting with an agent-suggested topic or the user's idea. Connect discussion to plans and code, record agreed changes, and expose resulting implementation work. Reuse the existing documentation roles; no new project database, orchestration service, mandatory skill or daily transcript.

This workflow was accepted under the user's September 10 delegation for non-critical execution/documentation recommendations; see the [decision record](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md#non-critical-october-recommendations-accepted). It does not approve product scope. The [discussion prompt](../../planning-prompt.md) is available for use; actual product decisions and implementation authority remain governing.

## Context and Goals

Plans, ledger, evidence, decisions and handoff already exist. Coarse plan/outcome statuses do not enumerate every capability, and historical passes may precede changed requirements. The user should understand a topic's intent, implementation and evidence, then leave a traceable decision or open question. Do not force a decision merely to produce a finalized plan.

## Decisions

### Two discussion paths

- **Suggest a topic:** read the release scope and compact decision/ledger indexes. Offer at most three opportunities with benefit, why now, existing coverage and likely rework. Include creative opportunities, not only blockers. Search titles/headings broadly; deep-read the selected topic.
- **Develop an idea:** identify the intended benefit and overlapping contracts/callers. Explain whether it already exists, enhances existing work, conflicts or adds a domain. Critique it and offer concrete alternatives. An idea is not automatically an approved implementation instruction.
- Begin with a compact picture of the workflow, dependencies, current code/evidence and actual decision. Use a realistic example or visual when useful.
- A normal discussion allocates roughly five minutes to context, fifteen to alternatives, five to consequences and five to decisions. This aids focus, not forced closure. Ask only material questions.

### One owner for each kind of information

| Information | Canonical location |
| --- | --- |
| Intended behaviour, interfaces and acceptance | Relevant `docs/plans/` file |
| Current delivery state, dependencies and active card | `docs/delivery-ledger.md` |
| Tested revision, environment, result and gaps | `docs/delivery-evidence/` |
| Material user decision, rationale and superseded choice | `docs/decision-history/` |
| Decision that actually blocks execution | `docs/approval-based-blockers.md` |
| Worthwhile unfinished exploration | One topic file in `docs/discovery/`, only when needed |
| Implementation task/process/restart state | `docs/implementation-handoff.md` |
| Human and agent entry points | `docs/README.md` |

Discovery notes contain the user problem, relevant plan links, viable alternatives, unsettled question and next experiment. Reuse one topic file, normally 300–600 words. On resolution replace exploration with a short disposition and links, retaining alternatives only where they explain the decision. No transcripts, private reasoning, empty topic files or second backlog. The blocker queue links rather than copies a discovery note.

### Coverage and truthful progress

- Status lives in the ledger. Add a compact **Delivery coverage** map when discussing implementation: stable capability ID, exact requirement/acceptance anchor, owning outcome and evidence pointer. Do not maintain status twice.
- Map user capabilities, not every sentence. New receipts identify the relevant plan revision/date. Older receipts require relevant contract reconciliation, not blanket re-testing.
- Declare coverage `partial` until all implementation-bearing sections of the claimed scope are mapped. An unmapped section is unknown, never implicitly complete or deferred. Enumerate the selected release before claiming its acceptance; backfill unrelated domains only when needed.
- Preserve ledger states `planned`, `building`, `review`, `integrated`, `deployed`, `deferred`. Blocking dependencies and changed requirements are separate fields. Missing acceptance remains `review`; integration is not deployment.
- Report scope, accepted capabilities, current work, missing verification and blockers. Never derive app-completion percentages from commits, plan counts or a partial denominator. Portal views must derive status from these sources rather than maintain separate totals.

### Changed requirements after implementation

1. Distinguish exploration, decision-complete proposal and actual approval. Preserve the approved contract until the user chooses the replacement.
2. Inspect affected sections, callers and receipts. Classify impact as no code change, new work, adaptation, replacement/removal or re-verification. Explain reuse and rework cost.
3. Revise agreed requirements in place. Record one concise material decision with date, reason, replaced choice and affected outcome IDs. Do not append competing specifications.
4. Preserve old passing receipts as evidence of the old requirement. Reopen affected ledger acceptance with the new requirement and checks. Reuse an ID for the same outcome; allocate a new one for a distinct outcome.
5. If current implementation is affected, record the changed scope for reconciliation at its next checkpoint. Verify actual task state before claiming coordination. Do not automatically message, interrupt or restart another task without authority. A stopped task stays stopped.
6. Close the change only after code and relevant fresh acceptance. Documentation cannot satisfy an application requirement.

### Bounded reading and maintenance

Use heading search and complete relevant section reads, including shared invariants. The selected domain, required dependencies, current ledger entry and relevant evidence are the normal reading set, not the whole archive.

Replace obsolete wording. Keep rationale compact; decisions and Git preserve meaningful history. Split a long plan only at independently owned capability boundaries with distinct interfaces/acceptance, retaining a parent map/shared invariants and updating links/index/portal. Word count alone does not justify fragmentation.

Update only affected files at discussion close. A small change may need only the plan; a material change normally also needs a decision and ledger entry. Update handoff only when restart/ownership changes. No daily report, per-agent tracker or compulsory full-doc review. Create a small optional skill later only if selection/discoverability would help; it must point to this workflow rather than duplicate it.

### Environment boundary

Use the [current pre-pilot decision](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md). Disposable legacy test data does not remove intended tenancy, security or evidence-integrity contracts. Record the user-declared real-client cutover before further data-affecting delivery. Verify the actual target at execution time; an environment file does not prove running or remote configuration.

## Implementation Plan

1. Add the discussion prompt and documentation routes.
2. Extend the plan template with coverage guidance and apply it to the discussed Organisation scope.
3. Remove stale claims/duplicate summaries without rewriting evidence history.
4. Exercise both discussion paths in ordinary use and refine only where concrete friction appears.

## Interfaces and Data Changes

Documentation only. Links connect plans, existing outcome IDs and receipts. No application schema, database reset, scheduler, implementation task or installed skill.

## Testing and Acceptance Criteria

- Both paths locate overlap and distinguish intended, implemented and verified behaviour.
- An undecided idea can be parked without becoming approved scope.
- Requirement changes retain historical passes and expose new work.
- Unfinished exploration stays outside finalized plans; a read-only session returns an explicitly unsaved change packet.
- Links/index metadata agree. No duplicated current status, secrets, confidential fixtures or conversations are saved.
- Documentation work does not launch implementation or require application tests for prose edits.

## Assumptions

The user chooses product tradeoffs; agents own technical analysis and upkeep. Thirty minutes is the ordinary discussion window, not a limit. Saving requires a mode permitting file edits.

## Open Questions

None for this workflow. Product choices remain in their owning plans and decision queue.
