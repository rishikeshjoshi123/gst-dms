# Production go-live ownership and incident response

Status: priority release discussion requested on 2026-09-14. Target the production-environment/recovery portion for **October 1–2, 2026**. This is the remaining human decision gate for the first confidential-data production release.

## Problem

CaseChain needs named authority and a practicable response path before one design partner uploads confidential PDFs. Passing automated checks is necessary but does not identify who may promote a release, who controls production accounts, who communicates with the client, or what happens when an upload, provider, access-control or recovery incident occurs.

The proposed zero-cost stack also conflicts with current assumptions. [Supabase Free has no automatic backups](https://supabase.com/docs/guides/platform/backups), and the proposed [Vercel Hobby deployment](https://vercel.com/docs/plans/hobby) must be checked against its non-commercial-use restriction. Separate second-account staging can provide useful isolation, but it also creates account-recovery, ownership and secret-separation obligations.

Application hosting and independent recovery are related but separate choices. CaseChain does not need to move its application compute to AWS merely to keep encrypted backup copies in Amazon S3. The dedicated [production environment and recovery options](production-environment-and-recovery-options.md) note preserves that brainstorm without prematurely selecting a provider.

## Questions for the session

- Who owns the production Vercel/alternative host, Supabase, Trigger, Resend, DNS and Google Cloud accounts, and who is the backup operator?
- Who may approve a release candidate, database migration, worker promotion, rollback, temporary feature disablement and permanent recovery action?
- What exact confidential-data checklist must pass against the deployed revision and configuration, and who records the sign-off?
- What is the support channel and expected initial response for access denial, unavailable source, stuck processing, incorrect AI metadata, missed reminder, data exposure or provider outage?
- What is the compliant hosting choice if Vercel Hobby is unavailable for this use?
- If Supabase remains Free, where do scheduled database dumps and private Storage copies go, how are they encrypted, how often are they made, and what restore drill proves them? If that cannot be achieved safely, is Supabase Pro required before upload?
- What is the rollback order for application, migrations, workers and feature flags, and when does the system stop accepting new uploads?
- Who informs the design partner, preserves evidence, rotates credentials and decides when service may resume after an incident?
- What short client-data agreement/checklist records authorised Matters/PDFs, the permitted processing purpose, allowed users, provider/region disclosures, retention/deletion/backup behavior, client-retained originals, recovery limits and the incident contact?

## Recommended direction

Use one written release sign-off with a named product owner and technical operator; one sealed account inventory with MFA/recovery access; a tested staging-to-production promotion; content-safe monitoring; a short client support channel; and a severity-based stop/rollback/communication playbook. Prefer ordinary governed commands and audited operator actions over ad hoc database edits.

End the discussion with a decision-complete runbook owner matrix, hosting/backup choice, confidential-data checklist, incident severity table and exact go/no-go authority. No external account or deployment action is authorised by this note.

## Related material

- [First production release scope](../decision-history/2026-09-14-first-production-release-scope.md)
- [Design Partner Pilot Execution Sequence](../plans/operations/2026-08-29-design-partner-pilot-execution-sequence.md)
- [Platform Operations](../plans/platform/2026-08-27-platform-operations.md)
- [Production environment and recovery options](production-environment-and-recovery-options.md)
