// Curated, static visual references for plan pages. These are documentation
// specimens, not a second implementation of the application component library.
// Add a reference only when it helps explain a decision in the canonical plan.
export const planVisualReferences = {
  'docs/plans/design-system/2026-08-20-casechain-design-system-overhaul.md': [
    { afterHeading: 'Decisions', specimenId: 'civic-ink-primitives' },
    { afterHeading: 'Implementation Plan', specimenId: 'stable-workspace-chrome' },
  ],
  'docs/plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md': [
    { afterHeading: 'Compact stable chrome', specimenId: 'matter-workspace-layout' },
  ],
  'docs/plans/features/2026-08-26-deadlines-and-financials.md': [
    { afterHeading: 'Deadline presentation', specimenId: 'deadlines-financial-layout' },
  ],
  'docs/plans/features/2026-08-25-notes-and-case-brief.md': [
    { afterHeading: 'Brief presentation', specimenId: 'notes-brief-layout' },
  ],
};

// The portfolio's dependency order, adapted into a complete reading sequence.
// Every archived plan must appear here so the public portal never falls back to
// an arbitrary title/date sort.
export const portalReadingOrder = [
  'docs/plans/platform/2026-08-24-product-architecture-portfolio.md',
  'docs/plans/design-system/2026-08-20-casechain-design-system-overhaul.md',
  'docs/plans/platform/2026-08-26-organisation-administration.md',
  'docs/plans/platform/2026-08-24-document-record-and-file-lifecycle.md',
  'docs/plans/platform/2026-08-24-resource-trash-retention-and-purge.md',
  'docs/plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md',
  'docs/plans/features/2026-08-25-work-review-activity-notifications.md',
  'docs/plans/features/2026-08-25-document-hub-ingestion-and-workbench.md',
  'docs/plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md',
  'docs/plans/features/2026-08-25-notes-and-case-brief.md',
  'docs/plans/features/2026-08-26-deadlines-and-financials.md',
  'docs/plans/features/2026-08-24-universal-search-and-evidence-retrieval.md',
  'docs/plans/platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md',
  'docs/plans/platform/2026-08-27-platform-operations.md',
  'docs/plans/operations/2026-08-27-project-portal-and-github-pages.md',
];
