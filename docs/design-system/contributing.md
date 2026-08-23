# Contributing UI

## Before implementation

1. Read the relevant design-system documents and inspect `/dev/design-system`.
2. Search for an existing shared component or domain pattern.
3. List the page's real states: default, loading, empty, error, disabled, success, destructive confirmation, and long content.
4. Decide the desktop and mobile presentations, stable chrome, and explicit scroll owner before coding.
5. Confirm that the work does not alter business logic, routing, data contracts, or permissions unless those changes are separately authorized.

## During implementation

- Use semantic tokens and typed component variants.
- Keep feature styling about composition, not reimplementation of primitives.
- Extend a shared component only when the new contract recurs or clearly belongs to that primitive.
- Do not add a feature-local colour/status map when a domain pattern already exists.
- Use real buttons, links, inputs, tables, and headings rather than clickable generic containers.
- Label actions with concise visible verbs by default. Treat every icon-only button as an exception that requires universal meaning, an accessible name, prompt hover/focus help, and a clear touch presentation.
- Forward refs and accessible attributes when extending an interactive primitive.
- Add a representative reusable state to `/dev/design-system`.

## New component checklist

A shared component must document or type its supported variants, sizes, loading/disabled/error behaviour, keyboard interaction, accessible name, responsive behaviour, and light/dark appearance. Avoid APIs that accept arbitrary colour names or styling modes such as `glass`.

## Validation

Run checks proportional to the change. For a new page or reusable pattern, the minimum is:

1. `npx tsc --noEmit`
2. ESLint on the files changed
3. Relevant repository tests
4. `git diff --check`
5. `npm run build` before declaring a migration or cross-cutting UI change complete
6. Browser checks in light and dark at phone and desktop sizes
7. Keyboard and focus verification
8. Loading, empty, error, long-content, and destructive states
9. Scroll every content region and verify that identity/context/actions remain available, scrollbars move only their intended bodies, and there are no nested scroll traps or layout shifts
10. Automated accessibility/visual smoke coverage when the page is a pilot workflow or introduces a shared pattern

Report exact commands and results. A timed-out, interrupted, scoped, or failing check must not be described as passing.

## Review questions

- Does the page make the primary task and next action obvious?
- Does every colour express an approved semantic role?
- Are repeated statuses aligned and equal in width within their collection?
- Does mobile retain the complete workflow using an appropriate presentation?
- Is there one deliberate scroll owner per page or pane, with stable workspace chrome and discoverable semantic scrollbars?
- Do selection, loading, and live updates preserve spatial continuity instead of moving the user's context unexpectedly?
- Are all controls reachable, named, focused visibly, and large enough to operate?
- Are primary, consequential, and ambiguous actions described with visible text rather than discoverable only through icons or delayed hover text?
- Are the shared component, gallery, and documentation still consistent?
- Did the change introduce raw colours, decorative gradients, arbitrary radii, or duplicate primitives?

If a new design decision is required, stop and obtain it before creating a one-off convention. Once decision-complete, update the canonical plan when appropriate and update this living specification with the implemented contract.
