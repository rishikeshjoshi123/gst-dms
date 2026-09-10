# Local acceptance

Install the pinned Chromium runtime once with `npx playwright install chromium`,
then run the complete disposable check with:

```sh
npm run acceptance:local
```

The command refuses non-loopback database, Storage, and captured-mail targets,
resolves the current project database container from its configured port, runs
`supabase db reset --local --no-seed`, executes the Team and upload SQL fixtures
with fail-fast rollback, seeds two synthetic tenants and role variants, and runs
the authenticated Matter-to-Workbench Chromium smoke. The server process uses a
closed loopback Trigger endpoint, a non-routable Resend sentinel, and empty
Google/Vertex credentials. No worker or provider call is part of this check.

The seeded accounts are auto-confirmed feature fixtures. This command does not
verify confirmation-required signup or email delivery acceptance.
