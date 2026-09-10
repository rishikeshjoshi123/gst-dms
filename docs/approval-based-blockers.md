# Approval-based blockers

This is the short, human-readable queue for decisions that need review before a
tranche can safely continue. It prevents one approval boundary from stopping
the rest of the approved portfolio.

## How it works

- Add an **Open** entry when a user decision, visual review, external authority,
  or material policy choice blocks a tranche.
- State the plan, the exact decision, why it cannot be safely inferred, the
  recommended option, and the safe next action after approval.
- Update the open index whenever an entry changes scope or is resolved. The
  detailed entry and actual user decision govern if an index summary is stale.
- Record the affected delivery-ledger outcome/release gate, the task owning
  resumption, the user's actual decision and date, and the commit implementing
  that decision. Unknown owner/commit fields remain `unassigned`/`not implemented`.
- Check this queue at tranche boundaries while a task is running. Editing the
  file does not wake a finished task; resume it with a message or the reusable
  implementation prompt. Settled technical repairs belong in the ledger.
- Continue with the next independent approved outcome within the user-selected
  objective and its prerequisites. A blocked item does not authorise portfolio
  expansion. Use the workflow's current bounded queue; preserve explicit
  exclusions and do not treat this file as approval by itself.
- When the user resolves an entry, preserve its dated decision in
  `docs/decision-history/` and keep a short link under **Resolved**. Retain its
  canonical-plan link and implementation evidence; an approved decision is not
  proof that dependent implementation is finished. Preserve existing anchors.

## Open decision index

September 10: [pre-pilot disposal and normal create-or-join onboarding](decision-history/2026-09-10-planning-and-pre-pilot-policy.md) are user decisions, not open questions. Real-client retention activation, minimum October administration, Matter identity, Review visual approval and enabled AI scope remain unsettled. The removal entry below concerns broader administrative dependencies; it does not make manual first-owner provisioning necessary.

Read this index at startup and the affected entries below. Detailed history is under [Resolved](#resolved); read a dated record only when its decision is relevant.

| Decision | Affected scope |
| --- | --- |
| [PILOT-RETENTION-SCOPE-2026-09-08](#pilot-retention-scope-2026-09-08--resolve-conflicting-production-activation-rules) | D03/D13: production retention activation; independent repairs continue. |
| [ORG-ASSOCIATE-ACCESS-CATALOGUE-2026-09-04](#org-associate-access-catalogue-2026-09-04--associate-feature-grants) | D03 when grants are enabled; existing Viewer repairs remain independent. |
| [WORK-REVIEW-CONCEPT-2026-09-01](#work-review-concept-2026-09-01--review-workspace-direction) | D08 live Review UI/D13; Task-reader repair remains independent. |
| [ORG-ADMIN-REMOVAL-DEPENDENCY-BOUNDARY-2026-09-08](#org-admin-removal-dependency-boundary-2026-09-08--truthful-impact-for-not-yet-canonical-domains) | D15 administrative removal; unrelated approved work continues. |
| [MATTER-IDENTIFIER-POLICY-2026-09-08](#matter-identifier-policy-2026-09-08--external-proceeding-identity-and-collision-rules) | D09 matter identity/create/placement/Restore; unrelated reader work continues. |
| [AI-ACQUISITION-BENCHMARK-THRESHOLDS-2026-09-03](#ai-acquisition-benchmark-thresholds-2026-09-03--ocr-quality-gate-thresholds) | D12 OCR/retrieval cutover; other application work remains independent. |

## Open

### PILOT-RETENTION-SCOPE-2026-09-08 — Resolve conflicting production activation rules

- **Affected outcome/release gate:** D03 and D13 in [the delivery ledger](delivery-ledger.md); confidential-data production activation only.
- **Plans:** [approved Trash contract](plans/platform/2026-08-24-resource-trash-retention-and-purge.md) and [proposed pilot sequence](plans/operations/2026-08-29-design-partner-pilot-execution-sequence.md).
- **Decision needed:** confirm whether the first production pilot uses the completed automatic-retention/governed-purge contract, or deliberately gates it off as the proposed pilot text says.
- **Why it cannot be inferred:** the approved Trash plan explicitly starts production with automatic expiry, but the pilot sequence says permanent purge and unattended destructive automation are unavailable. Both cannot describe the same enabled release. This is activation scope, not a defect in the completed Trash implementation.
- **Recommended direction:** preserve the approved Trash implementation and confirm its intended production activation explicitly; update the pilot matrix and partner-facing retention statement to the selected policy. If activation is deferred, gate commands/schedules without deleting the foundation.
- **Safe independent work:** D01/D02 and other approved upload, source-state, identity and reader repairs. Do not enable/disable production purge or reverse the approved retention design while awaiting this decision.
- **Resume owner:** next implementation coordinator, to record its task identity when claimed.
- **Exact resume action:** record the user's choice/date, reconcile both canonical plans and the release matrix, verify direct commands and scheduled-worker behavior, and add the tested implementation commit to D03.
- **User decision/date:** pending.
- **Implementation commit:** not implemented.

### ORG-ASSOCIATE-ACCESS-CATALOGUE-2026-09-04 — Associate feature grants

- **Delivery dependency/resume owner:** D03 if these grants are enabled; next implementation coordinator (task identity unassigned). User decision/date pending; implementation commit not implemented. Existing Viewer-ceiling repairs in D02 are independent.
- **Date/domain/plan:** 2026-09-04 · Organisation Administration ·
  Organisation Administration, Team Access, and Personal Settings.
- **Decision needed:** approve the bounded first-release catalogue of feature
  access that an Owner/Admin may grant or revoke for an Associate, plus the
  impact and audit presentation for those changes.
- **Why the approved contract does not settle it:** Organisation settings now
  reserves a dedicated `Access` section, but choosing the exact grant keys
  changes permissions across multiple domains and should not be inferred from
  the Document Hub concept.
- **Recommended direction:** design a small task-oriented catalogue based on
  real feature boundaries—not a free-form ACL editor—with effective-access
  explanations, resource-access intersection, audit history, and explicit
  save/revoke consequences. `Manage shared intake` is already fixed as one
  bundled grant: it gives `All uploads` together with standard shared-triage
  actions rather than a view-only global queue. All grants must remain below
  the Associate role ceiling.
- **Alternatives/consequences:** putting permission controls inside individual
  feature pages fragments authority; exposing arbitrary capability keys is too
  technical and makes unsafe combinations likely.
- **Exact resume action:** inventory the cross-domain Associate capabilities,
  propose the smallest grouped catalogue and Access-section concept, then obtain
  approval before implementing grant mutations.

### WORK-REVIEW-CONCEPT-2026-09-01 — Review workspace direction

- **Delivery dependency/resume owner:** D08 live Review UI and D13; next implementation coordinator (task identity unassigned). User decision/date pending; implementation commit not implemented. Canonical Task-reader repair is independent.
- **Date/domain/plan:** 2026-09-01 · Work · Work Orchestration, Review,
  Activity, Notifications, and Today.
- **Decision needed:** approve the material production direction for the
  dedicated Review queue and decision pane, including its evidence-first
  desktop layout and mobile list-to-detail flow.
- **Why the approved contract does not settle it:** the plan defines Review
  state, evidence, permissions, and interaction requirements, but the
  production workspace has no reviewed `/dev` concept.
- **Recommended direction:** approve the compact fixture-only Review concept
  with stable queue filters, an evidence/decision detail pane, explicit
  primary decisions, and the approved mobile drill-in; it does not reproduce
  the legacy Dashboard/Review four-table query.
- **Alternatives/consequences:** implementing a live Review workspace without
  visual review crosses the approved material UI boundary; delaying it does
  not block the independently approved Organisation Administration tranche.
- **Concept:** `/dev/review-workspace-concept` (fixture-only; no live reader,
  producer, command, notification, or Dashboard query).
- **Exact resume action:** review and approve that concept, record the visual
  decision here, then implement the smallest secure Review producer/consumer
  closure.

### ORG-ADMIN-REMOVAL-DEPENDENCY-BOUNDARY-2026-09-08 — Truthful impact for not-yet-canonical domains

- **Delivery dependency/resume owner:** D15 administrative removal; next implementation coordinator. The approved Team/departure visual direction remains resolved and must not be reopened.
- **Date/domain/plan:** 2026-09-08 · Organisation Administration · [Organisation Administration, Team Access, and Personal Settings](plans/platform/2026-08-26-organisation-administration.md#membership-lifecycle-and-offboarding).
- **Decision needed:** choose whether the first live administrative-removal closure must first add canonical accountable-deadline and addressed-notification ownership/lifecycle foundations, or whether the plan should define a truthful current-domain boundary that omits categories which do not yet have canonical ownership state. Review claims, cost grants, and digest schedules likewise do not exist and cannot be represented as zero dependencies.
- **Why it cannot be inferred:** the approved removal contract requires a current impact projection and explicit dispositions for accountable verified deadlines plus lifecycle effects across notifications, Review claims, grants, and schedules. The live schema has canonical Tasks, but legacy deadlines have no assignee/verification/revision identity; Review claims, cost grants, and digest schedules are absent; notification reads are not membership-fenced. Hard-coded zero counts or inferred ownership would misrepresent the approved contract, while silently pulling every future domain into D15 would materially expand scope.
- **Recommended direction:** add the smallest canonical addressed-notification access fence and historical-identity preservation required for immediate removal, and sequence a real accountable-deadline ownership slice before enabling removal. Treat absent Review/grant/digest domains as explicitly not yet applicable in the canonical plan rather than displaying invented zero checks. Then implement the approved Team impact/disposition workflow with atomic Task reassignment/unassignment, stale-impact and concurrency fencing, durable history, and immediate access revocation.
- **Safe independent work:** D09 matter identity, D11 bounded Matter navigation, remaining D06 source/freshness work, and other approved work that does not enable removal or fabricate impact. Do not reconnect `removeMember`, expose a destructive shortcut, or implement self-service departure while this boundary is open.
- **User decision/date:** pending.
- **Resume action:** record the chosen boundary in the canonical Organisation plan, then issue one decision-complete D15 administrative-removal writer brief with SQL/concurrency, historical-author, removed-session, notification, and responsive browser acceptance.

### MATTER-IDENTIFIER-POLICY-2026-09-08 — External proceeding identity and collision rules

- **Delivery dependency/resume owner:** D09 matter identity correction; next implementation coordinator.
- **Date/domain/plan:** 2026-09-08 · Document Hub / Trash · [Matter identity correction](plans/features/2026-08-25-document-hub-ingestion-and-workbench.md#matter-identity-correction) and [Restore](plans/platform/2026-08-24-resource-trash-retention-and-purge.md#restoration).
- **Decision needed:** approve the initial typed external matter-identifier policy: supported kind and issuer/system namespace; structured components and normalization; collision scope; verification authority/provenance; correction/revocation; and active/Trash/reuse behavior for each kind.
- **Why it cannot be inferred:** the plan requires `matter_identifiers` with uniqueness rules appropriate to each identifier type but does not enumerate those rules. The current schema has only organisation-unique CaseChain `matter_code` plus the unsafe client/FY index. Treating document references, GSTIN/PAN, titles, or financial year as verified proceeding identity could merge distinct proceedings or block legitimate records.
- **Recommended direction:** define a small versioned identifier matrix for explicit human-verified proceeding/portal/case keys, preserve issuer/system namespaces and provenance, and forbid OCR/fuzzy evidence from asserting verified identity. Align create/update, destination lookup, Restore, and purge to the same lifecycle rules; repair concurrent CaseChain code allocation before removing the client/FY index.
- **Safe independent work:** D11 bounded Matter readers/navigation and other approved work not changing matter identity. Do not drop `idx_matters_unique_client_fy`, loosen Restore conflicts, or add inferred identifier backfill before this decision.
- **User decision/date:** pending.
- **Resume action:** update the canonical Document Hub plan with the approved matrix, then issue one D09 writer brief covering audit/backfill, identifier-aware commands, code allocation, destination selection, Restore, purge cleanup, SQL/concurrency, browser acceptance, and independent QA.

### AI-ACQUISITION-BENCHMARK-THRESHOLDS-2026-09-03 — OCR quality-gate thresholds

- **Delivery dependency/resume owner:** D12 acquisition/retrieval cutover and D13; next implementation coordinator (task identity unassigned). User decision/date pending; implementation commit not implemented.
- **Date/domain/plan:** 2026-09-03 · AI Extraction and Provenance; Universal
  Search and Evidence Retrieval · [AI lifecycle plan](./plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md#prompt-and-model-evaluation).
- **Decision needed:** approve measurable pass/fail thresholds for the labelled
  60–100-page Mumbai acquisition benchmark: native/OCR routing precision and
  recall, character/word accuracy on OCR pages, each exact critical-fact
  metric, table/anchor correctness, latency, billed pages, and cost.
- **Why the approved contract does not settle it:** it requires every metric to
  be reported separately and prohibits a confidence aggregate from masking a
  critical error, but it does not define a threshold at which benchmark evidence
  authorises shadow backfill or Search cutover.
- **Recommended direction:** require no critical GSTIN/reference/date/amount,
  table, or anchor error in the initial representative set; require documented
  routing and OCR-quality floors, and a pre-approved per-page/corpus cost and
  latency ceiling. Treat a handwritten/low-quality exception as Review/manual
  handling rather than permitting it to dilute a critical metric. Record the
  exact numeric values beside the benchmark result.
- **Alternatives/consequences:** a qualitative approval after reviewing the
  content-safe report preserves discretion but is slower and less repeatable;
  inventing thresholds in code would silently change the approved product risk
  policy.
- **Concept/evidence:** local-only `scripts/document-ai/ocr-acquisition-benchmark.ts`
  emits `evidence_complete` rather than a quality pass until this decision is
  recorded; it never contains PDFs, extracted text, paths, or credentials.
- **Exact resume action:** provide/approve the threshold table, create the
  external adjudicated manifest, run the exact pinned Mumbai evaluator over 60–100
  unique pages, then review the content-safe report and decide whether its
  evidence satisfies the approved gate.


## Resolved

### 2026-09-10 — Pre-pilot data and normal onboarding

[Recorded user decisions](decision-history/2026-09-10-planning-and-pre-pilot-policy.md). D03/D13 require normal create-or-join implementation; prior restriction receipts are historical. No reset or implementation resumption occurred.

Dated receipts are preserved separately. Earlier links remain valid through these pointers. Read relevant decisions; old next-action text does not replace the current handoff.

### ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01 — Departure and Team impact workflow

**Resolved 2026-09-08:** the user approved the current revised concept. [Recorded decision and resume conditions](decision-history/2026-09-08-organisation-departure-team-concept.md). D15 may proceed when technical prerequisites are ready; its live implementation remains pending.

### 2026-09-08 — Source scope and single-task implementation workflow

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-08--source-scope-and-single-task-implementation-workflow).

### 2026-09-05 — Document Hub and Workbench concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-05--document-hub-and-workbench-concept).

### 2026-09-03 — Mumbai OCR processor promotion

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-03--mumbai-ocr-processor-promotion).

### 2026-09-01 — Independent backup destination for the design-partner release

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--independent-backup-destination-for-the-design-partner-release).

### 2026-09-01 — Search page-text source and first-release embedding scope

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--search-page-text-source-and-first-release-embedding-scope).

### 2026-09-01 — Page acquisition, English metadata, and India processing boundary

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--page-acquisition-english-metadata-and-india-processing-boundary).

### 2026-09-01 — Task comments workspace direction

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-comments-workspace-direction).

### 2026-09-01 — Task RPC organisation-selection authority

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-rpc-organisation-selection-authority).

### 2026-09-01 — Dedicated Tasks workspace concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--dedicated-tasks-workspace-concept).

### 2026-08-31 — Local browser QA authority for permanent-delete verification

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--local-browser-qa-authority-for-permanent-delete-verification).

### 2026-09-01 — Task and legacy note action-item compatibility

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-09-01--task-and-legacy-note-action-item-compatibility).

### 2026-08-31 — Trash permanent-delete concept

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--trash-permanent-delete-concept).

### 2026-08-31 — Retention for historical soft-deleted records

[Recorded decision](decision-history/2026-09-08-resolved-decisions.md#2026-08-31--retention-for-historical-soft-deleted-records).
