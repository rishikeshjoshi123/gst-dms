---
title: Single-Task Agent Delivery and Verification
status: approved
created: 2026-09-08
updated: 2026-09-08
owners:
  - product
  - engineering
related:
  - ./2026-08-29-design-partner-pilot-execution-sequence.md
  - ../platform/2026-08-24-product-architecture-portfolio.md
---

# Single-Task Agent Delivery and Verification

## Summary

One existing implementation task owns a durable goal, one code writer and sequential verified tranches across the approved portfolio. This is the canonical execution workflow. The reusable prompt grants execution authority; the [documentation map](../../README.md) routes supporting reads. Neither summaries nor plan approval prove working software.

## Context and Goals

The review found completed foundations alongside broken consumers, permission gaps and misleading completion claims. Delivery needs actual caller/acceptance evidence, bounded repair cost and continuity between tasks. Repeated instructions and historical logs should not dominate startup context.

## Decisions

### Task ownership and model routing

The task owner receiving the reusable prompt is the coordinator and keeps the user's selected model/reasoning setting. Sol/medium is a human recommendation, not a command to launch another coordinator. No additional user-owned tasks, worktrees or simultaneous writers. The coordinator owns selection, integration, commits and handoff.

| Assignment | Helper when useful |
| --- | --- |
| Clear bounded implementation | Terra/medium |
| Material UI, complex dependencies or architecture | Sol/high |
| Independent QA for security, migrations, asynchronous state, source identity or substantial workflows | Sol/high |
| Narrow repeatable QA | Luna/high; not sole reviewer of higher-risk work |
| Hard cross-domain boundary or persistent failure | Astra/high for a focused early decision/diagnosis |

Do trivial work directly. Give helpers fresh, self-contained assignments: exact plan sections, caller, revision, owned files/interfaces, dependencies, acceptance and known failures. Helpers read those contracts and applicable repository/UI rules, not the whole startup bundle or unrelated histories. Goal creation, portfolio discovery and tracker ownership belong to the coordinator. Helpers do not delegate further or commit. Reuse the implementer for repairs where practical; independent QA is read-only after the writer stops. Routing is not a promised speed/cost ratio.

### Selecting and finishing work

1. Invoke Goal mode as specified by the reusable prompt, confirming actual activation. Continue the same matching goal across tranches and milestones; do not declare portfolio completion after one increment or impose an unrequested token budget. Reviewing these documents does not itself start implementation. If goal controls are unavailable, disclose that and perform authorized work without claiming automatic continuation.
2. Read the latest [handoff](../../implementation-handoff.md), [ledger](../../delivery-ledger.md), [open decision index](../../approval-based-blockers.md#open-decision-index) and [plan index](../README.md#plan-index). Check Git status, ownership and relevant commits. Preserve unrelated edits; historical verification needs reconciliation with current code.
3. Select by user priority and dependency, initially build/type/authorization repairs and the document journey. Read the selected plan's current scope, applicable decisions, interfaces, failure/security rules and acceptance. Use headings and bounded section reads, expanding linked dependencies when required. Navigation summaries cannot replace these contracts.
4. Make one bounded inspection of real callers and legacy paths before filling the ledger's active card. Name the observable outcome, exact canonical sections, live caller, owned scope, exclusions, invariants and checks. A prerequisite-only increment names its dependent consumer. Reopen discovery only for a missed dependency or changed assumption.
5. After verification, record evidence and continue the next ready tranche without routine confirmation. A parked concept approval blocks its live consumer, not unrelated ready work.

When blocked or out of ready items, inventory **all of `docs/`**, including approved sections absent from the ledger. Search outstanding sections, supporting inventories and relevant evidence; inspect candidates against current code. Record latest coverage, ready candidates, exclusions and resume conditions in the discovery checkpoint. Add stable outcome IDs without reusing old ones. Reuse unchanged findings; do not repeatedly ingest whole plans or historical receipts.

A proposed overview does not negate an independently approved child contract. Lower priority or a pilot release exclusion alone is not an implementation deferral; explicit deferrals, visual approvals and prerequisites still apply. Preserve approved architecture and settled visuals. Before a whole-goal blocked claim, account for every canonical domain and relevant supporting document. If nothing executable remains, report concrete impediments and follow runtime blocked-goal rules. Do not invent work, silently expand approvals or treat missing acceptance as completion.

### Verification and bounded repair

1. **Developer:** establish the relevant runtime/lockfile baseline; run the card's behavior, type/lint and applicable migration/replay/type-parity checks. Explain failures and unrun checks. Never weaken assertions or erase nullability to manufacture a pass.
2. **Coordinator:** inspect the complete scoped diff and real caller; reject unrelated edits and, for higher-risk work, directly exercise one decisive adversarial case. Give QA the acceptance contract, actual revision, risks and baseline independently of the implementer's conclusion.
3. **Independent QA:** required for security, migrations, async processing and user workflows. Exercise actual commands/readers, database/RLS behavior and browser scenarios as applicable. Source-string assertions alone do not establish permission, retry, citation or workflow correctness.
4. **Repair:** classify findings as acceptance blockers, optional robustness, baseline failures, environment limits or adjacent/deferred work. Consolidate confirmed defects into one repair brief, then perform one independent recheck. Persistent material failure gets one stronger diagnosis and a bounded recovery or blocker; renaming a tranche must not reset an endless loop. Newly discovered defects that make the outcome unsafe cannot be dismissed as out of scope.

Track unrelated baseline failures without rerunning them every tranche. Recheck when affected inputs/environment change, a repair targets them, or integration/release requires it. New regressions are not baseline debt. At release acceptance, require disposable database replay/SQL checks, deterministic database and Next route types, TypeScript, lint with disclosed baseline debt, production build and the exact deployed pilot journey. An unavailable required check remains unverified.

### Decisions, tracking, and handoff

The ledger is an evidence index with states `planned`, `building`, `review`, `integrated`, `deployed`, `deferred`. Dependencies are separate. Missing, failed or invalidated acceptance stays in `review`. `integrated` requires scoped local acceptance, required independent QA and a real commit containing the tested change. `deployed` requires exact environment/revision acceptance. Unknown fields stay `not verified` or `unassigned`.

Write one compact [receipt](../../delivery-evidence/README.md#writing) per completed or parked tranche, separating developer, reviewer and coordinator evidence. Partial tranches cannot complete their parent; local integration cannot imply deployment. Before relying on a completed prerequisite, check its receipt, commit inclusion and subsequent relevant code/contract changes. Reuse still-applicable evidence; reopen unsupported claims while retaining historical observations.

Keep the ledger near 1,500 words and receipts normally 300–600 words. These are housekeeping targets, not reasons to hide unfinished work. Fully closed rows may leave the ledger only after their final receipt preserves scope, source and acceptance for every required stage. Retain pending acceptance/release work as compact rows or blocker links. Read historical evidence selectively; no duplicate progress totals or competing status files.

The [decision queue](../../approval-based-blockers.md) owns open human decisions: exact question/recommendation, affected outcome/gate, reason it cannot be inferred, safe independent work and resume owner/action. Record actual user decisions/dates; retain resolved receipts separately with canonical links and implementation evidence. Ordinary technical choices belong to the coordinator. Re-read the index and changed relevant decisions at tranche boundaries. Editing a file does not wake a stopped task; no background monitor is implied.

At checkpoints and before stopping, keep the handoff to branch/HEAD, owned unfinished files, current verification/receipt links, unresolved failures, parked approvals, helper/process ownership and one next executable action. Reconcile another task's newer evidence rather than overwriting it. Stop or transfer writers before a new task takes over. Report phase changes and brief interim progress; stopping reports name actual outcomes, evidence, blockers and the resume action.

### Authority and document maintenance

Local commits and disposable local QA follow the user's starting-prompt authorization. Verify local services, email and jobs before resets or synthetic login/signup. Only the coordinator stages owned reviewed changes and records the actual commit; later code changes invalidate affected evidence. Remote/production changes, paid providers and outgoing messages require their own existing authorization.

Product decisions live in canonical domain plans; this workflow owns execution procedure; code and checks establish implementation facts. Current root `AGENTS.md` and `docs/design-system/` supersede older decorative guidance. Update a changed contract in place, including shared UI/gallery references when applicable; do not rewrite the archive after every commit. Follow [document ownership and reading rules](../../README.md#document-roles) when sources disagree.

## Implementation Plan

1. Reconcile current evidence, close the highest-priority ready outcome and verify its actual consumer.
2. Continue across approved outcomes, discovering other work when blocked.
3. Preserve receipts and a resumable handoff at each checkpoint; satisfy the owning release gates before production claims.

## Interfaces and Data Changes

Documentation only: prompt, working ledger, selective delivery evidence, handoff and decision records. No custom orchestrator, database, automation or model API dependency.

## Testing and Acceptance Criteria

- A fresh task finds ready work without rereading the historical review or every plan.
- Goal continuation, single-writer ownership and risk-appropriate QA remain enforced.
- Missing checks, partial outcomes and stale/absent commits cannot establish completion.
- Wider discovery respects actual approval and dependency gates.
- Links, anchors and indexed plan statuses remain valid; restructuring preserves decisions.
- Documentation changes do not imply application or deployment acceptance.

## Assumptions

The reusable prompt authorizes goal execution, bounded helpers, local commits and disposable local QA. Its use retains current tool permissions and account/runtime limits.

## Open Questions

None. Product decisions remain in the decision queue and block their dependent work.
