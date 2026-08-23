# Accessibility

CaseChain targets WCAG 2.2 AA. Accessibility is part of every component contract and page acceptance test.

## Interaction

- Every interactive element is keyboard operable and has a visible focus indicator.
- Touch targets are at least `44px × 44px` in effective area and must not overlap adjacent targets.
- Icon-only actions have accessible names. Do not rely on `title` alone for essential naming.
- Disabled and loading states remain understandable; loading actions prevent duplicate submission.
- Dialogs, drawers, menus, and popovers use established accessible primitives with focus management and Escape behaviour.

## Meaning and content

- Colour never communicates status by itself.
- Form fields have programmatic labels, descriptions, and errors.
- Headings follow a logical hierarchy.
- Links and buttons use descriptive text, especially for destructive or workflow-changing actions.
- Tables use actual table semantics when data relationships require rows and columns.
- Empty, error, processing, and success messages are written in plain language.

## Dynamic processing

Live processing updates should announce meaningful stage changes without announcing every visual animation. Preserve focus and the item's position as its state changes. Use a suitable live region for important asynchronous completion or failure messages.

## Visual access

- Verify light and dark contrast rather than assuming semantic tokens guarantee it.
- Support `200%` zoom without loss of functionality or page-level horizontal scrolling.
- Respect reduced motion.
- Do not place essential text inside images or canvas-only presentations.
- Provide a list alternative for graph-based matter timelines.

## Minimum manual check

Complete a page using only the keyboard; inspect visible focus; open and close every overlay; verify labels in the accessibility tree; test at `200%` zoom and a phone viewport; and confirm that status remains understandable without colour.

