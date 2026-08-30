# Component contracts

Use components in [`src/components/ui/`](../../src/components/ui/) rather than reproducing their appearance inside a feature. Feature components control layout and content; shared components control visual and interaction contracts.

## Button

Use [`button.tsx`](../../src/components/ui/button.tsx).

- `default`: the principal action in the current region.
- `secondary`: a contained neutral action.
- `outline`: a lower-emphasis action on a page or panel.
- `ghost`: toolbar or quiet action.
- `destructive`: deletion or irreversible action; confirmation is still required when consequences are material.
- `link`: an action that should read as an inline link.

Sizes are `sm`, `md`, `lg`, and `icon`. The shared button supplies focus, disabled, loading, radius, and effective touch-target behaviour. Do not override its colour or geometry to create an unnamed variant. Promote a recurring need into the typed component API and gallery.

Icon-only buttons require an `aria-label` and should normally expose a tooltip or visible adjacent label when the meaning is not universal.

### Descriptive action language

Visible action text is the default. Use concise verb-led labels such as `View PDF`, `Reprocess`, `Assign document`, or `Delete note`; an icon may reinforce the label but must not carry an unfamiliar meaning alone.

Icon-only buttons are permitted only when all of the following are true:

- the action is universally understood in context, such as Close, Back, Expand/Collapse, or More actions;
- available space genuinely requires the compact presentation;
- the button has a programmatic accessible name;
- an accessible tooltip appears promptly on both hover and keyboard focus rather than after a long delay;
- touch users have an equally understandable presentation without relying on hover.

Primary actions, destructive actions, workflow transitions, unusual legal operations, and ambiguous icons always use visible text. Native `title` text alone is not an adequate tooltip or explanation. In dense repeated rows, group secondary actions in a clearly labelled menu instead of presenting a strip of unexplained icons.

## Badge

Use [`badge.tsx`](../../src/components/ui/badge.tsx) for status and compact classification.

- `default`: active/processing/selected primary state.
- `success`: complete or ready.
- `warning`: attention, duplicate, or review required.
- `danger`: failed or critical.
- `incoming` / `outgoing`: legal-document direction only.
- `muted`: queued, inactive, or neutral metadata.
- `outline`: non-status classification.

In a repeated list or table, select one `fixedWidth` (`sm`, `md`, `lg`, or `xl`) for the entire collection and use it for every row. Choose the size against the longest approved label in that collection; labels must never escape, resize, or misalign their badge. If the vocabulary outgrows the chosen width, enlarge the whole collection or revise the vocabulary rather than overriding one row. A badge colour must never be the only carrier of meaning.

## Input and labels

Use [`input.tsx`](../../src/components/ui/input.tsx) with [`label.tsx`](../../src/components/ui/label.tsx).

- Preserve a visible label unless an established accessible pattern provides an equivalent name.
- Connect descriptions and error messages with ARIA attributes.
- Use the component's error contract instead of feature-local red borders.
- Inputs are `44px` on mobile and may use compact desktop density at established breakpoints.
- Do not use placeholder text as the only label or instruction.

## Dialogs and confirmations

Use Radix-backed [`dialog.tsx`](../../src/components/ui/dialog.tsx) and [`ConfirmDialog.tsx`](../../src/components/ui/ConfirmDialog.tsx).

- Every dialog has a title; add a description when the consequence or task is not self-evident.
- Actions stack safely on phones and align horizontally on larger screens.
- Destructive operations state what will happen and use explicit action text such as “Delete document,” not “Yes.”
- Long or multi-step phone workflows should become a drawer or dedicated screen instead of an oversized dialog.
- Do not recreate focus trapping, escape handling, overlay, or close behaviour in feature code.

## Menus, avatars, and navigation

Use the shared Radix dropdown and Avatar implementations. A small avatar inside a button does not reduce the button's required target size.

The authenticated desktop navigation contract is fixed: a `64px` rail expands to `224px` on hover or focus and overlays content. Mobile uses the accessible navigation drawer. New navigation items belong in the shared navigation configuration, not in a page-local sidebar.

## Cards and surfaces

Prefer the shared `Card` composition or a semantic surface using `--surface`, `--border`, and `--radius-md`. Do not introduce glass or decorative elevated variants. The current `glass` and `elevated` Card API names are legacy surfaces and must not be used for new UI until the shared component is normalized to Civic Ink tokens.

Cards group related information; they are not default wrappers around every section. Prefer dividers and clear headings when a card does not add meaningful grouping.

## Compact operational tables

Use the shared `Table` composition for dense desktop collections whose columns have meaningful relationships. Its shared cells provide the Civic Ink compact row rhythm, semantic separators, sticky-header option, hover treatment, and selected-row treatment.

- Keep only information needed to identify, compare, and select a row. Move explanation, history, and long metadata into the selected detail pane or canonical record view.
- Every column must support a repeated comparison or the row’s immediate action. Remove columns that merely repeat the detail pane or expose an unavailable future workflow.
- Use a visible verb label for the row action. The item identity may also be a button when both controls perform the same selection.
- At mobile breakpoints, replace the table with a prioritized card or drill-down list rather than compressing columns.
- Loading tables reuse the same column definition and shared cell geometry as their loaded state.

## Loading, empty, and error states

- Loading preserves layout where practical and says what is happening when users may wait.
- Use the shared `Skeleton` primitive for placeholder surfaces. The feature layout owns its geometry: reproduce the final row, card, table-column, or pane structure at each breakpoint so loading does not resize or shift the workspace when content arrives.
- Keep skeletons non-interactive and hidden from the accessibility tree, pair the region with a plain-language loading status, and render a static semantic placeholder when reduced motion is requested.
- Processing uses real stages and a spinner/current-stage treatment; never fabricate a percentage.
- Empty states explain why the region is empty and expose the next useful action when one exists.
- Errors state the problem in plain language and offer retry, correction, or escalation where possible.
- Destructive and failure states use semantic danger tokens; reviewable or recoverable states normally use warning.

## Workspace and pane headers

In document review, queue, table, and split-pane workflows, separate stable chrome from moving content.

- The stable header contains the selected record's identity, current workflow state, essential interpretation context, and primary actions.
- Secondary metadata belongs in the scrollable body or an appropriate drawer.
- Header actions use shared buttons and remain keyboard reachable at every supported viewport.
- Desktop pane bodies may scroll independently; the header must not scroll away with them.
- Mobile should use a compact sticky identity header or bottom action bar only when persistence is necessary for the task.
- Avoid freezing so much content that the usable body becomes cramped.

### Matter section workbars

Non-canvas Matter sections use one stable ordering so controls remain predictable across sections:

1. View or scope switchers at the left.
2. Optional Search, result interpretation, or freshness context in the flexible middle.
3. Collaborators, Filters, and other secondary controls at the right.
4. The current primary action as the rightmost control.

Omit slots that do not apply without reordering the remaining controls. Do not repeat the selected section name, explanatory hero, totals that do not affect decisions, or the same create action again inside the scrolling body. Mobile may wrap or adapt this workbar, but retains the same semantic order and does not introduce page-level horizontal overflow.
