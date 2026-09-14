# Production environment and recovery options

Status: priority brainstorm requested on 2026-09-14; target the session for **October 1–2, 2026**. This note records options, not a hosting or remote-configuration decision.

## Problem

The October design-partner release needs a low-operations, low-cost environment that is lawful for the intended use and can recover both database state and private source PDFs. The current intent is Vercel, Supabase, Trigger.dev and Resend on free tiers with a second-account staging stack, but no confidential upload is approved until application hosting and independent recovery are settled and rehearsed.

The repository currently uses Next.js 16. AWS Amplify Hosting's published managed SSR support is for Next.js 12 through 15, so Amplify is not presently a drop-in option. Raw EC2, ECS or Kubernetes would create an avoidable operations and security burden for the first design partner. Cloudflare documents a Next.js 16 path through `vinext`, but calls `vinext` beta and requires a compatibility check; it is an evaluation candidate, not an assumed safe migration.

## Hosting options to compare

- **Vercel with written eligibility confirmation or a paid plan** — least migration risk; first ask Vercel Support whether this unpaid, closed design-partner validation qualifies for Hobby. Absence of revenue alone does not settle Vercel's published commercial-use definition.
- **Cloudflare Workers after a compatibility spike** — potentially low cost and compatible with a Next.js 16 codebase through `vinext`, but the adapter is beta and must pass CaseChain's routes, proxy/middleware, Server Actions, uploads, environment, build and rollback checks.
- **AWS managed hosting after support changes** — reconsider Amplify only when it documents support for the repository's Next.js version and features. Do not choose raw AWS compute merely to avoid a hosting subscription.

The session should compare compliance, migration work, framework compatibility, preview/staging isolation, logs, rollback, secrets, region/data path, spend limits and operator learning burden. Zero advertised price is not enough.

## Independent recovery option to design

Application hosting and backups need not use the same provider. A practical Supabase Free proposal is:

1. Run a scheduled, least-privilege logical database export and independently copy every private Storage object plus a manifest containing object identity, version/checksum and export revision.
2. Encrypt the artifacts before or at the destination and store them in a private, access-blocked bucket outside the live Supabase project. Amazon S3 in an approved region is one candidate; it does not require hosting the Next.js app on AWS.
3. Enable versioning, narrowly scoped IAM, MFA-protected owner recovery, access logging/alerts, a documented retention/lifecycle policy and cost alarms. Never put client filenames, Matter names or extracted text in job logs.
4. Alert on missed/partial backups and retain enough known-good generations to recover from delayed corruption or deletion.
5. Restore into an isolated non-production project, verify database-to-object referential integrity and open sampled PDFs through the application. A backup is not accepted until that restore drill succeeds and its recovery time/data-loss window are recorded.

The brainstorm must decide scheduler ownership, destination/region, encryption and key recovery, cadence, retention, deletion propagation, monitoring, restore responsibility and acceptable recovery objectives. If this cannot be made dependable before onboarding, move to a tier/provider with suitable managed recovery instead of treating an untested script as a backup.

## Client-data boundary to settle alongside it

Record which Matters and PDFs the design partner authorises; the permitted purposes (document management, OCR, metadata extraction and any enabled retrieval); allowed client users; external processors and regions; Trash/permanent-deletion and temporary-backup retention; the client's responsibility to keep recoverable originals; CaseChain's restore limits; and the support/incident contact.

## Discussion outcome

Produce one decision-complete environment diagram and runbook: production/staging account ownership, host, branches, domains, secrets, provider regions, backup flow, retention, monitoring, restore drill, rollback and named operators. Remote account creation, migration or deployment requires separate authority after the decision.

## Related material

- [First production release scope](../decision-history/2026-09-14-first-production-release-scope.md)
- [Production go-live ownership and incident response](production-go-live-ownership-and-incident-response.md)
- [Platform Operations](../plans/platform/2026-08-27-platform-operations.md)
