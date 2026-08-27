<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

<!-- BEGIN:repository-plan-archive -->
# Repository plans

- Before planning related work, read the relevant finalized plans in `docs/plans/`.
- Save every decision-complete plan under the appropriate domain folder in `docs/plans/` using `docs/plans/_template.md`.
- Use a `YYYY-MM-DD-descriptive-slug.md` filename, update the existing canonical file for revisions, and keep `docs/plans/README.md` indexed.
- Do not store secrets, credentials, private reasoning, brainstorming notes, or transient task checklists in the plan archive.
<!-- END:repository-plan-archive -->

<!-- BEGIN:casechain-design-system -->
# CaseChain UI work

- Before creating or modifying UI, read `docs/design-system/README.md` and the references it routes to for the task.
- Treat `docs/design-system/`, the semantic tokens in `src/app/globals.css`, shared primitives in `src/components/ui/`, and `/dev/design-system` as one design-system contract.
- Reuse shared components and semantic tokens. Do not introduce raw palette colours, decorative gradients, arbitrary radii, glass effects, or feature-local replacements for existing primitives.
- Design desktop and mobile presentations together; preserve capability on mobile and provide effective touch targets of at least 44 by 44 pixels.
- Define explicit scroll ownership for every page and pane. On desktop, keep workspace identity, interpretation context, and primary actions outside the scrolling content body; split panes may scroll independently without scrolling their headers. On mobile, normally use one principal scroller with a compact sticky header or bottom action bar.
- Keep scrollbars thin, semantic, and discoverable rather than hidden. Avoid accidental nested scrolling, page-level horizontal overflow, and layout shifts that move controls or live-updating items unexpectedly.
- Give actions visible, descriptive verb labels by default; icons support labels rather than replace them. Icon-only buttons are limited to universally understood, space-constrained controls, must have an accessible name and prompt hover/focus tooltip, and must never be the sole presentation of an ambiguous, primary, or consequential action.
- Keep repeated status badges equal in width and alignment within a collection, pair colour with text or an icon, and support light, dark, keyboard, loading, empty, error, and long-content states.
- When adding or changing a reusable UI contract, update the shared component, `/dev/design-system`, and relevant `docs/design-system/` documentation in the same change.
- When an approved plan has an approved companion layout or visual pattern, add a compact, curated reference to its GitHub Pages plan detail through `project-portal/plan-visual-references.mjs`. Keep the application gallery and shared components canonical; portal references are explanatory, static specimens rather than a second component implementation.
<!-- END:casechain-design-system -->
