# Repository Plans

This directory contains finalized, decision-complete plans for CaseChain. It is a project knowledge archive, not a storage location for brainstorming notes, private reasoning, or temporary task checklists.

## Working with plans

1. Read relevant existing plans before planning related work.
2. Copy [`_template.md`](./_template.md) into the appropriate domain folder.
3. Name the file `YYYY-MM-DD-descriptive-slug.md`.
4. Complete the plan before adding it to the archive; it must not contain implementation-blocking open questions.
5. Add or update its entry in the index below.
6. Revise the canonical file in place and update its `updated` date. Do not create `v2`, `final`, or `final-final` copies.
7. When an approach is replaced, mark the old plan `superseded` and link both plans through their `related` metadata.

Allowed statuses are `proposed`, `approved`, `in-progress`, `completed`, and `superseded`. Completed and superseded plans remain in their original domain folders so links stay stable.

## Domains

- **Design system:** Visual language, components, accessibility, and UX patterns.
- **Features:** User-facing capabilities and workflow changes.
- **Platform:** Architecture, data, security, infrastructure, and refactors.
- **Operations:** Migrations, releases, maintenance, and incident follow-ups.

Create another domain only after multiple plans justify a stable new category.

## Portfolio handoff

The canonical cross-domain status and resumption contract lives in the [CaseChain Product Architecture Portfolio](./platform/2026-08-24-product-architecture-portfolio.md#portfolio-status-and-resumption-contract). As of 2026-08-27, the fourteen child domains comprise four approved plans, six decision-complete proposed plans awaiting final approval, two in-progress implementation/revision tracks, and two domains without an archived plan. The umbrella portfolio remains proposed until the pending contracts receive final approval.

A fresh planning task should read `AGENTS.md`, this index, the portfolio status table, and only the plan for the active domain. It must not reconstruct approved decisions from chat history. Organisation Administration remains in progress, but its identity/RBAC foundation, canonical membership RLS cutover, hash-only invitation commands, safe acceptance flow, and associated local database acceptance gates are stable as a completed foundation tranche; its remaining approved work stays governed by that plan. The canonical next action is the approved Document Record and File Lifecycle foundation. Platform Operations must ship and pass its gates before rollout beyond the controlled pilot. External Acquisition and Imports remains deliberately deferred until representative spreadsheets are available.

## Plan index

### Design system

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Design-System Overhaul](./design-system/2026-08-20-casechain-design-system-overhaul.md) | `in-progress` | 2026-08-23 |

### Features

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Universal Search and Evidence Retrieval](./features/2026-08-24-universal-search-and-evidence-retrieval.md) | `proposed` | 2026-08-24 |
| [Work Orchestration, Review, Activity, Notifications, and Today](./features/2026-08-25-work-review-activity-notifications.md) | `approved` | 2026-08-27 |
| [Document Hub, Ingestion, Placement, Relationships, and Workbench](./features/2026-08-25-document-hub-ingestion-and-workbench.md) | `approved` | 2026-08-25 |
| [Matter Workspace and Procedural Timeline](./features/2026-08-25-matter-workspace-and-procedural-timeline.md) | `proposed` | 2026-08-25 |
| [Matter Notes and Cited Case Brief](./features/2026-08-25-notes-and-case-brief.md) | `proposed` | 2026-08-25 |
| [Verified Deadlines and Matter Financials](./features/2026-08-26-deadlines-and-financials.md) | `approved` | 2026-08-26 |

### Platform

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Product Architecture Portfolio](./platform/2026-08-24-product-architecture-portfolio.md) | `proposed` | 2026-08-27 |
| [Document Record and File Lifecycle](./platform/2026-08-24-document-record-and-file-lifecycle.md) | `proposed` | 2026-08-25 |
| [AI Extraction, Provenance, and Model Lifecycle](./platform/2026-08-24-ai-extraction-and-model-lifecycle.md) | `in-progress` | 2026-08-25 |
| [Hierarchical Resource Trash, Retention, and Purge](./platform/2026-08-24-resource-trash-retention-and-purge.md) | `approved` | 2026-08-24 |
| [Selective Realtime Delivery, Freshness, and Unread State](./platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md) | `proposed` | 2026-08-25 |
| [Organisation Administration, Team Access, and Personal Settings](./platform/2026-08-26-organisation-administration.md) | `proposed` | 2026-08-27 |

### Operations

| Plan | Status | Updated |
| --- | --- | --- |
| [Project Portal and GitHub Pages](./operations/2026-08-27-project-portal-and-github-pages.md) | `in-progress` | 2026-08-27 |
