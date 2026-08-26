# Domain patterns

Domain patterns translate CaseChain business state into consistent presentation. Prefer typed domain components that accept enums or state names rather than colour names.

## Document intake and processing

The current Document Hub vocabulary is:

| State | Treatment |
| --- | --- |
| Queued | Muted badge; explain what it is waiting for |
| Processing | Primary badge with spinner; show the current real stage |
| Ready | Success badge; expose the review or placement action |
| Review | Warning badge; explain the required decision |
| Duplicate | Warning badge; show the related evidence |
| Failed | Danger badge; show the cause and a recovery action |

Use the established stages `Queued → Extracting → Matching → Ready`. Name the current stage and completed stages. These stages do not take equal time, so a stage display must not be presented as a measured percentage.

Queue rows remain stable while updates arrive in place. Do not reorder an active item merely to animate progress. Announce meaningful live changes without repeatedly interrupting assistive technology.

## Status badges in collections

Status sizing is a collection-level decision:

- Choose one width that fits that collection's vocabulary.
- Use the same width and alignment for every row, including failed and long-label states.
- Do not add padding to individual badges to make one status fit.
- Status text must remain contained within the badge. If the vocabulary cannot fit the selected width, change the whole collection's width or revise the labels; never allow one long value to overflow or widen only its own row.

## Matters and legal direction

- Active/selected matter state uses the primary semantic family.
- Inactive/closed neutral state uses muted treatment unless a warning or failure genuinely applies.
- Incoming and outgoing colours are reserved for legal-document direction and must be paired with text or an icon.
- On mobile, replace the timeline graph with the chronological list fallback. Preserve document selection and access to details.

## Confidence, deadlines, and review

- Confidence is evidence about an automated result, not success. Low or uncertain confidence uses warning/review language and explains what needs verification.
- Do not communicate confidence through colour alone or imply mathematical precision the system does not possess.
- Deadline colour represents urgency: neutral for routine, warning for approaching attention, danger for overdue or critical.
- A review requirement is not an error. Use warning unless processing actually failed.

## Lists, tables, and split panes

- Desktop tables and dense lists need aligned metadata, stable actions, and explicit empty/error/loading states.
- Mobile uses prioritized cards or drill-down lists rather than compressed tables.
- Split-pane review becomes list/detail navigation on mobile. A user must always have a clear route back to the list.
- Bulk selection on mobile uses selection mode and a bottom action bar rather than tiny checkboxes and distant toolbar actions.
- PDF review moves secondary metadata/actions into a suitable drawer when space is constrained.
