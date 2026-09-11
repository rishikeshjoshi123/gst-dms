# Local acceptance

Install the pinned Chromium runtime once with `npx playwright install chromium`,
then run the complete disposable check with:

```sh
npm run acceptance:local
```

The command refuses non-loopback database, Storage, and captured-mail targets,
resolves the current project database container from its configured port, runs
`supabase db reset --local --no-seed`, executes the Team and upload SQL fixtures
with fail-fast rollback, seeds two synthetic tenants and role variants, uploads a
generated four-page PDF to local private Storage, and runs authenticated Chromium
checks for exact-page Workbench rendering, safe missing-source recovery, Matter
chronology history, Team directory privacy, real TUS completion, deterministic
in-flight cancellation and same-file reselection. A local service-role post-check
then verifies the upload sessions, Intake rows, reservations, receipts, asset
metadata, hashes, and private Storage object outcomes instead of trusting UI copy.
The browser matrix also covers representative 320px dark-mode, keyboard, target,
horizontal-overflow, stable-action, and scroll-owner assertions. The server process
uses a closed loopback Trigger endpoint, a non-routable Resend sentinel, and empty
Google/Vertex credentials. No worker or provider call is part of this check.

The seeded accounts are auto-confirmed feature fixtures. This command does not
claim that those fixtures verify email delivery. After the feature checks, the
runner starts a second disposable Supabase project on distinct loopback ports
with email confirmation required, captures two local-only verification mails,
follows their real links, and verifies both create and multi-invitation join
onboarding. The isolated confirmation project is stopped and removed after the
run, leaving the ordinary deterministic local profile unchanged.
