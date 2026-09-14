---
title: Single-Task Agent Delivery and Verification
status: approved
created: 2026-09-08
updated: 2026-09-13
owners:
  - product
  - engineering
related:
  - ./2026-08-29-design-partner-pilot-execution-sequence.md
  - ../platform/2026-08-24-product-architecture-portfolio.md
  - ../../decision-history/2026-09-13-cost-aware-outcome-packet-delivery.md
---

# Single-Task Agent Delivery and Verification

## Summary

One implementation task owns one outcome-sized packet, one code writer and its independent verification within the user-selected objective. Approved portfolio contracts remain available, but do not independently expand a bounded run. This is the canonical execution workflow. The reusable prompt grants execution authority; the [documentation map](../../README.md) routes supporting reads. Neither summaries nor plan approval prove working software.

## Context and Goals

The review found completed foundations alongside broken consumers, permission gaps and misleading completion claims. Delivery needs actual caller/acceptance evidence, bounded repair cost and continuity between tasks. Repeated instructions and historical logs should not dominate startup context.

## Decisions

### Task ownership and model routing

The task owner receiving the reusable prompt is the coordinator and keeps the user's selected model/reasoning setting. Sol/medium is a human recommendation, not a command to launch another coordinator. No additional user-owned tasks, worktrees or simultaneous writers. The coordinator owns selection, integration, commits and handoff.

| Assignment | Default helper when useful |
| --- | --- |
| Clear bounded implementation | Terra/medium |
| Material UI or difficult cross-layer implementation | Sol/medium |
| Objective database, browser, screenshot, accessibility, migration/type and regression QA | Luna/high |
| QA requiring difficult adversarial authority, concurrency, lifecycle or product interpretation | Terra/medium or Sol/medium, with the reason stated before delegation |
| Persistent implementation failure | Sol/high for one bounded diagnosis |
| Unresolved flagship visual, high-risk architecture, concurrency, authorization or destructive lifecycle judgment | Astra/medium for one bounded checkpoint, not the whole packet by default |

Do trivial work directly. Normally use at most one implementation writer and one independent QA agent. Spawn helpers without inherited conversation history and give them fresh, self-contained assignments: exact plan sections, caller, revision, owned files/interfaces, dependencies, acceptance and known failures. Limited recent history is permitted only when an essential user decision exists solely there. Helpers read those contracts and applicable repository/UI rules, not the whole startup bundle or unrelated histories. Goal creation, scoped discovery and tracker ownership belong to the coordinator. Helpers do not delegate further or commit. Reuse the implementer for repairs; independent QA remains read-only after the writer stops. Routing is not a promised speed/cost ratio.

### Current bounded run

The current objective belongs in the [handoff](../../implementation-handoff.md) and the [ledger's active card](../../delivery-ledger.md#active-tranche-card), reconciled with current user instructions and code/evidence. This workflow defines the reusable procedure; it does not permanently select a dated feature queue. Invoking the reusable prompt authorises execution within the resolved scope. Editing these instructions does not start implementation or wake another task.

Resolve scope in this order:

1. Use the latest explicit user objective, including any authorised scope change. A previous run's exclusions cannot cancel a later user decision.
2. Otherwise resume the recorded unfinished authorised objective after reconciling its scope and evidence. A large chat or new task is not a reason to repeat completed implementation or every historical check.
3. If the user explicitly delegates next-outcome selection, use that direction and the current decisions, ledger and relevant approved plans to choose one ready bounded outcome. State its observable result, dependencies, exclusions and acceptance in the active card, then implement without routine confirmation. This delegation does not approve unresolved product choices or a whole-portfolio goal.
4. If the previous objective is complete and no next scope or selection authority exists, report completion and recommend a concrete next scope. Do not revive the September 10 queue or invent work to keep a goal running.

Release assessments are context rather than blanket product approval or permanent scope unless the user's latest objective explicitly adopts them. Approved domain plans and current decisions govern selected features. Preserve actual product gates and external-action boundaries. A new task resumes from saved scope, evidence and ownership; do not assume its goal is activated merely because a previous task had one.

Before moving execution to a fresh task, the previous owner records its objective and remaining acceptance, branch/HEAD, owned unfinished files, checks/failures, decisions, helper/process ownership and next executable action, then stops its writers. The new owner verifies this handoff against the checkout before editing. Unrelated dirty files remain untouched. No simultaneous implementation owners or automatic restart of the old task.

**Historical September 10 run:** the former fixed queue established repeatable local acceptance and repaired existing upload → PDF Workbench → Matter chronology and read-only Team consumers. Its scoped local results are indexed in [D01-T06](../../delivery-evidence/D01-T06.md), [D04-T03](../../delivery-evidence/D04-T03.md) and [D06-T12](../../delivery-evidence/D06-T12.md). Its exclusions limited that run, not every future task. Later authorised onboarding, Trash and Intake work is recorded in the current handoff. These receipts do not close their parent domains or establish deployed, provider, expiry or scale acceptance.

### Selecting and finishing work

1. Resolve the current bounded objective as above, select one outcome-sized packet and invoke Goal mode as specified by the reusable prompt, confirming actual activation. One packet normally contains the schema, server, UI and verification needed for one observable journey rather than paying delivery overhead for each layer separately. Do not combine unrelated outcomes, split one journey across artificial goals or impose an unrequested token budget. Reviewing these documents does not itself start implementation. If goal controls are unavailable, disclose that and perform authorized work without claiming automatic continuation.
2. Read the latest [handoff](../../implementation-handoff.md), [ledger](../../delivery-ledger.md), [open decision index](../../approval-based-blockers.md#open-decision-index) and [plan index](../README.md#plan-index). Check Git status, ownership and relevant commits. Preserve unrelated edits; historical verification needs reconciliation with current code.
3. Select by current user priority and dependency within that objective. Read the selected plan's current scope, applicable decisions, interfaces, failure/security rules and acceptance. Use headings and bounded section reads, expanding linked dependencies when required. Navigation summaries cannot replace these contracts.
4. Make one bounded inspection of real callers and legacy paths before filling the ledger's active card. Name the observable outcome, exact canonical sections, live caller, owned scope, exclusions, invariants and checks. A prerequisite-only increment names its dependent consumer. Reopen discovery only for a missed dependency or changed assumption.
5. After verification, record evidence, complete the packet goal and stop. Report the next recommended packet without starting it. A later explicit continuation starts a fresh reconciliation. A parked concept approval blocks its live consumer, not unrelated ready work.

When blocked or out of ready items, inspect the current objective's remaining outcomes and necessary approved prerequisites. Use bounded searches and relevant caller/evidence checks, including scoped work absent from the ledger. Record coverage, ready candidates, exclusions and resume conditions once; reopen only when assumptions change. Wider portfolio discovery requires the user to expand the objective. Reuse stable IDs and unchanged findings.

A proposed overview does not negate approved child contracts. The user-selected objective determines what is executable in this run: explicitly excluded work is deferred for the run even when its owning plan is approved. Preserve architecture, settled visuals and actual approval gates. Before a blocked-goal claim, account for the scoped queue and its prerequisites, then follow runtime blocked-goal rules. Do not invent work or treat missing acceptance as completion.

### Verification and bounded repair

Reuse the existing project-owned headless acceptance runner and local fixtures; extend them only for the selected outcome. There is one owner of a mutable fixture database at a time. Independent read-only preparation may run alongside the writer; QA tests an exact coordinator-reviewed local commit from a clean state. Confirmation-required onboarding uses isolated local auth and captured mail, not auto-confirmed fixtures. Verify database, Storage, job and email destinations before mutation. Record desktop/mobile, keyboard, dark mode, zoom and source/permission checks according to the affected consumer, with unrun cases explicit.

If desktop access is blocked, prefer the headless runner; no repeated unlock polling. A claimed screen-lock pass requires actual observation, not merely a headless setting. If local infrastructure is unavailable, perform one bounded diagnosis, record the failure and continue another independent scoped outcome where executable. Do not fabricate passes or wait indefinitely on an unavailable surface.

1. **Developer:** establish the relevant runtime/lockfile baseline and run focused behavior, type/lint and applicable migration/type-parity checks while implementing. Explain failures and unrun checks. Never weaken assertions or erase nullability to manufacture a pass.
2. **Coordinator:** inspect the complete scoped diff and real caller; reject unrelated edits and, for higher-risk work, directly exercise one decisive adversarial case. Avoid duplicating an already adequate focused run. Once accepted, create a scoped local implementation commit and give QA the acceptance contract, exact commit, risks and baseline independently of the implementer's conclusion.
3. **Independent QA:** required for security, migrations, async processing and user workflows. From a clean state, exercise the exact commit's actual commands/readers, database/RLS behavior and browser scenarios as applicable. Run the complete packet-level acceptance once. Source-string assertions alone do not establish permission, retry, citation or workflow correctness.
4. **Repair:** classify findings as acceptance blockers, optional robustness, baseline failures, environment limits or adjacent/deferred work. Consolidate confirmed defects into one brief for the original implementer, run focused affected checks and create a separate repair commit. The same read-only QA agent may verify the repaired exact commit unless independence was compromised. Rerun failed and affected gates plus a minimal regression check; repeat the whole expensive suite only when the repair could invalidate it. If the same root problem survives the second implementation attempt, use one bounded Sol/high diagnosis and one controlled final repair. If it still fails, record a blocker; renaming the packet must not reset the loop. Newly discovered defects that make the outcome unsafe cannot be dismissed as out of scope.

Track unrelated baseline failures without rerunning them every packet. Once an appropriate check passes, broaden or repeat it only when affected inputs change, a repair can invalidate it, or integration/release requires it. New regressions are not baseline debt. At release acceptance, require disposable database replay/SQL checks, deterministic database and Next route types, TypeScript, lint with disclosed baseline debt, production build and the exact deployed pilot journey. An unavailable required check remains unverified.

### Decisions, tracking, and handoff

The ledger is an evidence index with states `planned`, `building`, `review`, `integrated`, `deployed`, `deferred`. Dependencies are separate. Missing, failed or invalidated acceptance stays in `review`. `integrated` requires scoped local acceptance, required independent QA and a real commit containing the tested change. `deployed` requires exact environment/revision acceptance. Unknown fields stay `not verified` or `unassigned`.

Write one compact [receipt](../../delivery-evidence/README.md#writing) per completed or parked packet, separating developer, reviewer and coordinator evidence. A partial packet cannot establish its promised outcome; local integration cannot imply deployment. Before relying on a completed prerequisite, check its receipt, commit inclusion and subsequent relevant code/contract changes. Reuse still-applicable evidence; reopen unsupported claims while retaining historical observations.

Keep the ledger near 1,500 words and receipts normally 300–600 words. These are housekeeping targets, not reasons to hide unfinished work. Fully closed rows may leave the ledger only after their final receipt preserves scope, source and acceptance for every required stage. Retain pending acceptance/release work as compact rows or blocker links. Read historical evidence selectively; no duplicate progress totals or competing status files.

The [decision queue](../../approval-based-blockers.md) owns open human decisions: exact question/recommendation, affected outcome/gate, reason it cannot be inferred, safe independent work and resume owner/action. Record actual user decisions/dates; retain resolved receipts separately with canonical links and implementation evidence. Ordinary technical choices belong to the coordinator. Re-read the index and changed relevant decisions at packet boundaries. Editing a file does not wake a stopped task; no background monitor is implied.

At checkpoints and before stopping, keep the handoff to branch/HEAD, owned unfinished files, current verification/receipt links, unresolved failures, parked approvals, helper/process ownership and one next executable action. Reconcile another task's newer evidence rather than overwriting it. Stop or transfer writers before a new task takes over. Report phase changes and brief interim progress; stopping reports name actual outcomes, evidence, blockers and the resume action.

### Authority and document maintenance

Apply the [current pre-pilot data phase](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md): do not maintain compatibility solely to preserve disposable legacy test data. Verify the actual target and authorised action scope; maintain resulting application integrity. Real-client cutover activates preservation/upgrade compatibility. Discussion and documentation do not start implementation.

When a user-approved product discussion changes a requirement, reconcile the affected current card/ledger against that contract before further dependent work. Preserve older passes as historical evidence and identify adaptation/re-verification explicitly. The [plan-evolution workflow](./2026-09-10-product-discussions-and-plan-evolution.md) and discussion prompt describe topic discovery and coverage conventions; they do not approve new product scope or message/restart another task.

Local commits and disposable local QA follow the user's starting-prompt authorization. Verify local services, email and jobs before resets or synthetic login/signup. Only the coordinator stages owned reviewed changes and records the actual commit; later code changes invalidate affected evidence. Remote/production changes, paid providers and outgoing messages require their own existing authorization.

Product decisions live in canonical domain plans; this workflow owns execution procedure; code and checks establish implementation facts. Current root `AGENTS.md` and `docs/design-system/` supersede older decorative guidance. Update a changed contract in place, including shared UI/gallery references when applicable; do not rewrite the archive after every commit. Follow [document ownership and reading rules](../../README.md#document-roles) when sources disagree.

## Implementation Plan

1. Reconcile current evidence, close the highest-priority ready outcome and verify its actual consumer.
2. Complete one observable packet within the selected objective, then stop with the next recommendation until the user explicitly continues.
3. Preserve receipts and a resumable handoff at each checkpoint; satisfy the owning release gates before production claims.

## Interfaces and Data Changes

Documentation only: prompt, working ledger, selective delivery evidence, handoff and decision records. No custom orchestrator, database, automation or model API dependency.

## Testing and Acceptance Criteria

- A fresh task finds ready work without rereading the historical review or every plan.
- Goal continuation, single-writer ownership and risk-appropriate QA remain enforced.
- Missing checks, partial outcomes and stale/absent commits cannot establish completion.
- Scoped discovery respects the selected objective, actual approvals and dependencies; a bounded run does not expand into the portfolio.
- Links, anchors and indexed plan statuses remain valid; restructuring preserves decisions.
- Documentation changes do not imply application or deployment acceptance.

## Assumptions

The reusable prompt authorizes goal execution, bounded helpers, local commits and disposable local QA. Its use retains current tool permissions and account/runtime limits.

## Open Questions

None. Product decisions remain in the decision queue and block their dependent work.
