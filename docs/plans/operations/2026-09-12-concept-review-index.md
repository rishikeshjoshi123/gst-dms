---
title: Developer Concept Review Index
status: approved
created: 2026-09-12
updated: 2026-09-12
owners:
  - product
  - engineering
related:
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
  - ./2026-09-08-agent-delivery-workflow.md
---

# Developer Concept Review Index

## Summary

`/dev/concept-index` is the canonical, unauthenticated catalogue for product concept pages. It presents every concept in an intentional product-review sequence with a short purpose and review focus, while `/dev/design-system` remains a separate supporting implementation reference.

## Context and Goals

Concept routes were individually discoverable only when their URLs were already known. Reviewers need one stable starting point that explains what each fixture demonstrates and provides a coherent path through related concepts.

The index is a developer review aid, not production navigation, a statement of feature completion, or an approval ledger. Like the other `/dev` routes, it contains fixture-only content and does not require authentication.

## Decisions

- Group concepts in this review order: organisation and access; documents and matters; work and decisions; retention and deletion.
- Give every entry a concise purpose and a concrete review focus rather than reproducing the concept page itself.
- Keep the ordered registry explicit so product review order and descriptions remain intentional.
- Every new route under `src/app/dev/` whose directory ends in `-concept` must be added to the index in the same change.
- Maintain an automated parity test between the registered links and the concept route directories so an omitted or duplicate entry fails verification.
- Link `/dev/design-system` as a supporting reference, but do not count it as a product concept.

## Implementation Plan

1. Add a responsive, server-rendered concept catalogue at `/dev/concept-index` using Civic Ink semantic tokens and accessible links.
2. Store ordered concept metadata in a typed registry consumed by the page and its parity test.
3. Update an entry's explanation or position when the concept's product scope materially changes.
4. Add every future `*-concept` route to the registry and run the parity test before handoff.

## Interfaces and Data Changes

- New public developer route: `/dev/concept-index`.
- New internal typed registry for concept hrefs, titles, explanations, review focus, and ordering.
- No production navigation, database, external integration, or permission changes.

## Testing and Acceptance Criteria

- Opening `/dev/concept-index` without a session renders the complete catalogue rather than redirecting to login.
- Every current `*-concept` route appears exactly once and each link opens its concept page.
- A newly added `*-concept` route fails the parity test until it is registered.
- The page remains readable and operable at phone and desktop widths, with keyboard-visible focus and no page-level horizontal overflow.
- `/dev/design-system` is available as a clearly separate supporting reference.

## Delivery Coverage

| Capability | Requirement | Evidence |
| --- | --- | --- |
| CRI-01 | Complete ordered concept catalogue | Route registry, rendered page, and browser verification |
| CRI-02 | Future concept inclusion | Route-to-registry parity test |
| CRI-03 | Public developer access | Existing `/dev` proxy exemption and unauthenticated browser verification |

## Assumptions

Concept pages continue to use the `*-concept` directory suffix. A route that intentionally adopts another convention must revise this plan and its parity test in the same change.

## Open Questions

None.
