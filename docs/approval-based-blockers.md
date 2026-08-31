# Approval-based blockers

This is the short, human-readable queue for decisions that need review before a
tranche can safely continue. It prevents one approval boundary from stopping
the rest of the approved portfolio.

## How it works

- Add an **Open** entry when a user decision, visual review, external authority,
  or material policy choice blocks a tranche.
- State the plan, the exact decision, why it cannot be safely inferred, the
  recommended option, and the safe next action after approval.
- Continue with the next independent canonical tranche. Do not treat this file
  as approval by itself.
- When the user resolves an entry, move it to **Resolved** with the recorded
  decision. Remove it after the dependent verified tranche is committed, unless
  its history is useful to the canonical plan.

## Open

### 2026-09-01 — Task and legacy note action-item compatibility

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **What is waiting:** choose how the existing note action-item controls behave
  while first-class Tasks are introduced.
- **Why:** today, the Matter Notes and Notes screens can mark a note action item
  resolved or change its assignment directly. The new Task is deliberately a
  separate record. Continuing to update both would create two competing sources
  of truth; leaving the old controls active would make the screen claim work is
  complete without changing the Task.
- **Recommended action:** approve **Task-only current state**. Keep a note as a
  historical record of what was created, but make Task the sole authority for
  completion, reopening, reassignment, and due-date changes. Remove the old
  note mutation controls and later show current Task state from the Task
  reader. Do not mirror Task changes back into the note.
- **Alternatives:** mirror every Task transition back to the note (more familiar
  short-term, but creates retry, race, reconciliation, and eventual-cleanup
  risk); or temporarily disable the controls without a Task reader (safe but
  leaves a dead-end workflow).
- **Then:** add the approved Task reader/transition command, organisational
  timezone semantics, typed Activity/outbox effects, and an additive one-to-one
  legacy backfill before claiming broader Task coverage.

### 2026-08-31 — Local browser sign-in for permanent-delete verification

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **What is waiting:** the final authenticated desktop/mobile/keyboard check of
  the new permanent-delete screen.
- **Why:** a generated Owner test account exists only in the disposable local
  database. Browser safety requires confirmation immediately before entering
  its generated password, even though it is not a real account and cannot
  affect production.
- **Recommended action:** enter the generated local test password at
  `http://localhost:3000/login` solely to verify the local Trash screens. It
  will not delete any records or call any production service.
- **Then:** finish the browser check and update the verified Trash checkpoint.

## Resolved

### 2026-08-31 — Trash permanent-delete concept

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** approve the compact root-operation permanent-delete review and
  typed-confirmation direction.
- **Why it needed review:** permanent deletion is irreversible and its impact,
  holds, and confirmation flow need human visual judgement.
- **Outcome:** user reviewed and revised the `/dev/trash-permanent-delete-concept`;
  the revised compact direction is approved for the production implementation
  tranche.
- **Next action:** implement and independently verify the governed permanent-delete
  authority and durable execution workflow.

### 2026-08-31 — Retention for historical soft-deleted records

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** no legacy compatibility migration is required before the first
  production deployment.
- **Why:** the local database contains test data only; no real client records
  exist that predate the automatic Trash policy. Production begins with the
  approved automatic retention policy, so it cannot contain pre-policy Trash
  entries.
- **Outcome:** do not invent or maintain a legacy exception for test data. If a
  future import introduces historical records, it must use its own approved
  import/retention contract.
