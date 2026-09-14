# Viewer Matter access

Status: post-October product requirement recorded on 2026-09-14; not first-release scope.

## Intended direction

A Viewer should not automatically receive read access to every Matter in an organisation. Owner/Admin should explicitly choose which Matters a Viewer may access. Matter-scoped access must intersect with the Viewer read-only ceiling and must fence documents, exact source links, Search, Notes, Activity, deadlines, graph/relationships, signed URLs and direct IDs consistently.

## Questions for the later discussion

- Is access assigned directly to each Viewer, through groups, or both?
- What default applies to an existing Viewer when the feature is enabled?
- Can a Viewer discover inaccessible Matter names, counts, clients or invitation context?
- What happens to open tabs, signed URLs, saved links, notifications and exports when access is revoked?
- May an invited Viewer receive Matter access before accepting, and who can change it?
- Should a Viewer ever receive selected client-wide access, or only exact Matters?

Until this contract is implemented and accepted across every consumer, the current first-release model remains organisation-wide Viewer read access with a strict read-only role ceiling. Do not present a partial UI filter as a security boundary.

## Related plan

- [Organisation Administration](../plans/platform/2026-08-26-organisation-administration.md)
