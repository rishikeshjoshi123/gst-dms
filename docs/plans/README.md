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

## Implementation entry point

Use the [reusable prompt](../implementation-prompt.md) and its [canonical workflow](./operations/2026-09-08-agent-delivery-workflow.md). The [documentation map](../README.md) routes supporting reads. For selection, use the index below; read the selected contract and necessary dependencies, expanding scope when evidence requires it. The largest domain plans have reading guides. Historical checkpoints are retrieved when relevant.

The [portfolio table](./platform/2026-08-24-product-architecture-portfolio.md#portfolio-status-and-resumption-contract) describes architecture; the [ledger](../delivery-ledger.md) indexes delivery evidence. Approval, implementation, verification and deployment remain distinct. A proposed overview does not approve its scope or invalidate a separately approved child plan. Keep temporary execution records out of this archive.

## Plan index

For product discussion, use the [planning prompt](../planning-prompt.md) and [plan-evolution workflow](./operations/2026-09-10-product-discussions-and-plan-evolution.md). Plan statuses are coarse lifecycle labels, not proof that every capability is implemented. Use coverage links and ledger evidence for that question.

### Design system

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Design-System Overhaul](./design-system/2026-08-20-casechain-design-system-overhaul.md) | `in-progress` | 2026-08-23 |
| [Public Brand and Landing Page](./design-system/2026-08-28-public-brand-and-landing-page.md) | `in-progress` | 2026-08-29 |

### Features

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Universal Search and Evidence Retrieval](./features/2026-08-24-universal-search-and-evidence-retrieval.md) | `in-progress` | 2026-09-08 |
| [Work Orchestration, Review, Activity, Notifications, and Today](./features/2026-08-25-work-review-activity-notifications.md) | `in-progress` | 2026-09-08 |
| [Document Hub, Ingestion, Placement, Relationships, and Workbench](./features/2026-08-25-document-hub-ingestion-and-workbench.md) | `approved` | 2026-09-08 |
| [Matter Workspace and Procedural Timeline](./features/2026-08-25-matter-workspace-and-procedural-timeline.md) | `approved` | 2026-09-08 |
| [Matter Notes and Cited Case Brief](./features/2026-08-25-notes-and-case-brief.md) | `approved` | 2026-09-08 |
| [Verified Deadlines and Matter Financials](./features/2026-08-26-deadlines-and-financials.md) | `approved` | 2026-09-08 |
| [Passcode-Gated Interactive Demo Workspace](./features/2026-09-03-interactive-demo-workspace.md) | `proposed` | 2026-09-03 |

### Platform

| Plan | Status | Updated |
| --- | --- | --- |
| [CaseChain Product Architecture Portfolio](./platform/2026-08-24-product-architecture-portfolio.md) | `proposed` | 2026-09-08 |
| [Document Record and File Lifecycle](./platform/2026-08-24-document-record-and-file-lifecycle.md) | `in-progress` | 2026-09-10 |
| [AI Extraction, Provenance, and Model Lifecycle](./platform/2026-08-24-ai-extraction-and-model-lifecycle.md) | `in-progress` | 2026-09-08 |
| [Hierarchical Resource Trash, Retention, and Purge](./platform/2026-08-24-resource-trash-retention-and-purge.md) | `approved` | 2026-09-08 |
| [Selective Realtime Delivery, Freshness, and Unread State](./platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md) | `approved` | 2026-09-08 |
| [Organisation Administration, Team Access, and Personal Settings](./platform/2026-08-26-organisation-administration.md) | `in-progress` | 2026-09-10 |
| [Platform Operations](./platform/2026-08-27-platform-operations.md) | `approved` | 2026-09-08 |

### Operations

| Plan | Status | Updated |
| --- | --- | --- |
| [Design Partner Pilot Execution Sequence](./operations/2026-08-29-design-partner-pilot-execution-sequence.md) | `proposed` | 2026-09-10 |
| [Project Portal and GitHub Pages](./operations/2026-08-27-project-portal-and-github-pages.md) | `in-progress` | 2026-09-08 |
| [Single-Task Agent Delivery and Verification](./operations/2026-09-08-agent-delivery-workflow.md) | `approved` | 2026-09-10 |
| [Product Discussions and Plan Evolution](./operations/2026-09-10-product-discussions-and-plan-evolution.md) | `approved` | 2026-09-10 |
