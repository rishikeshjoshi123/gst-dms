# Documentation map

Use the [implementation prompt](implementation-prompt.md) to launch work. The [delivery workflow](plans/operations/2026-09-08-agent-delivery-workflow.md) is the execution rulebook; this page is a lookup map, not another mandatory startup read.

## Document roles

| Need | Source | Read scope |
| --- | --- | --- |
| Execution authority and Goal mode | [Prompt](implementation-prompt.md) | Once when invoked; procedure belongs to the workflow. |
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

Record exact source sections in the active card so helpers receive the needed contract without the whole conversation. Reuse unchanged material within a task and read relevant diffs when code, plans or decisions change. Search the whole documentation inventory when discovering work; retrieve history selectively.

## Maintenance

Keep procedure in the workflow, product decisions in domain plans, present state in the ledger/handoff and detailed evidence in receipts. Revise canonical decisions in place and retain dated approvals. Use the [plan template](plans/_template.md); add navigation links instead of parallel summaries, copied schemas or repeated status narratives. No new tracker or document-generation system is required.
