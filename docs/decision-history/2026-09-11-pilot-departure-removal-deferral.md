# September 11 — Pilot departure/removal deferral and foundation-first handover

## Confirmed user decision

- The design-partner pilot will not include administrative member removal or self-service resignation.
- CaseChain will first build the important ownership and lifecycle foundations needed to identify every responsibility held by a departing member. The departure feature is implemented after those foundations, near the end of the wider delivery sequence.
- The approved Team/departure concept remains the future visual direction. This decision changes release scope and sequencing; it does not reopen that visual approval.

## Required future flow

1. A member submits a resignation request, or an Owner/Admin starts an administrative departure.
2. The Owner sees a complete, truthful inventory of every pending item and responsibility assigned to that member.
3. The Owner assigns each item to another eligible person. The flow must not present unknown or unsupported categories as zero impact.
4. CaseChain transactionally rechecks that no blocking responsibility remains, including stale or concurrently assigned work.
5. Only after the inventory is clear may CaseChain complete the departure, revoke current access and preserve historical identity and audit evidence.

No direct removal shortcut or self-service exit may bypass the impact, reassignment and final zero-responsibility check.

## Delivery impact

- `ORG-ADMIN-REMOVAL-DEPENDENCY-BOUNDARY-2026-09-08` is resolved by deferral rather than by narrowing the pilot to an incomplete impact catalogue.
- D15 remains planned but outside pilot scope. Do not reconnect the legacy `removeMember` caller or expose resignation while the foundations are incomplete.
- Prerequisites include canonical accountable ownership for relevant work such as Tasks and important deadlines, secure addressed-notification lifecycle handling, historical-identity preservation, and any other responsibility category enabled before departure ships.
- Domains that genuinely do not exist when the feature is implemented may be documented as not applicable; existing but unmodelled responsibilities may not be shown as zero.
- Last-member departure, empty-organisation lifecycle and recovery remain separate deferred questions.

This record does not launch implementation, deployment or remote changes. A future coordinator must reconcile the canonical Organisation plan and D15 acceptance before issuing a writer brief.
