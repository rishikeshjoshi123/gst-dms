# Organisation Team and departure concept approval

- **Decision / date:** `ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01` resolved on **2026-09-08** by the user: “i have approved its current shape”.
- **Canonical plan:** [Organisation Administration](../plans/platform/2026-08-26-organisation-administration.md#ui-layout-and-state-contract).
- **Approved reference:** `/dev/organisation-departure-team-concept`, including the current Team/member inspector, departure queue, administrative-removal impact workspace, `Before leaving`, and `My departure` surfaces. This approves the current revised fixture as the implementation direction; it does not establish live behavior.
- **Source observed when recording approval:** branch `dev`, HEAD `0ae1bb6`, with uncommitted concept and shared design-system changes. The concept source is [OrganisationDepartureTeamConcept.tsx](../../src/app/dev/organisation-departure-team-concept/OrganisationDepartureTeamConcept.tsx); its SHA-256 is `3390dd7601e088fd96cffb182b243f1a74fe9da6e502a0989e338cbe82cd40b8`. This identifies the concept file, not a committed snapshot of every visual dependency.

## Approved shape

- Team uses compact operational tables, 48px desktop rows for Members and Departure queue, stable columns, keyboard/pointer row selection, and an approximately 60/40 table/inspector split. Person is a short name index; repeated fields move into the inspector. The small left collection gutter remains stable when selection opens, and Invite member anchors the full-table toolbar's right edge.
- The inspector keeps one width, fixed identity/actions and an independently scrolling body. Member details, real work to hand over, teammate context and access information use a compact hierarchy. Mobile uses list-to-detail navigation and larger touch targets.
- Planned departure and immediate administrative removal remain separate. Removal uses a dedicated impact/disposition workspace. `Before leaving` and `My departure` share a 3:2 desktop grid and one-column mobile order; request/withdraw actions sit in the desktop summary and mobile bottom bar.
- Ordinary Team members continue to see a scheduled departing member as Active; private departure information stays self/Owner/Admin scoped. Impact includes the member's open Tasks and accountable important dates. Shared Review items stay in Review and only their temporary claim is released. A teammate note supplies context, not automatic reassignment; no invented Matter-owner responsibility is implied.

## Release and resume

The visual approval gate is released. The next implementation coordinator may claim **D15** in [the ledger](../delivery-ledger.md), reconcile current code and prerequisites, and implement the smallest secure live Team/departure or administrative-removal closure. Do not ask for this same visual approval again. Replace the legacy removal caller through the approved impact/disposition flow; do not attach typed destructive commands directly to the old control.

The canonical authority matrix, privacy/RLS boundaries, membership snapshots, transactional reassignment, stale/concurrent command protection, lifecycle effects, and required database/browser acceptance still apply. Retention activation, the Associate grant catalogue and the separate Review workspace retain their own decisions.

- **Resume owner:** next implementation coordinator; task identity `unassigned`.
- **Implementation state / commit:** `planned` / `not implemented` for the live consumer covered by this approval. Existing foundations retain their separately recorded evidence. Add the actual implementation receipt/commit through D15 when verified; visual approval alone cannot complete that outcome.

## Prior concept verification

The preceding handoff reported scoped ESLint, whitespace and browser-console checks passing against `a762850` plus then-uncommitted concept edits. Team list/detail and departure surfaces were exercised at desktop and a true 320px viewport without horizontal overflow. This is historical fixture evidence, not a live reader/mutation acceptance result, and was not rerun to record the user's decision. The handoff retains unresolved broader type/build/database checks for reconciliation before implementation.
