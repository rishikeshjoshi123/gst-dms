# Delivery evidence

Durable verification records live here so the [working ledger](../delivery-ledger.md) remains small. This is supporting evidence, not a second backlog or plan archive. Follow the [delivery workflow](../plans/operations/2026-09-08-agent-delivery-workflow.md#decisions-tracking-and-handoff).

No implementation receipts exist yet. Create a record only for an actual completed or parked tranche; do not pre-create empty files for the backlog.

## Reading

Start with the working ledger and handoff. Open only the receipt linked by the active outcome or a required prerequisite. Find older records by outcome ID, tranche ID or canonical-plan reference using filename/text search; do not load this directory wholesale at startup or during backlog discovery. Search its summaries to avoid reimplementing completed work, then inspect the relevant record and current code.

## Writing

Use one compact file per durable tranche, named `D02-T01.md`, for example. Record results at a reviewed checkpoint or when parking unfinished work. Temporary task cards stay in the ledger; do not create a file for each tool call, retry or agent message. Aim for 300–600 words per receipt, with links to meaningful checks/artifacts rather than copied logs. Never include secrets, private source content or confidential fixtures.

Each receipt records:

- **Outcome / tranche / owner task / date:** stable IDs, observable result and exact canonical plan/acceptance section.
- **Base and tested code:** commit plus explicitly identified dirty changes; no ambiguous evidence for a moving checkout.
- **Developer evidence:** acceptance criterion, command/scenario, result and environment; list failed/unrun checks and relevant artifacts.
- **Independent QA:** reviewer/task reference, inspected revision, independently checked behavior and result, or `pending` / `not required` with the workflow reason.
- **Coordinator check:** inspected diff, actual caller and decisive high-risk check when required.
- **Integration:** actual commit containing the tested change, or `not committed`. A document-only receipt commit may point to its tested parent.
- **Deployment:** verified revision/environment or `not verified`; record any release criteria still required.
- **Remaining work:** partial parent acceptance, blockers, dependencies and precise resume action. Say whether this closes the whole parent outcome or only the named tranche, and why.

Link the receipt from its outcome row. A partial or unverified result must remain visible in the working ledger. If later evidence contradicts a receipt, preserve the original dated observation, add the correction or link the later superseding receipt, and reopen the active outcome. File existence, location in this directory and a historical pass do not establish current completion.

Fully closed outcomes can leave the working ledger once their final receipt preserves the outcome summary, canonical source and evidence for all required stages. Keep anything with pending acceptance or release work visible. Search existing ledger and receipt IDs before assigning new ones; never reuse or renumber an old ID.
