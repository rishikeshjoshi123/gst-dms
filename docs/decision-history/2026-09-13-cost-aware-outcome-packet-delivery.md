# September 13 — Cost-aware outcome-packet delivery

## Confirmed user decisions

- Preserve high implementation quality while reducing repeated coordination, context and verification cost.
- Deliver one observable user journey as one outcome-sized packet across its necessary database, server, UI and acceptance boundaries instead of creating a separate tranche for every layer.
- Use the user-selected coordinator model; Sol/medium is the preferred implementation coordinator for this workflow.
- Spawn bounded helpers without inherited conversation history by default. Give each helper a compact, self-contained brief. Use limited recent history only when an essential user decision exists solely there; do not pass the full historical thread by default.
- Normally use one implementation writer and one independent read-only QA agent. Helpers do not delegate or commit.
- Default clear bounded implementation to Terra/medium, meaningful UI or difficult cross-layer implementation to Sol/medium, and objective browser/database/type/migration QA to Luna/high. Elevate QA only for difficult interpretation. Use Astra/medium for a bounded high-risk or flagship-visual checkpoint, and Sol/high for one bounded diagnosis after persistent implementation failure.
- The coordinator reviews the candidate and creates a scoped implementation commit before independent QA. QA verifies that exact commit from a clean state.
- Return a failed QA result to the original writer. The same independent QA agent may verify the repair unless its independence was compromised. If the same root problem survives the second implementation attempt, use one bounded Sol/high diagnosis; do not continue an endless loop.
- Use focused checks during implementation and repair. Run complete packet acceptance once against the exact commit, and repeat expensive checks only when a change or failure can invalidate them.
- Complete one packet, update evidence and handoff, recommend the next packet, and stop until the user explicitly continues.

## Scope and effect

This changes delivery procedure, model routing and verification economy. It does not approve a product feature, select the next implementation packet, start application implementation, weaken security or release acceptance, authorise deployment/provider use, or resolve the pending final pilot release-scope review.

The reusable implementation prompt and canonical delivery workflow carry these rules. Existing implementation receipts remain historical evidence and are not invalidated solely by this procedural change.
