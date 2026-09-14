# Last member leaving and an empty organisation

Status: deferred product discussion. Raised on September 10 and expanded on September 14; excluded from the October implementation objective. Owner: [Organisation plan](../plans/platform/2026-08-26-organisation-administration.md#last-member-and-empty-organisation-follow-up).

The user wants to explore allowing the sole member to leave rather than trapping them in an organisation. The departure, organisation state, data lifetime and possible return must be decided together. This is an intended later discussion, not approval of ownerless access, automatic deletion or a completed lifecycle contract.

The September 14 proposal is: the final Owner may leave; the organisation becomes archived; organisation jobs and processing stop; and the former Owner may later request recovery from CaseChain. Recovery might use a future governed Platform Administration surface or, temporarily, an internal operation. This is a proposal, not an approved command or permission to edit production tables manually. A normal recovery path should be authenticated, reasoned, auditable, collision-safe under the one-organisation rule and preferable to ad hoc database editing.

Questions for that session:

- Does explicit last-member departure suspend/close the organisation, and how is that different from temporarily pausing work?
- How long do its documents and history remain, who can authorise deletion, and what notice/recovery period applies?
- Can the former member return, what proves their right, and how is that reconciled with the confirmed one-organisation rule if they joined elsewhere?
- Does recovery reactivate the old membership/organisation generation or create a new one, and which actor may approve it through Platform Administration?
- How are pending invitations, background processing, storage charges, open work and any existing holds handled?
- Which jobs stop immediately on archive, which cleanup/retention jobs must continue, and how are delayed events fenced from resuming work accidentally?
- Could retaining a paused membership meet the user's goal, or would it improperly prevent joining another organisation?

No choice is settled. Keep existing last-Owner/Admin safeguards for ordinary access changes until a deliberate last-member departure/recovery contract replaces the relevant boundary. Do not turn this deferred topic into a blocker for signup, invitation display, normal creation or current acceptance work. Save the eventual decision in the canonical plan and reopen affected implementation evidence.
