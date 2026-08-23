# Responsive behaviour

Responsive CaseChain layouts adapt the task; they do not scale down a desktop canvas.

## Required viewport range

Support the application from a `320px` phone viewport through wide desktop layouts and at `200%` browser zoom. Build mobile and desktop behaviour in the same change.

## Shell

- Desktop: reserve `64px` for the collapsed rail. Expansion to `224px` overlays content and must not cause page reflow.
- Keyboard focus expands the rail just as hover does.
- Mobile: hide the rail and use the shared modal navigation drawer.
- Page titles, breadcrumbs, theme controls, and account controls must not collide or force horizontal scrolling.

## Stable workspace chrome

Stable workspace chrome is a core Civic Ink principle. In long operational workflows, users must retain the context needed to understand and act on the content they are scrolling.

A desktop workspace should normally use this anatomy:

```text
Workspace or pane
├── Header: identity, current state, interpretation context, primary actions
└── Body: the independently scrolling content
```

- Implement the pane as a bounded `flex` or grid region with `min-height: 0` and `overflow: hidden`.
- Keep the header outside the scrolling body and prevent it from shrinking.
- Give the body the remaining space with `min-height: 0` and `overflow-y: auto`.
- Prefer this structural separation over applying `position: sticky` to a header inside an accidental scroll container.
- A subtle separator or small shadow may appear after content scrolls beneath the header; do not add permanent heavy elevation.
- Keep selected-object identity and high-frequency actions available. Do not freeze decorative headings or large metadata sections that unnecessarily reduce the viewport.

For desktop split panes, each pane may own one vertical scroller while its header remains stable. For mobile, avoid multiple narrow scrollers: use one principal page/detail scroller, a compact sticky identity header when needed, and a bottom action bar or action menu for persistent primary actions.

## Scroll ownership

Every page and pane must have one deliberate scroll owner. Accidental nested scrolling is a defect.

- The application shell remains stable while the active workspace consumes the available height.
- Page-level horizontal scrolling is not allowed.
- Contained regions may scroll horizontally only when their information cannot be faithfully reformatted.
- Sticky table headings, filters, or bulk-action context are appropriate when users need them to interpret the moving rows.
- Preserve list scroll position when navigating to and back from mobile detail.
- When a different record is selected, deliberately reset or restore its detail position; never inherit an unrelated record's scroll position by accident.
- Live updates occur in place and must not unexpectedly move the item or its controls.

## Adaptation patterns

| Desktop composition | Mobile composition |
| --- | --- |
| Data table | Prioritized card/list with drill-down |
| Split-pane list and detail | Explicit list/detail navigation |
| Timeline graph | Chronological timeline list fallback |
| Persistent metadata panel | Drawer or collapsible section |
| Horizontal action row | Wrapped actions or stacked footer |
| Bulk toolbar | Selection mode with bottom action bar |
| Wide dialog | Phone-sized dialog, drawer, or dedicated page |

Do not hide a capability merely because it does not fit. Change its presentation.

## Layout rules

- Avoid fixed widths for primary page content unless paired with a responsive maximum.
- Use `min-w-0` on flexible children that contain long document names or identifiers.
- Define deliberate wrapping, truncation, and access to the full value.
- Keep the primary action visible without allowing secondary actions to crowd it.
- Horizontal scrolling is acceptable for a contained data region when the information cannot be faithfully reformatted; page-level horizontal overflow is not.
- Preserve consistent badge alignment and row rhythm across breakpoints.
- Reserve approximately final dimensions for loading states so headers, actions, and content do not jump as data arrives.

## Responsive acceptance

At minimum, inspect `320px`, a typical phone width, a tablet/intermediate width, and a wide desktop. Verify long names, keyboard focus, open menus/dialogs, loading, empty, error, and dark mode at more than one viewport. Scroll every independently scrollable region to confirm its intended header and actions remain available, scrollbars belong to the correct body, and no nested scroll trap or unexpected layout shift occurs.
