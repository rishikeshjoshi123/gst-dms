---
title: Single-Task Agent Delivery and Verification
status: approved
created: 2026-09-08
updated: 2026-09-10
owners:
  - product
  - engineering
related:
  - ./2026-08-29-design-partner-pilot-execution-sequence.md
  - ../platform/2026-08-24-product-architecture-portfolio.md
---

# Single-Task Agent Delivery and Verification

## Summary

One implementation task owns a durable goal, one code writer and sequential verified increments within the user-selected objective. Approved portfolio contracts remain available, but do not independently expand a bounded run. This is the canonical execution workflow. The reusable prompt grants execution authority; the [documentation map](../../README.md) routes supporting reads. Neither summaries nor plan approval prove working software.

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

Do trivial work directly. Give helpers fresh, self-contained assignments: exact plan sections, caller, revision, owned files/interfaces, dependencies, acceptance and known failures. Helpers read those contracts and applicable repository/UI rules, not the whole startup bundle or unrelated histories. Goal creation, scoped discovery and tracker ownership belong to the coordinator. Helpers do not delegate further or commit. Reuse the implementer for repairs where practical; independent QA is read-only after the writer stops. Routing is not a promised speed/cost ratio.

### Current bounded run

Prepared September 10 for the user's next implementation task. Invoking the reusable prompt starts this objective; editing these instructions does not launch this planning task or wake the previous owner. This is execution/verification of already-approved consumers and contracts, not blanket approval of the proposed October release or new product ideas.

**Objective:** make local acceptance repeatable and close verified defects in the existing upload → PDF Workbench → Matter chronology and read-only Team workflows. Deliver executable checks plus actual application repairs where failures demonstrate them.

1. **D01 acceptance runner:** establish one pinned, project-owned headless browser runner and deterministic disposable two-tenant/role fixtures. Get one authenticated Matter/Workbench smoke test running first, then expand to the queue below; do not build a generic test platform. Capture useful synthetic screenshots/traces and document one repeatable command. Verify local database, Storage, worker/email destinations before mutation. The current local config has Inbucket enabled and email confirmation disabled: test confirmation-required auth in an isolated local test profile with captured mail; do not treat auto-confirmed fixtures as verification-email acceptance. Feature tests may use seeded sessions while onboarding's separate open acceptance remains explicit. No Resend, DNS or cloud project setup is required for this run.
2. **D15 and D04 database evidence:** execute the existing Team directory and upload-authority SQL fixtures in disposable local databases, repair demonstrated defects and test role/cross-tenant denial. Preserve relevant successful evidence. Do not rewrite the schema just to modernise unrelated areas.
3. **D04/D06/D07/D11 actual consumers:** exercise current upload/cancel/reselection, authorised PDF opening/source failure/exact page reopening, and chronology filters/selection/Back/Forward. Include read-only Team role visibility. Check representative desktop, 320px/200% zoom, keyboard and dark-mode cases. Fix verified functional/layout failures through the approved design system. Record long-horizon token-expiry, remote provider, deployed cache and representative-scale checks separately when not actually exercised; no production or full-parent acceptance claim follows from this bounded run.

Use Sol/high for the cross-layer runner/integration or material UI work and independent consequential QA; use Terra/medium for clear bounded repairs and Luna/high only for narrow repeatable checks. Helpers receive only selected contracts/risks/acceptance, not the full archive. There is one code writer and one owner of any mutable fixture database at a time. Independent read-only preparation may run alongside the writer; QA tests a stable revision. Retain bounded repair/stronger diagnosis rules below.

If desktop access is blocked, prefer the headless runner; no repeated unlock polling. A claimed screen-lock pass requires actual observation, not merely a headless setting. If local infrastructure is unavailable, perform one bounded diagnosis, record the failure and continue another independent queued check/repair where executable. Do not fabricate passes or wait indefinitely on an unavailable surface.

**Excluded from this run:** new graph/relationship feature construction, typed Review UI and first-attachment work awaiting its concept, Matter identifier redesign, new onboarding/administration scope, retention activation, last-member departure/recovery, OCR/AI promotion, production SMTP/DNS/deployment, financials, Dashboard, marketing and further docs reorganisation. These exclusions do not cancel owning plans or the graph-first release priority. Finish this bounded objective and hand off; the user can expand it after discussion.

### Selecting and finishing work

1. Invoke Goal mode as specified by the reusable prompt, confirming actual activation. Continue the same matching goal across tranches and milestones; do not declare the bounded goal complete after only part of its queue or impose an unrequested token budget. Reviewing these documents does not itself start implementation. If goal controls are unavailable, disclose that and perform authorized work without claiming automatic continuation.
2. Read the latest [handoff](../../implementation-handoff.md), [ledger](../../delivery-ledger.md), [open decision index](../../approval-based-blockers.md#open-decision-index) and [plan index](../README.md#plan-index). Check Git status, ownership and relevant commits. Preserve unrelated edits; historical verification needs reconciliation with current code.
3. Select by user priority and dependency, initially build/type/authorization repairs and the document journey. Read the selected plan's current scope, applicable decisions, interfaces, failure/security rules and acceptance. Use headings and bounded section reads, expanding linked dependencies when required. Navigation summaries cannot replace these contracts.
4. Make one bounded inspection of real callers and legacy paths before filling the ledger's active card. Name the observable outcome, exact canonical sections, live caller, owned scope, exclusions, invariants and checks. A prerequisite-only increment names its dependent consumer. Reopen discovery only for a missed dependency or changed assumption.
5. After verification, record evidence and continue the next ready tranche without routine confirmation. A parked concept approval blocks its live consumer, not unrelated ready work.

When blocked or out of ready items, inspect the current objective's remaining outcomes and necessary approved prerequisites. Use bounded searches and relevant caller/evidence checks, including scoped work absent from the ledger. Record coverage, ready candidates, exclusions and resume conditions once; reopen only when assumptions change. Wider portfolio discovery requires the user to expand the objective. Reuse stable IDs and unchanged findings.

A proposed overview does not negate approved child contracts. The user-selected objective determines what is executable in this run: explicitly excluded work is deferred for the run even when its owning plan is approved. Preserve architecture, settled visuals and actual approval gates. Before a blocked-goal claim, account for the scoped queue and its prerequisites, then follow runtime blocked-goal rules. Do not invent work or treat missing acceptance as completion.

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

Apply the [current pre-pilot data phase](../../decision-history/2026-09-10-planning-and-pre-pilot-policy.md): do not maintain compatibility solely to preserve disposable legacy test data. Verify the actual target and authorised action scope; maintain resulting application integrity. Real-client cutover activates preservation/upgrade compatibility. Discussion and documentation do not start implementation.

When a user-approved product discussion changes a requirement, reconcile the affected current card/ledger against that contract before further dependent work. Preserve older passes as historical evidence and identify adaptation/re-verification explicitly. The [plan-evolution workflow](./2026-09-10-product-discussions-and-plan-evolution.md) and discussion prompt describe topic discovery and coverage conventions; they do not approve new product scope or message/restart another task.

Local commits and disposable local QA follow the user's starting-prompt authorization. Verify local services, email and jobs before resets or synthetic login/signup. Only the coordinator stages owned reviewed changes and records the actual commit; later code changes invalidate affected evidence. Remote/production changes, paid providers and outgoing messages require their own existing authorization.

Product decisions live in canonical domain plans; this workflow owns execution procedure; code and checks establish implementation facts. Current root `AGENTS.md` and `docs/design-system/` supersede older decorative guidance. Update a changed contract in place, including shared UI/gallery references when applicable; do not rewrite the archive after every commit. Follow [document ownership and reading rules](../../README.md#document-roles) when sources disagree.

## Implementation Plan

1. Reconcile current evidence, close the highest-priority ready outcome and verify its actual consumer.
2. Continue within the selected objective and its approved prerequisites, using the current bounded queue until the user expands it.
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
