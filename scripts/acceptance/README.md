# Local acceptance

The mandatory first-release local integration rehearsal has one exclusively owned,
confirmation-required Supabase stack and one stateful production-webpack Chromium
journey:

```sh
/opt/homebrew/opt/node@24/bin/node scripts/acceptance/run-release-journey.mjs
```

It uses project `dms-release-journey-162` (API 56221, database 56222, shadow
56220, captured mail 56224, app 3113), replays current migrations, runs error-level
database lint, proves deterministic checked-in database types, and builds only in a
temporary application copy with the repository `node_modules` symlinked. The browser
creates a newly verified Owner, organisation, Client and two active Matters; performs
global and Matter-origin signed private-Storage uploads; follows the accepted no-call
terminal-processing manual recovery and typed ambiguous-placement branches; reopens
the exact version/page in Workbench and the Matter; then inspects chronology, the
truthful read-only graph and a manually verified deadline. A bounded 320px dark,
keyboard, touch-target and overflow segment and final cross-feature SQL assertions
cover tenant/role/source/version/assignment/decision/Activity identity and duplicate
side effects. The run does not call or evaluate an extraction provider, and therefore
makes no D12 provider/corpus-quality claim. It does not deploy or touch the ordinary
local `dms` stack or the repository `.next` directory. Its only seeded journey
preconditions are worker-owned validation/processing outcomes and proceeding-class
relationship endpoints that the first-release UI cannot author; the graph edge still
uses the canonical governed relationship command, and all other journey state is
created or decided through the product UI.

Timeline relationship authoring uses its own exclusively owned disposable project:

```sh
/opt/homebrew/opt/node@24/bin/node scripts/acceptance/run-relationship-authoring.mjs --types --browser
```

This replays migrations in `dms-relationship-authoring-155` (API 57321, database
57322, shadow 57320, app 3105), runs the effective-relationship core and authoring
SQL fixtures, checks generated-type parity, and builds a production webpack
snapshot for Chromium. It rejects an existing project with that name and removes
only the stack it created. It never resets or repairs the existing `dms` database.
The browser scenarios cover ordered chronology/desktop graph creation, exact
catalogue sentences, required archive reasons, stale-draft recovery, response-loss
replay, Owner/Associate authority, Viewer absence, retained history and Activity,
320/900px and true 200% zoom, long titles, dark/reduced motion, and keyboard focus.

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
chronology history, and the populated Matter graph backed by a governed effective
relationship. The graph checks cover Owner and Viewer access, fixed node geometry,
the accessible relationship-list alternative, keyboard inspector focus restoration,
filter and Back/Forward continuity, endpoint-filtered edges, pane scroll ownership,
light and dark themes, reduced motion, phone and tablet chronology fallback without
a graph server action, and Chromium 200% zoom reflow. They print bounded local graph
readiness and interaction observations; those numbers are smoke diagnostics, not
production latency or p95 claims. The suite also covers Team directory privacy, real
TUS completion, deterministic in-flight cancellation and same-file reselection. A
local service-role post-check
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
