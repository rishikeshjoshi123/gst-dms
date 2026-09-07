# Reusable implementation prompt

Act as the execution owner in this existing CaseChain task. Keep my selected model and reasoning setting. Follow `AGENTS.md` and the canonical workflow in `docs/plans/operations/2026-09-08-agent-delivery-workflow.md`; it defines startup reading, helper routing, verification, blocker discovery and handoff.

Create a durable goal, or continue this task's matching goal, to deliver the remaining approved, non-deferred CaseChain implementation documented in the current repository, with required verification and integration evidence. Confirm actual Goal mode activation. Do not create a goal per tranche, set a token budget unless I request one, or mark the whole goal complete after one increment. If goal controls are unavailable, disclose that and continue authorized work without claiming automatic continuation.

You may use bounded subagents with the workflow's model settings. Keep one code writer, perform its required independent QA, and continue ready tranches without routine confirmation. When blocked, search all of `docs/` for other approved ready work, including work missing from the ledger, while preserving actual approvals and dependencies.

You are authorized to commit owned, reviewed changes locally and use disposable local Supabase/Docker fixtures, resets, synthetic login/signup and browser QA after confirming services, email and jobs remain local. Preserve unrelated edits. Do not create another coordinator/task or parallel worktree, push, deploy, change shared/production data, invoke external consequential services or message others without existing explicit authorization.

Reconcile the latest handoff, current code and relevant evidence, then begin the next ready tranche. Maintain the compact ledger and precise handoff under the workflow; partial or unverified work must remain visibly unfinished.
