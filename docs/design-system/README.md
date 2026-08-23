# CaseChain design system

This directory is the living specification for CaseChain's **Civic Ink** interface. Read it before creating or modifying a page, component, responsive layout, or visual state.

The sources of truth have distinct roles:

1. These documents define the current design and contribution rules.
2. [`src/app/globals.css`](../../src/app/globals.css) defines the implemented semantic tokens.
3. [`src/components/ui/`](../../src/components/ui/) contains shared primitives.
4. `/dev/design-system` is the rendered reference for approved states and patterns.
5. [`docs/plans/design-system/`](../plans/design-system/) records why the overhaul was undertaken; it is not the everyday component manual.

When documentation and implementation disagree, do not silently choose one. Treat it as a design-system defect, preserve semantic behaviour, and reconcile the documentation, shared component, and gallery in the same change.

## Civic Ink character

CaseChain is a dense legal operations product. Its interface should feel calm, authoritative, restrained, and precise.

- Use warm neutral surfaces and deep ink navigation.
- Use one restrained action colour; colour is functional, not decorative.
- Prefer borders and hierarchy over shadows and effects.
- Keep information compact without reducing clarity or touch accessibility.
- Preserve stable workspace chrome: identity, interpretation context, and primary actions remain available while long content moves beneath them.
- Preserve the same capability on mobile through task-focused layouts, not scaled-down desktop screens.
- Pair every meaningful colour state with text, an icon, or both.

Decorative gradients, glass effects, arbitrary palette colours, oversized pills, excessive hover movement, and emoji in operational UI are not part of Civic Ink.

## Required reading by task

| Work | Read |
| --- | --- |
| Any UI change | This page and [foundations](./foundations.md) |
| Shared or feature component | [components](./components.md) and [contributing](./contributing.md) |
| Status, processing, review, or legal workflow | [domain patterns](./domain-patterns.md) |
| New page or layout | [responsive](./responsive.md) and [accessibility](./accessibility.md) |
| Final verification | [contributing](./contributing.md) |

## Non-negotiable implementation rules

- Consume semantic tokens such as `var(--surface)`, `var(--text-primary)`, and `var(--danger)`. Do not introduce raw hex/RGB values or Tailwind palette colours in feature UI.
- Reuse a shared primitive before creating a feature-local button, badge, input, dialog, menu, avatar, or card contract.
- Use `6px` control radii and `8px` panel radii through the supplied tokens. Full pills are reserved for circular avatars or established compact indicators.
- Keep the desktop rail collapsed at `64px`; it expands to `224px` on hover or keyboard focus and overlays content without reflow.
- Use mobile drawers, drill-downs, lists, and bottom action bars when desktop tables, graphs, or split panes do not fit.
- Give every page and pane an explicit scroll owner. Desktop split-pane headers remain stable while their bodies scroll independently; mobile normally uses one principal scroller.
- Keep scrollbars thin, semantic, and discoverable. Do not hide them completely or allow page-level horizontal overflow.
- Give actions visible, descriptive labels by default. Do not make users wait for hover text to discover what an ambiguous icon does.
- Provide an effective target of at least `44px × 44px` for touch interaction. A visual control may remain compact when its effective hit area satisfies this requirement without overlapping adjacent targets.
- Within a repeated collection, status badges use one fixed width and alignment. Different collections may choose different widths.
- Support light and dark appearances through the same semantic token names. Components must never branch on the name `Civic Ink`.
- Add approved reusable states to `/dev/design-system` and update these documents when a contract changes.

## New-page recipe

1. Identify the page's primary task, principal action, statuses, empty state, loading state, error state, and destructive actions.
2. Reuse the authenticated shell, breadcrumb system, shared primitives, and existing domain patterns.
3. Design desktop and mobile presentations together. Decide what remains anchored, which region owns scrolling, and what stacks, drills down, becomes a drawer, or becomes a list.
4. Implement only with semantic tokens and typed component variants.
5. Exercise long labels, missing data, errors, loading, empty results, dark mode, keyboard use, and a phone viewport.
6. Add a representative reusable pattern to `/dev/design-system` when the page introduces one.
7. Follow the acceptance checklist in [contributing](./contributing.md).
