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

In a repeated list or table, select one `fixedWidth` (`sm`, `md`, or `lg`) for the collection and use it for every row. A badge colour must never be the only carrier of meaning.

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

## Loading, empty, and error states

- Loading preserves layout where practical and says what is happening when users may wait.
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
