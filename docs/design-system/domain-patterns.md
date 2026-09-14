# Domain patterns

Domain patterns translate CaseChain business state into consistent presentation. Prefer typed domain components that accept enums or state names rather than colour names.

## Document intake and processing

The current Document Inbox / Upload Queue vocabulary is:

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

Document Inbox queue scopes use task language rather than recency language:

| Scope | Meaning |
| --- | --- |
| Action required | A human decision or recovery is currently required |
| Processing | The document is in an active pipeline stage |
| Completed | Processing or handoff is stable and no current action is required |
| All documents | Every accessible queue item regardless of state |

Do not use `Recent` as a workflow scope. Recency is a sort or date filter, not an explanation of what the user must do.

Ownership scope is separate from workflow status. When the current capability can see shared Intake, place a compact `My uploads` / `All uploads` control before Search; remember the choice per user and default ordinary contributors to `My uploads`. Users without organisation-intake visibility do not receive `All uploads`. Visibility never implies permission to place, retry, discard, or resolve.

Status and other field-specific filters belong in their table-column headings on desktop when the column remains visible. Keep scope and Search in the collection workbar. On presentations without table headings, expose the same filter as one compact labelled control near Search; never hide an active filter merely because the layout removed its desktop column.

The unselected Upload Queue is a compact table with document identity/classification, equal-width status, uploader identity, source, destination/stage, and received date. The uploader's visible name and avatar are first-class comparison context. Workflow actions live in the selected sidebar rather than being compressed into the row. When the sidebar opens, keep document, status, and uploader columns and remove repeated source, destination, and received columns instead of squeezing them.

On wide desktop, selection establishes one stable split-pane chrome row: the queue workbar occupies the table's approximately 60% pane and the sidebar tabs occupy the unchanged approximately 40% pane. Opening a source swaps the queue workbar and table for the PDF toolbar and viewer inside that left pane only. The sidebar header, width, body scroller, and action footer must not move when source mode opens or closes.

The selected-document sidebar separates scan-first context from complete extraction data:

1. **Overview:** dominant document type and legal direction, subordinate filename, current status, up to three key evidence items, a state-specific decision/outcome section, and intake details.
2. **Extracted data:** one compact AI-verification header followed by predictable document metadata, parties/identifiers, deadlines, financial facts, and other applicable typed sections. Each section is one bounded panel with a quiet header and a dense two-column field grid; every field keeps its label, value, and source action together. An odd final field spans the panel rather than leaving a visually broken empty cell.
3. **Fixed footer:** `View original PDF` plus the current primary workflow action.

Allow one state-specific summary and at most three key findings on Overview. A key finding always has a type, primary value, short explanation, and explicit source-page action when evidence exists. Different document types may change values and applicable extracted-data sections, but never the tab anatomy or action location. Processing, completed, duplicate, and failed records use their real state name and semantic treatment; warning language/background is not a universal sidebar heading.

Do not leave state explanation as an unstructured sentence or let it occupy the sidebar's prime region as a large generic callout. After identity/status, lead with the source-backed evidence or processing facts that let the user understand the document. Follow them with one lightweight decision/outcome section: a plain section heading, explicit `Decision required` or `No action needed` cue, outcome title, consequence, and one semantic leading rule. Do not render it as another tinted alert card with an icon tile. This evidence-before-interpretation order is stable across document states.

Opening and closing the Document Inbox sidebar uses the shared `--duration-fast` and `--ease-smooth` transition with no entry delay. The sidebar header and body reveal/collapse as one pane, and the queue changes between condensed and full columns in the same state change; never restore columns only after the pane transition finishes. This dense collection is an intentional exception to the default structural duration because a slower expanding table makes document rows feel elastic. Switching between queue and source mode does not animate or move the already-open inspector. Reduced-motion presentation changes state without spatial movement.

Processing rows use a same-line stage marker, not a fabricated percentage or a third line that changes row height. Name the current stage and encode completed/current/future stages with text plus a compact segmented marker. When that row is selected, remove its duplicate row marker and replace it with one compact processing summary that states what is happening, one truthful completed-work fact, and whether user action is required. Do not repeat a fully labelled stage rail in the sidebar. A live collaborator claim uses the same one-place rule and always names the actor. In a queue row it is a quiet secondary activity label with a restrained pulsing dot, not a competing badge; in the selected sidebar it may become a compact structural notice because it changes action availability. The pulse must stop under reduced motion; text continues to communicate the live state.

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
