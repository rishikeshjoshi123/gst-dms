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

### 2026-08-31 — Retention for historical soft-deleted records

- **Plan:** Hierarchical Resource Trash, Retention, and Purge — legacy
  `deleted_at` compatibility migration.
- **What is waiting:** the retention rule for records that were already
  soft-deleted before the new Trash policy existed.
- **Why:** the system knows their old deletion timestamp but not whether their
  organisation ever agreed to automatic deletion. Starting a 30/60/90-day
  schedule retroactively could permanently delete legal records using invented
  history; leaving them unscheduled creates a narrow legacy exception.
- **Recommended action:** create each recoverable old record as a clearly
  labelled historical Trash entry with no automatic deletion date. A future
  authorised Owner/Admin action can choose a policy explicitly. This never
  changes a live/new Trash operation.
- **Alternative:** apply the current 30/60/90-day policy from the migration
  date. This is simpler but may delete old legal records sooner than the
  organisation expects.
- **Then:** implement and verify the legacy migration using the chosen rule.

### 2026-08-31 — Local browser sign-in for permanent-delete verification

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **What is waiting:** the final authenticated desktop/mobile/keyboard check of
  the new permanent-delete screen.
- **Why:** a generated Owner test account exists only in the disposable local
  database. Browser safety requires confirmation immediately before entering
  its generated password, even though it is not a real account and cannot
  affect production.
- **Recommended action:** approve entering the generated local test password at
  `http://localhost:3000/login` solely to verify the local Trash screens. It
  will not delete any records or call any production service.
- **Then:** finish the browser check, move this entry to Resolved, and update
  the verified Trash checkpoint.

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
