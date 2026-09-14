# Documentation map

Choose the entry point for the work you want. This page is a lookup map, not another mandatory startup read.

| What you want | Start here |
| --- | --- |
| Suggest a topic or discuss your idea | [Product discussion prompt](planning-prompt.md): overlap, critique, alternatives and saved decisions |
| Understand the October target and tradeoffs | [September 14 release scope](decision-history/2026-09-14-first-production-release-scope.md) → [current pilot plan](plans/operations/2026-08-29-design-partner-pilot-execution-sequence.md); [go-live ownership](discovery/production-go-live-ownership-and-incident-response.md) remains the priority discussion, with the [environment/recovery options](discovery/production-environment-and-recovery-options.md) session targeted for October 1–2 |
| See what is built, unverified or still missing | [Delivery ledger](delivery-ledger.md), then relevant receipts; coverage is partial, not a whole-app percentage |
| See what needs your decision | [Open decision index](approval-based-blockers.md#open-decision-index) |
| See the current implementation task/restart point | [Handoff](implementation-handoff.md); editing docs does not wake a stopped task |
| Start or resume authorised implementation | [Implementation prompt](implementation-prompt.md) → [current scope and takeover rules](plans/operations/2026-09-08-agent-delivery-workflow.md#current-bounded-run), using the latest handoff; complete one outcome-sized packet and stop, with no replay of a completed queue |

## Document roles

| Need | Source | Read scope |
| --- | --- | --- |
| Execution authority and Goal mode | [Prompt](implementation-prompt.md) | Once when invoked; procedure belongs to the workflow. |
| Product discussion and effects of changed requirements | [Discussion prompt](planning-prompt.md) → [plan evolution](plans/operations/2026-09-10-product-discussions-and-plan-evolution.md) | Chosen topic and its evidence; proposals are not approvals. |
| Selection, helpers, QA and continuation | [Workflow](plans/operations/2026-09-08-agent-delivery-workflow.md) | Once per fresh task; revisit changed rules. |
| Current work and restart point | [Ledger](delivery-ledger.md), [handoff](implementation-handoff.md) | Current entries, reconciled with code/evidence. |
| Unsettled product decisions | [Open decision index](approval-based-blockers.md#open-decision-index) | Index, then affected entries; resolved receipts are linked separately. |
| Approved product behavior | [Plan index](plans/README.md#plan-index) → domain plan | Current scope, relevant decisions/interfaces and acceptance. |
| Current UI contract | [Design-system router](design-system/README.md) | Its task-specific required reading, shared components and gallery. |
| Proof or prior approval | [Delivery evidence](delivery-evidence/README.md), linked decision history | Specific records needed by the outcome or prerequisite. |
| Supporting investigation | [Work catalogue](work-catalogue-inventory.md), [review](reviews/2026-09-07-app-and-plan-review.md), [search baseline](search/legacy-search-baseline-v1.md) | Relevant finding or disposition, checked against current code. |

Current explicit user decisions and applicable instructions govern authority. Plans govern intended behavior; code and checks establish actual behavior. A stale implementation does not override its approved contract. The workflow governs execution, not product scope. Portal summaries and historical checkpoints do not supersede canonical decisions. Resolve contradictions at their owning source; use the decision queue when a real user choice is needed.

## Reading a large plan

Use heading search, such as `rg -n '^#{2,4} ' <plan>`, then read complete relevant sections with bounded output. Start with status/scope and current amendments, then the operation's decisions, interfaces and acceptance. Include shared security/lifecycle/failure rules even outside that operation's heading. A keyword hit or navigation summary is insufficient; recover truncated text.

Expand dependencies according to the change: permissions need role/RLS and tenancy contracts; source work needs identity/version/lifecycle rules; async changes need concurrency, replay and failure behavior; UI needs design-system, accessibility and approved visuals. If the boundary is unclear, read more before implementing.

Record exact source sections in the active card so helpers receive the needed contract without the whole conversation. Reuse unchanged material within a task and read relevant diffs when code, plans or decisions change. Search the selected objective and its dependencies when discovering work; retrieve history selectively.

## Maintenance

Keep procedure in the workflow, product decisions in domain plans, present state in the ledger/handoff and detailed evidence in receipts. Revise canonical decisions in place and retain dated approvals. Use the [plan template](plans/_template.md); add navigation links instead of parallel summaries, copied schemas or repeated status narratives. No new tracker or document-generation system is required.

An unfinished idea worth revisiting may have one compact topic note in `docs/discovery/`, created only when needed. Store the problem, alternatives, unsettled question and next step, not a transcript. On resolution retain a short disposition linking the canonical plan/decision. Do not put unfinished brainstorming into finalized plans or make every idea a blocker.

When an agreed plan change affects existing code, preserve the old evidence and reopen affected acceptance in the ledger. Coverage maps link requirements to those outcomes without duplicating status. Split long plans by independently owned capabilities only when useful; preserve links and shared invariants. No fixed daily documentation chore or full-archive reread is required.
