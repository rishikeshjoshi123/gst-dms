# Delivery strategy and phased production pilot review

Assessment date: 8 September 2026. Code baseline: `cef0fde33e127df683593d7e2d756614468f4ae9`. This is an assessment and recommendation, not an approved replacement rollout plan or an instruction to start implementation. Existing plans, the active implementation task and unrelated working-tree changes were preserved.

## Conclusion

The previous work created substantial reusable foundations. Its dominant order was dependency-led architecture implementation, followed by individual consumer migrations and, recently, repairs to the actual application. That order was defensible early on, but it has not consistently optimised the time until the design partner can complete a useful workflow.

A small production release is appropriate. It should use the permanent identity, tenancy, document and evidence contracts, while exposing a narrow product. The user's new priority is a useful matter graph and next actions. The existing proposed pilot instead defers the full graph and includes OCR/cited-retrieval gates. Those priorities must be reconciled explicitly; simply resuming the broad portfolio prompt will not reliably deliver the new pilot.

This weekend, 12–13 September, is a stretch for confidential-data production access and is not a responsible unconditional promise from this evidence. A narrow release with human-confirmed chronology/relationships is plausible sooner than the full approved graph, Review, deadline and search experience. Keep release gates fixed and reduce enabled breadth when time is short.

## Evidence and limits

Reviewed the 19-plan index, delivery workflow and ledger, the September 7 audit, relevant delivery receipts, current application/database/worker paths, and retrieved records from:

- Implementation 28 Aug Thread
- Implementation 29 Aug Thread
- Implementation 01 Sep Thread
- Implementation 03 Sep Thread
- Impl 05 Sep Thread
- Impl 08 Sep Thread
- Imp 08 Sep Thread 2
- Estimate canonical plan completion
- Assess app completion timeline
- Workflow strag. and prompt prepare

This was targeted retrieval of task instructions, substantive turns, completion claims and repair examples, combined with repository evidence. It was not an exhaustive reread of every message or a remote production/security audit. The implementation task was active in the same checkout; check results therefore use an isolated committed snapshot, while current dirty documents provide decision context.

Git history from August 24 through the baseline contains **204 commits**: 58 touch only documentation/portal/root instructions; 146 touch other files, and 135 of the total touch `src/` or `supabase/`. September 8 alone accounts for 79 commits, including 38 documentation/portal-only commits. These categories measure history composition, not wasted work, productive time, or feature completion. The checkout contains 138 migration files, 120 SQL test files, 76 tests under `src`, and 40 delivery receipts. File counts do not prove those tests currently pass.

Fresh checks on the isolated snapshot, using Node 24.8.0 and the installed dependency tree:

- TypeScript without incremental caching: passed.
- Focused upload/recovery, invitation, matter authority/navigation/pagination and release-policy tests: 44 passed. This selection contains both executable behavior tests and source-shape assertions; it does not establish live database or browser acceptance.
- Migration inventory: 138 unique versions passed. This checks numbering, not SQL execution.
- Generated-type refiner tests: 4 passed. Fresh database generation/parity was not rerun.
- Webpack production build: public font fetching initially failed in the network-restricted environment. With network access, compilation and the build's TypeScript phase passed; page-data collection then failed because the deliberately credential-free snapshot has no Resend API key. A complete configured production build was not established by this audit.

The snapshot reused installed dependencies rather than doing a fresh `npm ci`. No existing database was reset; no authenticated browser journey, real email, Storage transfer, provider evaluation or deployment was exercised. Historical receipts report additional passing checks, but their unrun release gates remain open. Temporary audit outputs are under `/private/tmp/casechain-strategy-audit-20260908` and `/private/tmp/casechain-audit-*.log`.

## What the delivery strategy actually did

| Period | Dominant delivered work | Interpretation |
| --- | --- | --- |
| Aug 27–28 | Membership/invitations; immutable assets/versions; upload and placement commands; durable outbox; global/matter upload callers | Necessary foundations with real consumers |
| Aug 29 | Staged-source migration/retirement, recovery, provenance, effective metadata, search indexing | Strong data work; much less directly visible partner value |
| Aug 30–Sep 1 | Inspector consumers, Trash/restore/purge; Tasks; platform pricing/usage/alerts; search and acquisition foundations | Broad portfolio progress while key UI approvals remained open |
| Sep 2–3 | Source anchors, acquisition evaluation/benchmark harness | Useful quality work, but blocked by real corpus/threshold/provider inputs |
| Sep 5 | Canonical Document Hub, reader, Workbench access and source locators; membership history | More direct user workflow progress |
| Sep 8 | Build/type/auth repairs; direct upload; PDF viewer; quotations; Matter shell/Files; upload race hardening | Corrective integration and visible progress, with several acceptance gates still open |

The older implementation instructions explicitly used sequential implementation → coordinator inspection → independent QA → consolidated repair → recheck → documentation/commit. They generally used Terra for implementation, Luna for QA and separate concept work. This was a multi-agent quality process, not simultaneous delivery of several independent complete features. Newer workflow instructions route consequential QA to Sol and encourage direct handling of trivial work.

The process has demonstrable benefits. [D04-T02](../delivery-evidence/D04-T02.md) records cancellation, late-token and cleanup-accounting defects found and repaired by independent QA. [D11-T02](../delivery-evidence/D11-T02.md) records seven first-pass shell defects plus a transitive over-fetch found on recheck. [D06-T11](../delivery-evidence/D06-T11.md) records expired-URL renewal and permanent-versus-temporary source failures. These affect actual reliability and justify independent review.

However, substantial quality problems survived earlier tranche acceptance: the September 7 audit found broken build/worker boundaries, live permission gaps and incompatible legacy consumers. Some newer tests establish that expected strings exist in source, not that real role/session/database behavior works. Several newer receipts explicitly lack independent QA or authenticated browser acceptance. Thus “lots of QA” is not equivalent to an integrated, verified release.

There is no credible measured speedup percentage for the old model routing: no controlled comparison or complete time accounting was available. Commit intervals include checks, waiting, user pauses and context transitions. Older estimates moved from approximately 8–12 days for all plans to weeks, and from mid-September to late-September/early-October pilot targets. They should not be carried forward as commitments.

## Why delivery has felt slow

1. **The objective remained the entire approved portfolio.** The [implementation prompt](../implementation-prompt.md) tells the owner to keep finding other approved work when blocked. The [workflow](../plans/operations/2026-09-08-agent-delivery-workflow.md) expressly says a pilot exclusion alone is not an implementation deferral. That can rationally select pricing, retention or unrelated readers while a pilot-critical decision waits.
2. **The proposed pilot pivot was never a complete governing scope change.** It remains `proposed`, and it prioritises a different first-release value proposition from the user's graph-first request.
3. **Too many independently accepted fragments.** Tables, RPCs, readers and compatibility repairs can be correct while the full workflow still fails. The first configured deployment should have been rehearsed earlier to expose environment assumptions.
4. **Real defects cause real repair time.** Removing QA would hide that cost until the client experiences it. Better initial briefs and earlier high-risk review can prevent repeat cycles.
5. **Operational friction.** Long histories, repeated discovery, preserved dirty documentation hunks and unavailable browser control slow verification. Retrieved tasks also contain repeated unchanged “Paused”/“Active” turns, which are continuation overhead rather than feature work.
6. **Completion has multiple meanings.** A schema, live caller, passing local check and accepted deployment are different milestones. The ledger is more honest now, but many outcomes remain in review.

## Current readiness of the requested journey

| Capability | Evidence now | Release work remaining |
| --- | --- | --- |
| Accounts and organisation | Canonical membership/invitation foundations and invite-bound signup | Bootstrap/provision first owner/org; configured auth email/redirects; session/revocation journey |
| Organisation creation | Public action deliberately disabled in [org.ts](../../src/lib/actions/org.ts) | Provision one canonical org under a controlled operation, or implement a separate approved public creation flow |
| Clients and matters | Governed mutation repairs and live pages | Replace the still-present client/year uniqueness assumption; verify multiple real matters and Restore |
| Upload/assignment/PDF access | Direct private resumable transport, immutable versions, Intake/placement, source renewal | Real SQL/TUS/token/retry/size-boundary and deployed acceptance; honest exception/manual path |
| Matter shell/Files | URL-driven sections, lazy readers, bounded Files, source reopening | Authenticated browser acceptance, broader projections and complete chronology |
| Graph | Existing React Flow/Dagre implementation | Canonical relationship model/commands, chronology, authoritative metadata summaries, stable horizontal UI, accessibility and meaningful action context |
| Deadlines/next actions | Tasks and legacy dates; overdue reader repair | Verified legal dates, accountable owners, lifecycle/source context and Matter projection; reminders remain separate |
| Review and other modules | Foundations or legacy routes | Typed Review resolver and production consumer; full Activity, Notes/Brief, financials, search and realtime remain substantial work |
| Release operations | Migration and portal workflows; descriptive release manifest | Coordinated app/database/worker promotion, feature enforcement, real environment identity, backups/recovery boundary and exact deployed journey |

The graph gap is source-confirmed: [workspace-read.ts](../../src/lib/matters/workspace-read.ts) reads `document_links`; [TimelineGraph.tsx](../../src/components/matters/TimelineGraph.tsx) uses `TB`, 148×100 nodes, enum-derived labels and pending edges. The approved [Matter plan](../plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md) instead specifies effective `document_relationships`, left-to-right progression, catalogue phrases and separately reviewed suggestions. The planned effective relationship tables are not yet present as that canonical model. The legacy inference helper still defaults unknown type pairs to `responds_to`; that is unsuitable as the authority for a trusted procedural graph.

[MatterActiveSection.tsx](../../src/components/matters/MatterActiveSection.tsx) already presents unavailable Deadlines, Financials and Activity sections. “Coming soon” is therefore compatible with the application structure, but it cannot stand in for required backend guards. The release manifest's route/worker/limit inventory is mostly descriptive; only specific decisions are wired through its current policy functions. It is not yet a universal release enforcement mechanism.

## Recommended first-release product

Provision one permanent organisation and owner, then let that owner invite the approved 10–15 members. Land users in Matters or Clients. Expose matter creation, document upload into a chosen matter, assignment where needed, exact PDF reopening, essential notes, a readable chronology and a restrained graph over explicitly verified relationships. Use the existing canonical schemas and IDs throughout.

Prioritise the graph's meaning before animation or automation. A user should understand the known progression, see why two documents are connected, open the evidence, and see the responsible person's next recorded action. Keep disconnected documents visible; preserve unknown dates; distinguish provisional information. Never imply that the few uploaded files constitute the full matter history.

Reuse Tasks for internal actions. Add the smallest canonical human-verified deadline slice for legal dates if those dates are displayed as authoritative. A task date is not a legal limitation calculation. “Next action” must have an explicit owner, state and basis; it cannot be guessed from the latest document or a terminal graph node. Several concurrent open actions may be valid.

For initial setup, human-confirmed dates, document types and relationships are acceptable and likely faster. Extraction may assist, but if its benchmark/Review path is unfinished it must remain disabled or explicitly provisional, and basic filing must work when the provider is unavailable. That fallback requires implementation and acceptance; disabling a worker alone is not evidence that the DMS still functions.

Hide Dashboard/Today, full financials, advanced search, Brief generation, bulk imports, advanced organisation grants, automated legal-date calculation and unready destructive automation. Use placeholders inside necessary workspace sections sparingly; hide whole unused destinations when clearer. Do not leave enabled actions that reach legacy mutation paths. Retention activation needs an explicit scope decision because the current plans conflict.

The new manual-first scope changes the existing pilot proposal. It would defer OCR/cited-retrieval release gates only if the corresponding behavior is actually excluded and server/worker boundaries enforce that exclusion. It does not waive the quality gate while continuing to ship the gated AI capability.

## Data preservation across future releases

Schema changes do not inherently delete user data. Preserve durable user, organisation, membership, client, matter, document, version and asset identities; add new capabilities around them. Never make graph layout or AI output the only copy of a human decision. The [portfolio migration policy](../plans/platform/2026-08-24-product-architecture-portfolio.md#migration-policy) already calls for additive changes and stable IDs.

Use an expand → backfill → verify → switch → later retire sequence. For example, add canonical relationship tables beside legacy links, retain a legacy-ID mapping, import every link with an explicit disposition, validate counts and evidence, switch the reader, then retire the old writer in a later release. Invalid historical semantics must be reported rather than silently promoted. The same approach applies to deadline ownership, Notes and future organisation features.

Before client entry, make permanent-data rules operational: separate development/staging/production; append new migrations rather than editing already-deployed history; test both a blank installation and an upgrade containing representative existing data; preserve foreign keys and source hashes; check old sessions and in-flight workers against the expanded schema; and stage app/worker/database changes as one release. An app rollback does not reverse a destructive database migration. Restoring an older backup may discard later client writes and is an emergency recovery measure, not a routine deployment rollback.

The current [migration workflow](../../.github/workflows/supabase-migrations.yml) can push migrations on `main`, uses `--include-all`, and regenerates/types checks again after the push. No protected production environment or coordinated app/worker release is defined in that file. Remote GitHub protections/configuration were not inspected. Before live data, require a rehearsed ordered migration set and checks before any production push.

Supabase documents separate staging/production projects and migration deployment in [Managing Environments](https://supabase.com/docs/guides/deployment/managing-environments). Its [backup documentation](https://supabase.com/docs/guides/platform/backups) explicitly excludes Storage object bytes from database backups. Preserve original PDFs independently or retain the already-agreed one-client boundary of verified managed database backups plus client-retained recoverable originals, with honest missing-object handling. Do not describe that boundary as full object restore. A tested independent object backup would strengthen it and should be preferred if readily achievable; it is a recommendation, not a newly invented approval gate.

Supabase's [SMTP documentation](https://supabase.com/docs/guides/auth/auth-smtp) also confirms that its default email service is unsuitable for production and restricts recipients. The app's invitation provider and Supabase Auth's verification/reset email configuration must both be checked. A working invitation template is not sufficient onboarding evidence.

## Faster delivery without reducing acceptance

Retarget the existing owner to a fixed pilot outcome and a short ordered queue. Use the existing ledger, with each next item explaining what becomes usable and what release dependency it closes. Do not launch another portfolio, tracker or orchestrator. Keep one writer. Use independent read-only QA for security, migrations, async behavior and material workflows; run truly independent preparation in parallel only when it does not race the writer or shared database.

Batch cohesive behavior rather than isolated helpers, but do not create multi-day unreviewable diffs. Give helpers exact contracts, callers and acceptance cases. Consolidate defects, reuse the implementer for repair, and escalate persistent conceptual failures early. Measure accepted workflow increments, time to first usable integration, repair cycles and open acceptance age; do not optimise commit count.

Run targeted tests during implementation, a joined workflow check at each milestone, and the broad suite at release. Maintain a repeatable browser fixture that does not depend on an unlocked desktop, plus disposable database fixtures with separate identities. Avoid repeated broad scans and unchanged-baseline runs. The September 8 workflow already incorporates much of this; enforce it consistently and narrow its release objective rather than rewriting it again.

Production-quality testing is substantially within an agent's implementation domain: agents can write and run database, permissions, migration, browser, accessibility, failure and load checks, and implement deployment/recovery tooling with authorised access. Humans still own product/legal correctness, representative fixture adjudication, account authority, release acceptance and operational responsibility. Broad analytics and scale exercises can wait; access denial, evidence retention, upload failure recovery and basic operational visibility cannot.

## Estimate and weekend decision

These are judgement ranges, not measured statistical confidence intervals. Hours mean effective project engineering time including implementation, integration and repair—not the sum of overlapping agents and not laptop uptime. Calendar ranges assume roughly 8–12 effective hours on active delivery days, prompt decisions and working access to providers/test environments; weekly limits or unavailable people extend them. No account-quota conversion was attempted.

| Outcome from this baseline | Effective project hours | Planning range |
| --- | ---: | --- |
| Narrow production DMS with invite-bound organisation, upload/assignment/reopen, human-confirmed chronology/basic graph and recorded next actions | 60–110 | About 1–2 weeks; roughly Sep 15–22 as a working target |
| Strong flagship graph plus dependable relationship decisions, verified deadline responsibility and integrated core Matter workflow | 100–180 total | About 2–4 weeks |
| Broad currently documented product, excluding advanced analytics and extensive production scale/certification work but retaining normal correctness/security/integration tests | 300–500 total | About 6–10 productive weeks at roughly 50 hours/week; 10–14 calendar weeks is a reasonable downside |

The broad estimate includes the substantial remaining Review/Activity/notification, Notes/Brief, deadlines/financials, retrieval, organisation, realtime, platform and UI integration work. It is conditional on settling proposed/deferred scope, including the demo; unplanned spreadsheet/GST imports and future legal rule catalogues cannot have a reliable completion date before their inputs and scope exist. These rows overlap and must not be added together.

Indicative narrow-pilot breakdown: 10–18 hours for identity/entry/matter identity, 12–22 for the complete document/manual-exception journey, 22–40 for canonical manual relationships/chronology/basic graph/action context, and 12–22 for configured release/migration/browser/recovery acceptance. Their 56–102-hour sum is rounded to 60–110 for modest integration uncertainty. Automatic relationship quality, full Review breadth and exceptional graph refinement push toward the next row.

For Sep 12–13, aim to have a configured release candidate and one observed end-to-end demonstration. Confidential client access is conditional on the actual release passing. By Friday Sep 11, require a clean-session invite journey, two distinct same-client/year matters, upload/reopen, a truthful graph/action view, role/tenant denial and upgrade preservation in the deployed rehearsal environment. Missing those by Friday means no weekend commitment to confidential uploads. If they pass, complete the production canary and recovery/configuration checks before gradual onboarding, starting with the owner and a few members/matters before expanding to all 10–15.

The central recommendation is to keep the foundational investment, adopt permanent-data release discipline now, and make the next accepted outcome a useful matter workflow. The graph should earn trust through correct relationships, sources and actions; additional modules can then ship safely in increments.
