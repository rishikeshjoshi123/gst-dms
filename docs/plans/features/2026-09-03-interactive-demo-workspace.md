---
title: Passcode-Gated Interactive Demo Workspace
status: proposed
created: 2026-09-03
updated: 2026-09-03
owners:
  - product
  - design
  - engineering
related:
  - ../design-system/2026-08-28-public-brand-and-landing-page.md
  - ./2026-08-25-matter-workspace-and-procedural-timeline.md
  - ./2026-08-25-work-review-activity-notifications.md
  - ./2026-08-25-notes-and-case-brief.md
  - ../platform/2026-08-27-platform-operations.md
---

# Passcode-Gated Interactive Demo Workspace

## Summary

Add a passcode-gated, interactive CaseChain demo that lets a prospect experience a coherent fictional GST-litigation workspace without signing up. The demo reuses stable production presentation contracts but obtains all application data from versioned repository fixtures, applies changes only to per-tab browser state, and has no authority to call Supabase mutations, Storage, AI providers, email, Trigger jobs, or other production side effects.

This feature is deliberately scheduled last. Implementation begins only after the existing indexed CaseChain product, design-system, platform, and operational plans are completed or explicitly superseded, and after the stable Matter-to-evidence-to-Review-to-Task production journey is reusable. The production application remains canonical; the demo must not become a parallel product implementation.

## Context and Goals

CaseChain's value is experiential: a connected matter, its source evidence, procedural timeline, Review decisions, tasks, and notes are easier to understand by using them than by reading feature copy. A controlled demo can reduce acquisition friction, support sales conversations, and let prospects self-qualify without creating an account or organisation.

The main risks are accidental access to production mutation paths, maintenance drift from the real application, a shared access code being mistaken for strong authentication, synthetic data creating misleading product claims, and an over-broad demo delaying core product work. The plan addresses those risks through a separate `/demo` runtime boundary, shared data-agnostic views, compile-time dependency checks, a curated workflow, explicit fictional-data labels, and deferred delivery.

Success means a prospect can enter with a configured access code, understand the product through an optional guided mission, explore the main workspace, make representative temporary changes, reset the experience, and reach signup or contact actions. No demo interaction may alter canonical data or trigger paid or external workflow effects.

## Decisions

- Call the credential a **demo access code** in user-facing copy. A shared code is a soft launch and traffic gate, not WebAuthn authentication or protection for sensitive content.
- Make **Try the interactive demo** the primary landing-page action, **Create workspace** secondary, and retain sign-in access. Add a contextual demo invitation near the landing-page product specimen.
- Route visitors through `/demo/access` and then `/demo/dashboard`. Direct demo links remain shareable but require a valid signed access cookie.
- Show persistent demo chrome stating that all data is fictional and changes remain in the current tab. Provide **Reset demo**, **Create workspace**, and **Back to CaseChain** actions.
- Offer a skippable, resumable guided mission that opens a priority matter, follows its timeline to source evidence, resolves a Review item, and creates or completes related work. Free exploration remains available at all times.
- Include Dashboard, Clients, Matters, one rich Matter Workspace and source inspector, Review, Tasks, Notes, local Search, Activity projections, and limited Trash/restore behavior.
- Support representative interactions: matter detail/status edits; note creation, editing, pinning, replies, and deletion; task creation, assignment, comments, due-date/status changes; Review accept/reject decisions; document move-to-Trash and restore; filters and Search.
- Keep derived counts, attention indicators, Activity, Search results, and Trash projections consistent after every temporary command.
- Exclude real uploads, provider-backed AI or reprocessing, invitations, organisation administration, usage/billing, email, realtime collaboration, exports, and permanent deletion. Hide irrelevant controls; explain an unavailable real-workspace capability only when it materially helps the product story.
- Label every person, organisation, identifier, source document, legal event, and extracted result as fictional. Precomputed extraction output is presented as an example and never as a live model result.
- Use one coherent fixture: a fictional practice, three clients, five matters, approximately eighteen documents, six tasks, five note threads, three Review items, Activity, deadlines, and two small synthetic source PDFs. Current tasks and deadlines are derived relative to the demo-session start so the demo does not become stale.
- Persist temporary changes in `sessionStorage`, versioned with the fixture. They survive navigation and refresh within the tab, do not transfer into a real workspace, and reset when the tab session ends, the fixture version changes, or the visitor chooses **Reset demo**.
- Use privacy-preserving aggregate analytics for the acquisition and engagement funnel. Never collect the access code, search text, note/task content, fixture titles, record IDs, email addresses, session identifiers, or free-form errors.

## Implementation Plan

1. Wait for the repository's existing indexed plans and stable core production journey to finish. Reconfirm the final production route, component, permission, and design-system contracts before starting the demo.
2. Extract only stable production compositions into data-agnostic views. Live containers keep their authorised readers and Server Actions; demo containers pass fixture selectors, demo route builders, and reducer callbacks. Do not add `demoMode` branches to production actions.
3. Define and validate a versioned fictional fixture and synthetic PDFs. Use deterministic opaque IDs and a session-relative clock for current deadlines while keeping the historic legal chronology internally coherent.
4. Add the `/demo/*` route tree and dedicated demo shell. A signed-in user may enter, but the shell always presents a fictional demo identity and never reads or reveals the user's organisation.
5. Add one client-side demo state provider and reducer. Every allowed interaction emits a typed demo command, updates the canonical temporary state, derives dependent projections, and persists the state to `sessionStorage`. If storage is unavailable, continue in memory and disclose that refresh persistence is unavailable.
6. Add the guided mission as a compact desktop side panel and mobile sheet. Tour completion is driven by semantic route/command events rather than fragile DOM selectors, and the tour never traps the visitor or blocks free navigation.
7. Add the access boundary. `POST /api/demo/access` accepts a bounded same-origin form submission, compares the configured scrypt hash in constant time, and issues a four-hour signed `HttpOnly`, `SameSite=Lax`, production-`Secure` cookie scoped to `/demo`. Derive the signing key from the session secret and current access-code hash so rotating either invalidates existing access.
8. Treat the demo route layout as the access authority. Proxy may avoid ordinary login redirection, but missing, expired, malformed, or tampered cookies are rejected again by the layout. When the feature flag is disabled, hide landing CTAs and return a non-disclosing unavailable state for direct access.
9. Add an automated dependency-boundary check that rejects demo imports of Supabase clients, `src/lib/actions`, service credentials, Storage upload/signing, AI providers, email, Trigger workers, and production mutation adapters. Static synthetic assets and allowlisted analytics are the only post-entry network activity.
10. Add `noindex, nofollow` metadata, keep demo routes out of sitemap discovery, and prevent query strings or dynamic record identifiers from entering analytics page views.
11. Integrate privacy-preserving Vercel Web Analytics custom events for landing CTA, successful demo entry, tour state, allowlisted feature/action use, reset, exit, signup, and contact conversion. Use no more than two fixed scalar properties per event and keep analytics failure non-blocking.
12. In preview, configure and observe a Vercel WAF fixed-window rule for `POST /api/demo/access`, then enforce ten attempts per ten minutes per supported source key with HTTP 429 before enabling the production flag.
13. Launch behind `DEMO_ENABLED` only after preview verification of access control, rate limiting, analytics, synthetic fixtures, responsive behavior, and the complete guided/free-exploration journey. Review aggregate engagement after 30 days or 50 entrants, whichever is later, before expanding scenarios or personas.

## Interfaces and Data Changes

- Routes: `/demo/access`, `/demo/dashboard`, demo-scoped Client/Matter/Review/Task/Note/Trash routes, and `POST /api/demo/access`. Search remains local and does not place visitor-entered query text in the URL.
- Configuration: `DEMO_ENABLED`, `DEMO_ACCESS_CODE_SCRYPT_HASH`, and `DEMO_SESSION_SIGNING_SECRET`. Secrets remain server-only.
- `DemoFixture`: immutable, schema-validated baseline with `fixtureVersion` and session-relative date inputs.
- `DemoState`: fixture version, session start, tour state, fictional domain records, and temporary lifecycle state.
- `DemoCommand`: a discriminated union covering only the approved matter, note, task, Review, Trash/restore, tour, and reset operations.
- Shared workspace views accept serializable data, route builders, capability presentation, and action handlers. Live and demo containers provide separate adapters at compile time.
- No database schema, RLS, Storage, outbox, background-job, AI, email, or real organisation changes are introduced.

## Testing and Acceptance Criteria

- Correct, incorrect, absent, expired, tampered, and rotated access configurations behave safely and disclose no secret or configuration detail.
- The disabled feature flag removes all demo CTAs and blocks direct entry. Authenticated and unauthenticated visitors cannot cross from demo state into a live organisation.
- The deployed preview proves the WAF rate limit, cookie attributes, same-origin POST handling, direct deep-link behavior, and session expiry.
- The complete demo runs with deliberately invalid Supabase and provider configuration, proving there is no runtime production-data dependency.
- Dependency tests fail whenever a demo module acquires a forbidden production action or provider import.
- Temporary edits survive refresh and demo navigation in one tab, remain absent from an independently opened tab, and return exactly to the baseline after reset or fixture-version change.
- Matter, Review, Task, Note, Activity, counters, Search, and Trash projections remain mutually consistent after every supported command.
- Unsupported controls cannot upload files, mutate the database, invoke providers or workers, send messages, or permanently delete anything.
- Analytics tests permit only the documented event names and properties and prove that visitor-entered text and record identifiers never leave the browser.
- The tour can be skipped, resumed, completed, and restarted without trapping focus, obscuring primary actions, or preventing free exploration.
- Landing and demo experiences pass TypeScript, scoped ESLint, dependency-boundary tests, fixture/reducer tests, production build, `git diff --check`, and browser verification.
- Desktop, mobile, keyboard-only, screen-reader naming, light/dark appearance, reduced motion, 320px, wide desktop, and 200% zoom checks pass with explicit scroll ownership, visible focus, 44-by-44-pixel touch targets, and no page-level horizontal overflow.

## Assumptions

- All other currently indexed plans take implementation priority. This plan is the final planned product tranche unless the user explicitly reprioritises it later.
- The access code controls rollout and casual access only; no confidential or production-derived information enters the demo.
- Demo changes are intentionally non-transferable to signup or a real workspace.
- The Vercel project will enable a plan/configuration that supports the approved custom-event and WAF behavior before `DEMO_ENABLED` is turned on; any billing change requires separate owner approval.
- Future persona tours or alternate legal scenarios require evidence from the first demo and are outside v1.

## Open Questions

None.
