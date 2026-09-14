# Document workspace naming

Status: resolved on 2026-09-15. **Document Inbox** is the approved overall workspace label and **Upload Queue** is its processing-focused queue/view label. Product-copy implementation remains separate.

## Problem

`Document Hub` is broad and potentially misleading. The surface is primarily the organisation's durable upload/Intake and processing queue, while the shared `DocumentWorkbench` opens and inspects an individual document from Intake, Matter, Search, Review, Activity or Trash. The user has proposed **Upload Queue** or **Document Inbox**. The user-facing name should communicate what belongs here without implying a second document database or the organisation Review queue.

## Alternatives to test

- **Upload Queue** — clearest if the page is mainly pending, processing, failed and recently placed uploads; it can sound more technical and narrower than the whole durable intake surface.
- **Document Inbox** — approachable and accurately suggests incoming work needing attention; it may need a `Queue` subview or status filters to make processing state explicit.
- **Documents** — familiar and short, but may imply a complete file library.
- **Document Intake** — operationally precise, but may undersell assigned/recent processing handoff.
- **Document Desk** — suggests a working surface, but may be unfamiliar.
- **Uploads** — clear for entry and processing, but too narrow once an item is assigned.
- **Inbox & Documents** — descriptive but long and may blur Intake with the Matter-owned document collection.

## Decision

Use **Document Inbox** for the overall workspace because it owns incoming work, attention states and recent handoff. Use **Upload Queue** for the processing-focused queue/view within that workspace. Keep `/documents` as the canonical route and preserve internal identifiers and historical evidence; changing product copy does not require a data-model rename. This decision does not itself launch the application-copy change.

## Related plan

- [Document Hub, Ingestion, Placement, Relationships, and Workbench](../plans/features/2026-08-25-document-hub-ingestion-and-workbench.md)
