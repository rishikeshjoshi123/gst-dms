# October design-partner release reassessment

Assessment date: 10 September 2026. Committed baseline: `24d9d77` on `dev`. Read together with the [September 8 audit](2026-09-08-delivery-strategy-and-phased-pilot-review.md).

Subsequent disposition: the user accepted [non-critical execution/documentation recommendations](../decision-history/2026-09-10-planning-and-pre-pilot-policy.md#non-critical-october-recommendations-accepted), superseded the initial preservation/manual-bootstrap assumptions with disposable pre-pilot data and normal create-or-join onboarding, and on September 14 fixed the [first-production release scope](../decision-history/2026-09-14-first-production-release-scope.md). Production ownership, compliant hosting/recovery and incident response remain pending. The original assessment below is retained as dated analysis, not current scope or an instruction to preserve tester data.

This is an evidence-based scope recommendation and documentation change specification, not an approved replacement execution plan. The user has moved the client presentation to October 12–15, can contribute 1–3 hours daily, and accepted the previous data-preservation and focused-delivery recommendations. They have not resumed the stopped implementation task, approved every release-policy choice below, or authorised deployment. Existing modified files have been preserved.

## Recommendation

Use the additional month to deliver a coherent, production-capable design-partner release whose distinguishing feature is an evidence-backed Matter graph with accountable next actions. Do not use the extra time to resume unrestricted implementation of the entire portfolio.

A credible October release is achievable under the assumptions below, but this is an engineering forecast, not measured velocity or a delivery guarantee. The release should remain useful with human-entered/confirmed document metadata and relationships. Assisted extraction and relationship suggestions can improve that workflow when their quality gates pass. The graph itself should be a release requirement; broad automatic legal interpretation should not be.

Keep the October demonstration date distinct from permission to accept confidential production data. Aim to satisfy both together. If the data-safety gates fail, demonstrate the staging release and defer onboarding; a presentation deadline does not waive the gates.

## What changed since the earlier audit

- [D15-T01](../delivery-evidence/D15-T01.md), implementation `b3837d5`, adds the secure read-only Team directory and inspector and removes the dormant unsafe legacy removal action. Its SQL fixture and authenticated browser acceptance remain unexecuted.
- [D11-T04](../delivery-evidence/D11-T04.md), implementation `168d69e`, makes authoritative chronology the sole live Timeline presentation until the new graph is implemented. It includes bounded current-version reads, URL selection/filter state and Trash parity. Disposable SQL acceptance passed historically; browser acceptance remains open.
- [D11-T05](../delivery-evidence/D11-T05.md), implementation `9663a10`, adds typed Matter work state/forum, compatibility handling and governed mutations. A populated pre-migration replay and authority fixtures passed historically. Browser/deployed/scale acceptance remains open.
- Evidence commit `24d9d77` follows these changes. The ledger says the user stopped implementation after D11-T05. The handoff still contains older next-action bullets above its newer checkpoint; these should be reconciled before resumption.
- No Playwright/Puppeteer package resolves in the current project dependency tree. There is no committed browser acceptance runner in the inspected package scripts. The existing test base is useful but does not provide a repeatable authenticated end-to-end release gate.
- `.github/workflows/supabase-migrations.yml` pushes migrations to the configured remote on relevant `main` pushes after migration-number/type checks. It does not first run populated upgrade fixtures, the full browser journey, or an explicit staged application/worker compatibility gate. Repository inspection does not establish whether that remote is production or whether external branch/environment protections exist.

These are source and receipt observations. This reassessment did not rerun the application, database or deployed acceptance suites and does not upgrade historical test claims into current release acceptance.

## Screen-off and locked-Mac operation: first priority

The inspected power assertions showed a running `caffeinate` process preventing idle system sleep. Display sleep remained allowed. The reported problem therefore cannot be explained simply by missing idle-sleep prevention.

Separate three conditions: display off, macOS session locked, and machine asleep. Ordinary file, shell and database work can run while an awake machine is locked. Desktop interaction has additional session/permission requirements.

OpenAI documents a macOS **Locked use** option under **Settings → Computer Use**, including its connected-device setup and safeguards. Follow the [official instructions](https://learn.chatgpt.com/docs/computer-use#locked-use). Its availability/enabled state was not verified in this installation: Computer Use refused access to the Codex app itself. No security settings were changed, and no locked-screen acceptance test was performed.

The durable engineering solution is a project-owned browser/database acceptance runner, with unattended execution proved in the actual environment. Playwright provides headless execution and [CI support](https://playwright.dev/docs/ci); see its [test runner documentation](https://playwright.dev/docs/running-tests). Use interactive desktop/browser inspection for exploratory and visual judgement in addition to that runner.

Proposed first acceptance increment:

1. Pin the runner and supported browsers, use the repository's Node 24 contract, and document one reproducible local command.
2. Create a disposable local database fixture containing two organisations, relevant roles, active/suspended users, representative documents and graph cases. Confirm local mail/storage/jobs before any reset or synthetic signup. Preserve existing databases.
3. Exercise real application/database auth, invitation entry, client/matter creation, upload/assignment, PDF reopening, denied foreign IDs and suspended access. Seed routine sessions as fixtures, while retaining a separate genuine signup/invite flow test; do not replace tenant enforcement with mocks.
4. Add desktop/mobile, keyboard, long-content and failure screenshots/traces with synthetic data. Tests of supported workers should use deterministic controlled fixtures, with deployed integrations accepted separately.
5. Prove completion while the display is off and while the session is locked; separately prove the runner in CI. A failed Computer Use attempt must not be reported as a failed application workflow or vice versa.
6. Keep human visual review in the daily window. Screenshots and assertions support, but do not replace, judgement about graph comprehension and interaction.

The installed `caffeinate` manual confirms that plain `caffeinate` prevents idle sleep. On AC, `caffeinate -is` is an optional stronger sleep assertion while preserving display sleep; it does not unlock macOS. Keeping the display illuminated is not the intended permanent fix.

## Why the graph was deferred, and what makes it substantial

The [existing pilot proposal](../plans/operations/2026-08-29-design-partner-pilot-execution-sequence.md) explicitly prioritises the document/OCR/cited-retrieval journey and defers the full procedural graph. The [Matter plan](../plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md) independently sequences shell/chronology/Files before graph. Neither establishes that a useful graph is infeasible. The release priorities no longer match the user's stated value proposition.

React Flow and Dagre are already dependencies and approved design decisions exist. The difficult work is the domain authority surrounding the canvas:

- A chronological neighbour, reference mention and procedural relationship are different facts. A date sort cannot establish that an order decides an appeal or a reply responds to a particular notice.
- Canonical relationship commands must enforce tenancy, permission, endpoint validity, active Matter/client lineage, duplicate rules and cycle protection. Direction and display wording must agree.
- The relationship must preserve its source/manual basis, human decision, revision and correction history. Pending suggestions cannot appear as confirmed legal progression.
- Reclassification, reassignment, replacement, Trash and restore must invalidate or reconcile affected derived state safely.
- Branches, disconnected documents, unknown dates and missing PDFs must remain comprehensible. Pan/zoom, selection, evidence inspection and chronology fallback must work without jumping layouts.
- The current action is a separate recorded obligation or Task with an owner and state. It cannot be inferred reliably from the last graph node, and several parallel actions may remain open.

The planned canonical `document_relationships` model was not found in the migration inventory. Therefore a cosmetic revival of the legacy graph would bypass the main remaining work.

Recommended sequence: authoritative chronology (already implemented locally) → effective human-confirmed relationship commands and graph → verified actions/deadlines → quality-gated suggestions. Use the same permanent canonical model from the first graph increment. “Manual first” describes how facts become authoritative, not a temporary schema or reduced visual ambition.

## October product boundary

### Required

- One permanent design-partner organisation and owner, with a tested bootstrap/provisioning path; verified account entry, invitations for 10–15 members, understandable roles and a tested immediate access-revocation path. Broad public organisation creation is a separate scope choice.
- Clients and multiple distinct Matters, including more than one proceeding for the same client/financial year. Preserve stable identity through create, assignment, move and restore.
- Upload into a chosen Matter, shared Intake/manual assignment where enabled, truthful processing/failure/retry, private current-PDF preview and stable source reopening. Human fallback must be implemented, not inferred from disabling AI workers.
- Timeline graph with canonical effective relationships, evidence/manual basis, readable branches/unlinked documents, correction history, selection/inspector, useful chronology and mobile presentation.
- A compact “what needs attention” area with named owners, status, source/manual basis, overdue visibility and completion. Legal dates use the canonical human-verified deadline slice; internal work dates use Tasks. Unknown dates stay unknown.
- Minimum Review, notes and Activity needed to support these decisions and workflows; no unsafe legacy mutation remains reachable through a hidden screen.
- Controlled production configuration, coordinated app/database/worker rollout, operational error/job visibility, verified recovery boundaries and tested upgrade preservation.

### Conditional enhancements

OCR/extraction, suggested relationships, cited retrieval and reminders can ship only where their own evaluation, Review, recipient and failure contracts pass. Preserve completed foundations and existing approved processing boundaries. Confirm the revised release scope explicitly before removing an existing pilot requirement. Never waive an AI gate while continuing to expose the gated behaviour.

### Explicitly defer from the October implementation objective

Full Dashboard/Today; complete financials and Case Brief generation; organisation-wide semantic search; broad administrative grants/departure automation; advanced platform console and analytics; broad Realtime; marketing/demo refinement; bulk ingestion and non-PDF breadth. Existing necessary security/lifecycle foundations remain maintained. Retention/purge activation is an unresolved policy decision, not automatically disabled by this recommendation.

Hide unused top-level destinations. Use “coming soon” in the existing Matter structure when it helps orientation. The core client journey must be complete without following a placeholder. Measure progress by accepted journeys, not by the number of sections filled.

## Proposed calendar and checkpoints

Dates are targets with dependency gates, not unconditional promises.

| Window | Observable outcome | Checkpoint consequence |
| --- | --- | --- |
| Sep 10–13 | Repeatable unattended QA foundation; current browser/SQL gaps triaged; agreed release scope; representative Matter fixtures and expected relationships/actions; first staging configuration | Resolve Review concept, Matter identity, minimum member administration and retention direction together. If runner/environment cannot execute, repair that dependency before accumulating more unaccepted UI. |
| Sep 14–20 | Invite → client/Matter → upload → assign → reopen works; first evidence-backed manual relationship graph on a representative Matter | Target a first usable graph around Sep 17–20. Missing this checkpoint consumes enhancement budget, not the final safety week. |
| Sep 21–27 | Graph/inspector polished on ordinary and awkward Matters; accountable actions and verified deadlines; core Review/corrections; mobile and source failure behaviour | The user can explain the progression and next responsibilities without agent guidance. Select any remaining AI enhancement by observed quality, not an assumed threshold. |
| Sep 28–Oct 4 | Complete enabled workflow regression, populated upgrades, role/revocation checks, deployed mail/storage/worker rehearsal and recovery evidence | Feature freeze by Oct 4. No unrelated feature breadth enters the release. |
| Oct 5–11 | Release candidate, defect repairs, rehearsal, partner instructions and support path | Preserve this stabilisation week. Resolve release gates against the exact deployed revision/configuration. |
| Oct 12–15 | Partner demonstration; controlled onboarding if gates pass | Start with a few active Matters and a small initial group, then the remaining invited members. Demonstration alone does not imply confidential-data approval. |

Do not wait until the final week to configure hosting, email, storage, workers or environments. Establish staging during the first week and exercise the evolving deployed workflow throughout.

Planning allowance: approximately **120–200 effective engineering/QA hours**, including targeted setup and repair reserve. This is a judgement-based range, not observed throughput or a conversion from subscription quota. A rough allocation is 12–20 hours for unattended acceptance, 18–30 for core entry/document closure, 30–50 for canonical graph delivery, 16–28 for actions/deadlines integration, 20–35 for release verification and 20–35 for repair/uncertainty. These allowances overlap at the margins and should be recalibrated after the first three days.

That implies roughly 30–50 effective project hours per week over four weeks, mostly agent execution. Human steering is a separate budget. If approvals, quota or external configuration regularly prevent execution, elapsed time extends. Completing every remaining plan is still a materially larger effort; the prior 300–500-hour, 6–10-productive-week broad estimate remains a rough order of magnitude, not a fresh exhaustive re-estimate or an October commitment.

## Working within 1–3 human hours daily

A normal daily window can be 60–90 minutes: 10 minutes on outcomes/blockers, 20–30 using a finished workflow, 20–30 deciding the next small set of product choices, and 10–20 reviewing labelled cases or the next acceptance target. Reserve longer sessions for graph design/domain validation, production setup and release rehearsal.

The implementation owner should deliver one compact packet: usable result/preview, exact checks and gaps, at most three material decisions with a recommendation, and the next independently executable outcome. Routine technical choices remain with the agent. Batch decisions early enough that evening input feeds the next work period. Do not require the user to supervise terminal commands or every helper handoff.

Keep one writer and independent high-risk QA. Assign a capable implementer directly to graph/domain integration; the D11-T04 receipt demonstrates that starting a difficult cross-layer change with an underpowered assignment can create diagnosis/repair overhead. Use early focused design/authority review for difficult boundaries. Independent preparation or fixture design may run alongside implementation within the approved workflow; reviewers should inspect a stable revision. No measured evidence justifies claiming a particular speed multiplier from model routing.

Track accepted user journeys, first-pass acceptance, material repair cycles and time blocked on decisions/environment/quota. A prerequisite-only increment must name the consumer it enables. Broader portfolio discovery must not restart whenever a release-specific decision is waiting.

## Subscription decision

Official pricing lists Pro 5x and 20x relative to Plus; moving from 5x to 20x provides approximately four times the included usage allocation, not a promised fourfold delivery speed. See [current pricing](https://learn.chatgpt.com/docs/pricing).

At inspection, the account reported 52% of its main weekly allowance used, resetting September 15 at 06:55 IST, and two available full-reset credits expiring October 4 and 5. No credit was redeemed. A snapshot does not establish a future consumption rate.

Recommendation: establish the focused queue and unattended verification first. If the added subscription cost is comfortable, 20x is reasonable for this delivery month to reduce quota interruptions during sustained implementation and independent QA. It cannot solve missing decisions, blocked desktop access or an expanding objective. If remaining on 5x, measure several days of consumption and make the upgrade decision before quota stalls the critical path; reset credits provide contingency rather than a throughput guarantee.

## Permanent-data rule

The user accepted preserving production data, deployed migration history, stable identities, human corrections and source versions, and testing upgrades against populated records. Adopt this as a release invariant.

Substantial schema evolution need not delete or reset accounts, organisations, Matters or documents. Prefer additive changes, explicit backfill, compatibility reads/writes where required, and delayed retirement after old application sessions and workers are no longer relying on the prior contract. Test conflict/stale-job cases and record the operational rollback approach; application rollback and database recovery are separate operations.

D11-T05's additive work-state migration and populated upgrade fixture are useful local precedent, but not proof that every future migration is safe. Production must not be the environment used for resets or schema experimentation. Protect the deployment workflow accordingly. Honour the existing first-organisation backup/object-recovery decision unless explicitly revised; do not silently invent a new external backup destination or declare Storage objects covered by database backups.

Agents can implement and run database, browser, migration, security-regression, failure and performance tests in authorised environments. They can prepare deployment/recovery tooling and evidence. Human domain judgement, external-account configuration and actual production authority remain necessary. Advanced analytics can wait; basic operational visibility and data safety cannot.

## Required documentation revisions

Revise canonical files in place after release scope is settled. Preserve original filenames, stable outcome IDs, approvals and receipt history. This table is a change specification; it does not mark those edits as performed.

| File or canonical group | Required change |
| --- | --- |
| `docs/plans/operations/2026-08-29-design-partner-pilot-execution-sequence.md` | Make October 12–15 the target; promote graph/actions to required scope; separate mandatory, conditional and explicitly deferred outcomes; add dated checkpoints, feature freeze and deployment gates. Replace contradictory graph-deferral/document-first instructions. Keep `proposed` until material policy/scope decisions are settled. |
| `docs/implementation-prompt.md` | Replace “all remaining approved implementation” with the defined October release objective. Restrict blocked-work discovery to that scope and necessary prerequisites. Preserve model choice, one owner, independent QA and actual deployment authority. Editing this file must not resume the paused task. |
| `docs/plans/operations/2026-09-08-agent-delivery-workflow.md` | Make explicit release exclusions implementation deferrals for this objective; stop mandatory all-portfolio discovery. Add repeatable browser/database evidence, early stable boundary review, bounded repair and accepted-workflow reporting. Preserve strong authority/QA rules. |
| `docs/delivery-ledger.md` | Order current IDs against release outcomes/dependencies; retain the unexecuted SQL/browser/deployed gates. Record deferred October breadth explicitly. Represent a blocked dependency separately from the workflow's allowed status values. Add acceptance-harness/relationship outcomes only where existing IDs do not cover them. |
| `docs/implementation-handoff.md` | Reconcile the old top bullets with the D11-T05/current HEAD checkpoint; preserve the user-requested stop. Leave one current next action, owned dirty files, checks/gaps and process state, with links to history. |
| `docs/approval-based-blockers.md` and `docs/decision-history/` | Record the user's actual September 10 date/time/data/workflow decisions. Order remaining decisions by the pilot dependency they block and requested-by date. Resolve Review concept, Matter identity, retention and minimum administration; defer grant catalogue only if excluded. Keep AI thresholds conditional on shipping the gated capability. Do not treat willingness to upgrade as purchase authority. |
| `docs/plans/platform/2026-08-24-product-architecture-portfolio.md` | Retain full architecture but identify the October subset and explicit implementation deferrals. Remove next-action wording that returns a blocked pilot to arbitrary portfolio work. |
| `docs/plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md` | Make the graph a release requirement after chronology; retain canonical direction/evidence/acyclic rules, mobile chronology and tested scale. Link accountable attention to Tasks/Deadlines; never infer obligations from graph topology. Preserve settled visual contracts. |
| `docs/plans/features/2026-08-25-document-hub-ingestion-and-workbench.md` | Specify the earliest canonical human-confirmed relationship workflow and source/correction lifecycle; sequence automated candidates later. Make upload/placement/manual fallback independently usable and keep exact attachment/retry acceptance. |
| Work/Review and Deadlines/Financials plans | Identify the minimum typed Review resolver, action-owner projection and verified deadline lifecycle required by the pilot. Explicitly defer broad Today, reminders unless accepted, and financial breadth. Preserve the difference between a Task date and a legal deadline. |
| Organisation Administration plan | Clarify first owner/org bootstrap, invitation journey, pilot role matrix and immediate access suspension/revocation. Separate essential access control from full departure, transfer and grant administration. Preserve the already-approved Team visual decision. |
| Document Lifecycle, Trash and Platform Operations plans | Add populated-upgrade/compatibility evidence and coordinated staging/production promotion to the release contract. Resolve retention activation at its owning source. Preserve the approved managed-database/client-original recovery boundary unless changed by the user; distinguish broad analytics from required error/job visibility. |
| AI and Search plans | Mark release inclusion conditional where proposed; keep approved processing/privacy and evaluation contracts. Do not require their full breadth as a prerequisite for manually confirmed graph value. |
| One new operational acceptance runbook, linked from `docs/README.md` | Document exact local/CI setup, disposable fixtures, supported unattended execution, environment checks, commands and artefacts. Keep it operational; do not create another coordinator, progress tracker or duplicate plan. |
| `docs/plans/README.md` and `docs/README.md` | Update canonical links, dates/statuses and routing once the owning documents change. Do not claim approvals just because an index was edited. |

No wholesale design-system rewrite is warranted. Reuse the approved patterns and update shared component/gallery documentation only when an actual reusable UI contract changes. Historical delivery receipts should remain dated evidence; update current status through the ledger instead of rewriting history to look complete.

## Decisions needed before this becomes the execution plan

The October date, daily availability, data preservation and focused-delivery principles are confirmed. The precise release inclusion of AI/retrieval, first-organisation bootstrap, minimum role/access administration, retention activation and Matter identity still need a concrete scope decision or the already-recorded approval. Review's concept gate remains real. Resolve these in one short planning session with recommendations and example journeys; then revise the existing pilot plan and execution prompt together. Until then, this review is not a decision-complete plan and does not replace the canonical archive.
