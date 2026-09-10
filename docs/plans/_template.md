---
title: Plan title
status: proposed
created: YYYY-MM-DD
updated: YYYY-MM-DD
owners:
  - owner
related: []
---

# Plan title

## Reading guide

For a long plan, link to its current scope/amendments, shared invariants, operation sections, interfaces and acceptance. Use anchors rather than copied summaries. Omit this section for a short plan; navigation does not replace the linked contracts.

## Summary

State the intended outcome and the approach in a few sentences.

## Context and Goals

Describe the current state, the problem being solved, the audience, success criteria, and meaningful scope boundaries.

## Decisions

Record the decisions an implementer must follow, including important tradeoffs and defaults.

## Implementation Plan

Describe ordered changes and dependencies by observable outcome. Keep current evidence in the delivery ledger/receipts and link it when needed; do not append task transcripts or repeated checkpoint logs. Label retained historical evidence and avoid presenting old next actions as current instructions.

## Interfaces and Data Changes

Document changes to public APIs, component contracts, types, schemas, events, configuration, or external integrations. State `None` when this section is relevant but no changes are required.

## Testing and Acceptance Criteria

Use meaningful capability IDs where implementation needs tracking; link exact acceptance sections from a Delivery Coverage map. Keep status in the ledger rather than duplicating it in the plan.

List observable completion criteria, failure/security cases and required checks for each outcome. Distinguish local and deployment gates. Link shared contracts instead of duplicating definitions; do not replace necessary acceptance detail with a word-count target.

## Delivery Coverage

Map capability ID, exact requirement/acceptance anchor, owning ledger outcome and evidence pointer. Declare coverage `partial` until the stated scope is fully mapped; unmapped requirements are unknown. A plan-only proposal may say `Not inventoried`. Preserve IDs across revisions and identify rework when a requirement changes. See the plan-evolution workflow through the plan index.

## Assumptions

Record assumptions and defaults that affect implementation.

## Open Questions

List only non-blocking follow-ups. Write `None` when the plan is decision-complete.
