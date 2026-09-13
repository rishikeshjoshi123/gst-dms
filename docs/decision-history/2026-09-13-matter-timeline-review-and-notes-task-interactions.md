# Matter Timeline, contextual Review, and Notes Task interactions

- **Decision / date:** approved through product discussion on **2026-09-13**.
- **Canonical plans:** [Matter Workspace and Procedural Timeline](../plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md#edge-and-relationship-interaction-contract), [Matter Notes and Cited Case Brief](../plans/features/2026-08-25-notes-and-case-brief.md#message-authoring-and-lifecycle), and [Work Orchestration and Review](../plans/features/2026-08-25-work-review-activity-notifications.md#review-items-and-decisions).
- **Affected outcomes:** D08 relationship Review and Notes-created Task entry; D11 graph interaction, relationship inspection/editing and candidate Review. This record changes intended interaction and acceptance; it does not implement or deploy them.

## Approved decisions

- Timeline has two ordinary visible states: read-only **View** and permission-gated **Edit timeline**. Edit contains add, correct and reason-required archive; it does not expose separate top-level Add or Correct modes. View retains restrained edge feedback and read-only inspection, while Edit uses stronger whole-path feedback and permitted mutations.
- A relationship's complete parent-to-child path is selectable. Visually grouped branches use deterministic parallel strokes/hit regions rather than literally sharing geometry, so hovering or focusing one full path never needs an ambiguous chooser. Layout and temporary dragging preserve minimum node, label and edge-target spacing.
- Relationship Review is contextual, not a global Timeline mode. **Review on timeline** opens the same Review item/revision in a constrained graph state, offers only its allowed accept/correct/reject decisions, and may be cancelled without mutation. Resolving from graph or queue invokes the same typed resolver, records one decision and Activity event, and closes the queue item atomically.
- The document inspector retains **Overview**, **Relationships**, and **Notes** only. A fourth Needs-attention tab is rejected. A compact conditional Overview summary remains subject to concept validation and must be omitted if it adds more noise than comprehension.
- Notes supports explicit Task creation both while composing and from an existing message. One responsive compact Task draft is reused in the full Notes workspace and narrow document inspector. It collects title, one assignee, optional due date/time and priority; the resulting Task retains the exact immutable Notes origin and Notes displays only its linked summary/current route.
- Archiving a relationship is not destructive deletion. It requires the governed reason where applicable, preserves decision history and emits the canonical Activity event. Mere viewing, hovering and layout movement do not create Activity.

## Implementation and concept impact

The current approved concepts do not demonstrate all of these states. Before implementation acceptance, revise the Matter concept for distinct branch targeting, View/Edit and contextual Review; revise Notes for the shared Task draft and existing-message action; and test the optional compact attention summary with empty, populated, long-content, narrow and mobile fixtures. Preserve prior D11 graph/manual-relationship evidence as evidence for the earlier contract while reopening only the changed interaction and integration checks.
