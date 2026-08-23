---
title: CaseChain Design-System Overhaul
status: in-progress
created: 2026-08-20
updated: 2026-08-23
owners:
  - product
  - engineering
related: []
---

# CaseChain Design-System Overhaul

## Summary

Rebuild the CaseChain visual system from first principles while retaining the product name and domain model. The new direction will be calm, authoritative, information-dense, trustworthy, WCAG 2.2 AA compliant, and task-adaptive on mobile.

Treat the current tokens and UI components as legacy. Preserve the technical stack—Next.js 16, Tailwind CSS v4, Radix primitives, Lucide icons, and `next/font`—while replacing the visual conventions and component contracts.

## Context and Goals

CaseChain is a multi-tenant GST-litigation document system used for document intake and AI processing, clients and matters, review queues, legal timelines, notes, notifications, billing, and PDF inspection. Its design system must prioritize trust, dense evidence-heavy workflows, unambiguous status communication, and comfortable long desktop sessions without sacrificing complete mobile access.

The authenticated product is the first priority. Authentication and public pages will later adopt a lighter version of the same brand layer. Existing business logic, database schemas, routes, and server/client boundaries are outside the visual overhaul.

## Decisions

- Adopt **Civic Ink** as the single initial visual direction: warm paper-like neutrals, deep ink navigation, a restrained blue-green action colour, brass attention accents, and compact professional geometry.
- Use neutral, low-chroma surfaces with one restrained action color. Reserve green, amber, red, violet, and similar colors for defined meanings.
- Use Geist Sans for interface text and Geist Mono for reference numbers, GST identifiers, dates, document codes, and extracted metadata.
- Adopt compact professional density: 14px body text, clear 12px metadata, 20–28px page headings, restrained 6–10px radii, and minimal shadows.
- Use 6px radii for buttons and controls and 8px radii for cards and panels. Operational controls must not use sharp square corners or oversized pill geometry.
- Use a 64px collapsed desktop navigation rail that expands to 224px on hover or keyboard focus and overlays page content instead of reflowing it. Do not repeat a legal-scale icon in the sidebar brand area.
- Avoid decorative gradients, excessive hover movement, glass effects, emoji in operational screens, and entity colors that do not communicate meaning.
- Define separate semantic families for matter and document lifecycles, processing and AI extraction, confidence and review requirements, deadline urgency, and general feedback.
- Pair every meaningful color state with a label, icon, or explanatory text.
- Within any repeated collection, reserve one consistent status-chip width and alignment across all items. Different collections may use different widths when their status vocabulary requires it, but chip sizing must never vary row by row within the same section.
- Preserve all product capabilities on mobile through task-adaptive presentations instead of shrinking complex desktop layouts.
- Make the token architecture capable of supporting additional named themes later, but ship only Civic Ink in the initial system. Do not add a theme selector, Quiet Ledger, Precision Blue, or arbitrary user colour controls in the first release.
- Treat light/dark appearance and named visual themes as separate concepts. Both Civic Ink appearances must share one semantic token contract.
- If user colour customization is introduced later, offer a small set of accessibility-tested accent choices rather than unrestricted primary and secondary colour pickers. Semantic success, warning, danger, confidence, and deadline colours are never user-customizable.
- Maintain the current, tool-agnostic UI contract under `docs/design-system/`. The plan archive records the overhaul and its decisions; the living specification, semantic tokens, shared components, and `/dev/design-system` gallery jointly guide future UI work.
- Adopt **Stable Workspace Chrome** for operational layouts: page or pane identity, interpretation context, and primary actions remain outside the designated scrolling body. Desktop split panes may scroll independently without moving their headers; mobile normally uses one principal scroller with a compact sticky header or bottom action bar.
- Use thin, semantic, discoverable scrollbars. Do not hide scrolling affordances, allow accidental nested scrollers, or let live updates and loading states unexpectedly move the user's context.

## Implementation Plan

1. Produce a design-system charter covering users, principles, terminology, accessibility, responsive behavior, and contribution rules.
2. Audit every current screen and classify repeated UI as a primitive, domain pattern, template, or one-off composition. Record token violations and duplicated native controls.
3. Replace the legacy visual foundation with raw, semantic, and component token layers covering Civic Ink's light and dark appearances, typography, spacing, elevation, focus, motion, breakpoints, and density. Keep visual values behind semantic tokens so another named theme could implement the same contract later.
4. Build foundations and primitives for typography, icons, surfaces, dividers, buttons, form controls, badges, tooltips, dialogs, drawers, tabs, menus, toast messages, and loading states.
5. Build reusable data components for tables, list rows, filtering, pagination, search, metadata grids, and empty/error states.
6. Build domain patterns for document and matter status, confidence, deadlines, processing, document preview, audit entries, and review decisions.
7. Standardize templates for collections, matter workspaces, review queues, split-pane document review, settings, and dashboards.
8. Create a non-production `/dev/design-system` gallery containing tokens, component states, responsive examples, dark mode, loading/error/empty states, and accessibility notes.
9. Validate the system by migrating Inbox and Matter workflows first. Then migrate review and collection pages, dashboard and settings, followed by authentication and public surfaces.
10. Add review or lint safeguards against raw hex colors, undeclared variables, arbitrary status colors, and duplicate primitive controls in feature code.

The Civic Ink visual draft, including its desktop and mobile live-processing treatments, was approved on 2026-08-22. Implementation begins with the authenticated shell and Document Hub pilot before expanding to Matter workflows.

The living design-system charter and contribution guidance were added under `docs/design-system/` on 2026-08-23 and made required reading for UI work through `AGENTS.md`.

Responsive adaptations must include prioritized card or drill-down alternatives for tables, separate metadata/action drawers for PDF review, a chronological list alternative to the timeline graph, selection mode with a bottom action bar for bulk operations, phone-sized drawers in place of unsuitable dialogs, and touch targets of at least 44 by 44 pixels.

## Interfaces and Data Changes

- Components use typed contracts such as `variant`, `tone`, `size`, `density`, `loading`, and `invalid`; feature screens do not add arbitrary visual variants.
- Domain status components accept domain enums rather than color names.
- Form controls share label, description, validation, disabled, required, and loading behavior.
- Interactive components forward refs, support keyboard operation, expose accessible names, and render visible focus.
- Feature components control layout and content while consuming system tokens and shared components for appearance and behavior.
- Components must not branch on a named theme. Theme containers provide semantic values, and components consume the same semantic token names in every appearance.
- No database schema or server API changes are required.

## Testing and Acceptance Criteria

- Test light and dark themes from a 320px phone viewport through wide desktop layouts, at 200% zoom, with keyboard-only use, reduced motion, and screen-reader naming.
- Enforce WCAG 2.2 AA contrast and interaction requirements.
- Cover default, hover, focus, active, disabled, loading, empty, error, destructive-confirmation, and long-content states.
- Validate long client names, GST references, multiple dates, missing metadata, large queues, duplicate filenames, low-confidence AI results, urgent deadlines, and failed uploads.
- Add automated accessibility checks and visual regression coverage for the gallery and the two pilot workflows.
- Consider the system validated when Inbox and Matter require no raw styling exceptions and remain fully operable across the target viewport and accessibility matrix.

## Assumptions

- The authenticated product is the first implementation priority.
- The current visual language is not a compatibility requirement.
- Complex workflows may use different task-focused presentations on mobile while retaining their capabilities.
- Existing business logic, data contracts, routing, and server/client boundaries remain unchanged.
- The in-app design-system gallery will be the canonical component reference.
- Civic Ink is the only user-visible visual theme in the initial release; future theme selection remains an architectural capability rather than current product scope.

## Open Questions

None.
