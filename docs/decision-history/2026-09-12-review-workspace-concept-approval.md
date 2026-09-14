# Review workspace concept approval and concept-quality baseline

- **Decision / date:** `WORK-REVIEW-CONCEPT-2026-09-01` resolved on **2026-09-12** by the user after iterative review of `/dev/review-workspace-concept`.
- **Canonical plans:** [Work Orchestration and Review](../plans/features/2026-08-25-work-review-activity-notifications.md#workspace-interaction-contracts) and [CaseChain Design-System Overhaul](../plans/design-system/2026-08-20-casechain-design-system-overhaul.md#decisions).
- **Affected outcomes:** D08 live Review producer/resolver/UI and the Review-dependent portions of D05, D11, and D13. This approval resolves the visual gate; it does not implement or deploy the live Review workflow.

## Approved Review direction

- Desktop uses a compact filterable queue and stable selected-item sidebar. Mobile retains list-to-detail navigation rather than compressing the table.
- The desktop queue uses the approved 56px minimum two-line row rhythm. Type, Priority, and Status filters live in their applicable column headings; Search and item count remain in the workbar.
- User-facing Review state is only `Needs review` or `Closed`. Opening an item does not assign, lock, or move it to an `In progress` state. Source replacement closes an obsolete item without exposing `Superseded` as a user-facing status.
- Priority is deterministic and separate from status. Its rationale remains accessible without repeating a visible priority explanation throughout the detail pane.
- The selected header is compact and contains identity, status/type, then priority and creation age. Redundant eyebrow labels are omitted.
- The detail has only Evidence and Decision tabs. Evidence is grouped and numbered with clear citation language; available citations open the shared PDF workspace at the exact page. Derived comparisons remain visibly distinct from source quotations.
- Decision options name the outcome and consequence plainly. Confirmation uses the shared dialog composition. A fixture cannot invoke the live record command.
- There is no item-history tab. Durable decisions remain append-only records and material business events belong in Activity.

## Review friction converted into a future quality gate

The first passes placed too much information in individual cells, diverged from approved table and sidebar anatomy, used oversized rows and pane headers, repeated labels and source actions, introduced unclear terms and speculative states, and presented evidence, decisions, and confirmation with weak hierarchy. The reviewer had to identify these foundational inconsistencies across many iterations before the concept became calm and understandable.

Future concepts must therefore arrive as internally reviewed proposals:

- inspect the closest approved concept and shared design-system pattern before composing the page;
- use shared density, table, pane, source-viewer, and dialog contracts from the first pass;
- remove redundant labels, repeated metadata/actions, unexplained terminology, and unapproved workflow states;
- test the information hierarchy with representative partial, long, closed, responsive, and dark/light states;
- perform a deliberate visual critique and refinement pass before requesting product approval;
- apply creativity to hierarchy, grouping, rhythm, and progressive disclosure—not decorative novelty or feature-local styling.

## Implementation impact

The visual approval unblocks planning and later implementation of the smallest secure Review producer-to-decision closure. The next implementation owner must still build and verify the live reader, typed producers/resolvers, optimistic revision checks, replay safety, authority, source-version validation, Activity integration, server pagination/filtering, responsive behavior, accessibility, and deployment acceptance. Existing legacy Review queries or generic status mutations do not satisfy this decision.

- **Resume owner:** next implementation coordinator when D08 or a dependent bounded tranche is explicitly authorised.
- **Implementation state / commit:** visual concept and documentation decision recorded; live Review implementation not started by this approval.
