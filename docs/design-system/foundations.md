# Foundations

## Colour and themes

Feature code consumes semantic roles, never Civic Ink's literal colour values. Light and dark appearances define the same contract in [`src/app/globals.css`](../../src/app/globals.css).

| Purpose | Tokens |
| --- | --- |
| Page and panels | `--bg`, `--surface`, `--surface-hover`, `--bg-overlay` |
| Borders | `--border`, `--border-strong`, `--border-subtle` |
| Primary action | `--primary`, `--primary-hover`, `--accent-muted`, `--on-accent`, `--accent-ring` |
| Text | `--text-primary`, `--text-secondary`, `--text-muted`, `--text-disabled` |
| Navigation | `--sidebar-bg`, `--sidebar-hover`, `--sidebar-text`, `--sidebar-active`, `--sidebar-accent`, `--on-sidebar` |
| Success | `--success`, `--success-muted`, `--on-success` |
| Warning/review | `--warning`, `--warning-muted`, `--on-warning` |
| Failure/destructive | `--danger`, `--danger-hover`, `--danger-muted`, `--on-danger` |
| Legal direction | `--incoming`, `--incoming-muted`, `--outgoing`, `--outgoing-muted` |
| Modal overlay | `--scrim` |

Do not use semantic colours as decoration. Green means success, amber means attention or review, and red means failure or destructive action. Primary blue-green communicates action, selection, processing, or outgoing direction according to context.

Do not add named-theme switches or arbitrary user colour controls. Civic Ink is the only named theme; light and dark are appearances of that theme.

## Typography

- Geist Sans is the interface face.
- Geist Mono is for GST identifiers, reference numbers, document codes, extracted metadata, dates, and other values that benefit from character-level scanning.
- Page headings are normally `20–28px`; the `text-page-title` utility is `24px/600`.
- Section headings use `text-section-heading` (`16px/600`).
- Body content uses `text-body` (`14px/400`).
- Metadata and supporting labels use `text-caption` (`12px/500`).
- Avoid all-caps body text. Uppercase is acceptable for short metadata labels with restrained letter spacing.

Use the smallest number of weights necessary to establish hierarchy. Do not compensate for weak hierarchy with colour or oversized type.

## Geometry and elevation

- Controls: `var(--radius-sm)` (`6px`).
- Cards and panels: `var(--radius-md)` (`8px`).
- Larger contained compositions may use `var(--radius-lg)` (`10px`).
- `var(--radius-full)` is limited to circular avatars, dots, and an established indicator that is semantically a pill.

Use borders first. Use `--shadow-xs` or `--shadow-sm` for modest separation, `--shadow-md` for overlaying panels, and `--shadow-xl` for dialogs or drawers. Avoid stacking borders, glow, and heavy shadow on the same surface.

## Density and spacing

Civic Ink is compact, never cramped.

- Default body text is `14px`; supporting metadata is `12px`.
- Related controls generally use `8px` gaps; distinct groups normally use `16–24px` separation.
- Page padding should reduce on phones and grow at established breakpoints.
- Preserve clear grouping and alignment before adding more whitespace.
- Dense desktop controls may be visually shorter than `44px`, but touch presentations and effective targets must remain at least `44px × 44px`.

## Icons and motion

- Use Lucide icons already used by the application.
- Pair unfamiliar or consequential icons with visible text or an accessible name.
- Do not use emoji as operational icons.
- Motion explains state change; it is not decoration. Prefer colour/fade transitions using `--duration-fast` or `--duration-base`.
- Spinners indicate active indeterminate work. Stage-based processing must not invent a percentage.
- Respect reduced-motion preferences and avoid continuous animation except for an active progress indicator.

## Scrollbars and scrolling

Scrollbars are quiet navigation controls, not decoration.

- Desktop scrollbars should normally be approximately `5–6px` wide with a transparent track, a muted semantic thumb, and stronger hover/active feedback.
- Support thin scrollbars across engines, including `scrollbar-width: thin` where applicable.
- Do not use raw palette values for scrollbar styling and do not hide scrollbars completely.
- A scrollbar belongs to the content region it moves. It must not appear to move a fixed pane header or unrelated page chrome.
- Independent desktop panes may use contained overscroll where it prevents scroll chaining into the page.
- The application must remain operable with platform scrollbar preferences and keyboard scrolling.
