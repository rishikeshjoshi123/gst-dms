# Associate working access and internal expenses

- **Decision / date:** `ORG-ASSOCIATE-ACCESS-CATALOGUE-2026-09-04` resolved on **2026-09-11** by the user after reviewing the proposed access cases.
- **Canonical plans:** [Organisation Administration](../plans/platform/2026-08-26-organisation-administration.md#roles-ownership-and-capabilities), [Document Hub](../plans/features/2026-08-25-document-hub-ingestion-and-workbench.md#shared-visibility-action-authority-and-concurrency), and [Deadlines and Financials](../plans/features/2026-08-26-deadlines-and-financials.md#internal-litigation-costs).
- **Affected outcomes:** D02/D15 role and lifecycle acceptance, D04/D06 shared-intake consumers, and the later internal-cost portion of D11/Financials. No application implementation or deployment is authorised by this record.

## Confirmed policy

- Owner/Admin and Associate have the same ordinary legal-work capabilities, subject to the owning feature's evidence, lifecycle and consequential-action safeguards. Owner/Admin adds application-level organisation management; it is not a separate class of lawyer for routine Matter work.
- Ordinary Associate work includes organisation-wide Matter/document access under the current first-release model, uploads, `All uploads`, standard shared-intake triage, Tasks, Notes/comments, Review, deadlines, and legal-financial work wherever the owning domain otherwise permits the action.
- Viewer remains read-only wherever access is otherwise permitted and does not receive unplaced-intake visibility merely from the Viewer role.
- There is no first-release general Associate feature-grant catalogue, `intake.manage_shared` grant, Organisation `Access` page, or arbitrary capability editor.
- Internal litigation expenses remain the sole optional working-access exception. Owner/Admin has inherent access and manages participants per Matter. An eligible Associate may receive `view` or `edit`; a Viewer may receive `view` only. This does not reveal other Matters or grant organisation administration, export, destructive authority, or unrelated Matter access.
- Confidential-Matter and ethical-wall restrictions are parked for possible future discussion after the user consults colleagues. They are not pilot or current production scope; Matter access remains organisation-wide unless a later approved plan changes it.

## Rationale and implementation impact

The organisation largely works together on the same legal matters. A broad configurable permission catalogue would add complexity without a demonstrated workflow, while internal expenses have a clear confidentiality need. Shared intake therefore becomes baseline Associate work instead of a separately granted responsibility.

Repository inspection on September 11 found no non-documentation `intake.manage_shared`, Organisation Access route, or internal-cost grant implementation to remove. The decision changes pending requirements and acceptance rather than invalidating a live feature. Future implementation must verify role parity for ordinary legal work and shared intake, keep administrative commands Owner/Admin-only, and independently enforce Matter-specific internal-cost visibility, mutation, audit, revocation, suspension/removal and role-downgrade behavior.

- **Resume owner:** next implementation coordinator when the relevant D02/D15, Document Hub or Financials tranche is authorised.
- **Implementation state / commit:** documentation decision recorded; application implementation not started by this discussion.
