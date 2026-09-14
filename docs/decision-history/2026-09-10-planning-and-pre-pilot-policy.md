# September 10 — Pre-pilot data, normal onboarding and product discussions

## Confirmed user decisions

- **Current phase:** before real-client onboarding, existing application data and legacy tables/code are disposable, including current tester-only production data. The user will identify when real users are onboarded. Do not preserve obsolete test data or maintain compatibility solely for it. Choose a clean rebuild/replacement when it is the better bounded implementation; do not discard useful work merely because replacement is permitted.
- **Execution scope:** this removes legacy-data preservation as a product requirement in the current phase. It does not request a reset in this documentation task or identify a remote project to operate on. Verify the target and affected callers/jobs before an authorised overhaul; preserve unrelated working-tree edits. Re-baselining is permitted in principle, with coherent application, schema, generated types, fixtures and workers. Do not falsify remote migration history or weaken tenant/evidence authority.
- **Real-client transition:** record the user-declared cutover/environment before first real-client release. Then preserve accounts, organisations, stable resource/source IDs and human corrections through safe migrations/rollouts. The phase follows real-client use, not a deployment's `production` label. Resolve unclear or contradictory data-phase evidence before destructive work.
- **Normal onboarding:** email signup → verification → onboarding showing `Create organisation` and the user's pending invitations. Creation establishes the first Owner/Admin through the normal application command; invitation acceptance joins an existing organisation. Manual first-owner provisioning and invite-only signup are not required. Existing one-active-or-suspended-organisation and invitation/authentication rules remain unless separately changed.
- **Discussion:** support agent-proposed topics and user ideas, overlap checks, candid critique, alternatives and saved decisions with implementation impact. Keep maintenance/reading economical. Application implementation remains paused.

## Environment observation

September 10 read-only inspection found no root `.env`; `.env.local` contains a loopback Supabase URL, local-issuer anon/service-role JWTs and an empty `SUPABASE_PROJECT_REF`. `.env.example` is a template. No cloud Supabase credentials were identified in these files; no values are recorded here. No inherited Supabase/DB variables or nonempty local Supabase link file were observed. Running-process overrides, hosting configuration and GitHub Actions secrets were not inspected. Other providers are not classified by this Supabase-only check.

## Impact and unresolved choices

### Subsequent clarifications

- On September 11, the user resolved real-client Trash activation in favour of automatic 30/60/90-day retention, exact logical expiry, one daily midnight-IST physical-purge sweep and asynchronous cleanup. The pilot does not surface the 24-hour Team-attention item; its UI is parked with future Today/Dashboard work. Wider background-job optimisation is parked for a separate brainstorming session. [Recorded decision](./2026-09-11-trash-retention-activation.md).
- On every login without an active/suspended organisation membership, show the account's pending invitations and a distinct create-organisation view/action. Multiple inviting organisations do not change the user-confirmed one-organisation membership rule.
- Last-member departure, empty-organisation retention/deletion and returning to that organisation are explicitly deferred for a later brainstorming session. [Topic note](../discovery/last-member-and-empty-organisation.md). No automatic deletion/recovery or last-admin exception is approved.
- The user reports purchasing `case-chain.com` and proposes using Resend for Supabase Auth. Domain DNS/Resend verification and remote SMTP configuration remain unverified. Production setup is separate from local captured-mail testing; no DNS, SMTP or email-send operation is authorised by this record alone.

### Non-critical October recommendations accepted

The user explicitly authorised accepting recommendations from the October assessment that do not need their immediate review. Under that delegation, accept the focused release sequencing; repeatable headless/local/CI acceptance; one writer with scoped helpers and independent consequential QA; bounded repairs and selective document reads; capability/evidence tracking and documentation maintenance; the daily short decision packet; early staging preparation and an October 4 feature-freeze target with a final stabilisation period. These dates are planning targets, not guarantees or deployment authority. The product-discussion workflow is accepted as an operating procedure, not approval of the product ideas it may generate.

The graph remains the priority already expressed by the user. Human-confirmed relationship authority can lead implementation; this does not settle final AI/retrieval inclusion or waive its evidence gates. Existing approved visual contracts remain governing. The current local acceptance/repair run is executable without reading or approving the entire assessment.

Keep critical decisions pending: real-client retention/purge activation; access/removal/last-member lifecycle and minimum release administration; Matter identity/collision policy; Review concept approval; AI thresholds/consequential authority and final enabled scope; remote configuration/deployment/paid-service actions. Subscription willingness is not purchase approval. Pre-pilot disposability and normal onboarding are already explicitly decided, not newly inferred here.

- **D03/D13:** old invite-only signup and disabled-creation receipts no longer satisfy intended onboarding. Normal create-or-join entry needs code and acceptance. See [Organisation onboarding](../plans/platform/2026-08-26-organisation-administration.md#normal-signup-and-create-or-join-onboarding).
- **Lifecycle/D09:** compatibility/backfill solely for disposable legacy test records is superseded in this phase; resulting application identity/integrity remains required.
- **Still undecided:** retention activation for real-client use, minimum October member administration, Matter identifier policy, Review visual approval and enabled AI scope/thresholds. Asking about these is not approval.
- The October 12–15 target and 1–3 daily hours remain as recorded in the [October assessment](../reviews/2026-09-10-october-release-reassessment.md). This decision supersedes its immediate preservation/manual-bootstrap assumptions, not its historical observations.
