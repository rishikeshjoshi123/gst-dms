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

The canonical cross-domain status and resumption contract lives in the [CaseChain Product Architecture Portfolio](./platform/2026-08-24-product-architecture-portfolio.md#portfolio-status-and-resumption-contract). As of 2026-08-29, the fourteen child domains comprise nine approved plans, zero decision-complete proposed plans, four in-progress implementation/revision tracks, and one deliberately deferred, not-archived domain. Every archived decision-complete proposed child plan has now passed final approval. The umbrella portfolio remains proposed until External Acquisition and Imports is archived, but planning no longer blocks implementation.

A fresh planning task should read `AGENTS.md`, this index, the portfolio status table, and only the plan for the active domain. It must not reconstruct approved decisions from chat history. Organisation Administration remains in progress, but its identity/RBAC foundation is a completed foundation tranche. Document Record and File Lifecycle is in progress: direct-matter and global Inbox canonical upload, placement, recovery, staged-source verification, controlled staging transfer, and the non-destructive retirement evidence inventory are complete. The canonical next action is to implement and independently verify the approved durable outbox dispatch, organisation-aware draining, retention/compaction, explicit reprocess, and structured Vertex failure contracts. A separate fail-closed staged-source purge with content-free tombstones is approved as the following tranche; adapter removal remains separately gated. Platform Operations must ship and pass its gates before rollout beyond the controlled pilot. External Acquisition and Imports remains deliberately deferred until representative spreadsheets are available.

## Plan index

### Design system

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Design-System Overhaul](./design-system/2026-08-20-casechain-design-system-overhaul.md) | `in-progress` | 2026-08-23 |
| [Public Brand and Landing Page](./design-system/2026-08-28-public-brand-and-landing-page.md) | `in-progress` | 2026-08-29 |

### Features

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Universal Search and Evidence Retrieval](./features/2026-08-24-universal-search-and-evidence-retrieval.md) | `approved` | 2026-08-27 |
| [Work Orchestration, Review, Activity, Notifications, and Today](./features/2026-08-25-work-review-activity-notifications.md) | `approved` | 2026-08-27 |
| [Document Hub, Ingestion, Placement, Relationships, and Workbench](./features/2026-08-25-document-hub-ingestion-and-workbench.md) | `approved` | 2026-08-25 |
| [Matter Workspace and Procedural Timeline](./features/2026-08-25-matter-workspace-and-procedural-timeline.md) | `approved` | 2026-08-27 |
| [Matter Notes and Cited Case Brief](./features/2026-08-25-notes-and-case-brief.md) | `approved` | 2026-08-27 |
| [Verified Deadlines and Matter Financials](./features/2026-08-26-deadlines-and-financials.md) | `approved` | 2026-08-26 |

### Platform

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Product Architecture Portfolio](./platform/2026-08-24-product-architecture-portfolio.md) | `proposed` | 2026-08-29 |
| [Document Record and File Lifecycle](./platform/2026-08-24-document-record-and-file-lifecycle.md) | `in-progress` | 2026-08-29 |
| [AI Extraction, Provenance, and Model Lifecycle](./platform/2026-08-24-ai-extraction-and-model-lifecycle.md) | `in-progress` | 2026-08-29 |
| [Hierarchical Resource Trash, Retention, and Purge](./platform/2026-08-24-resource-trash-retention-and-purge.md) | `approved` | 2026-08-29 |
| [Selective Realtime Delivery, Freshness, and Unread State](./platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md) | `approved` | 2026-08-27 |
| [Organisation Administration, Team Access, and Personal Settings](./platform/2026-08-26-organisation-administration.md) | `in-progress` | 2026-08-27 |
| [Platform Operations](./platform/2026-08-27-platform-operations.md) | `approved` | 2026-08-27 |

### Operations

| Plan | Status | Updated |
| --- | --- | --- |
| [Project Portal and GitHub Pages](./operations/2026-08-27-project-portal-and-github-pages.md) | `in-progress` | 2026-08-27 |
