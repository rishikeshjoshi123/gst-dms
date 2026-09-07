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
- Continue with the next independent approved canonical tranche. If the chosen
  work is blocked or the ready queue is exhausted, search across all of `docs/`
  and add other executable approved outcomes to the delivery ledger. One open
  entry does not block the whole goal; preserve explicit deferrals and do not
  treat this file as approval by itself.
- When the user resolves an entry, preserve its dated decision in
  `docs/decision-history/` and keep a short link under **Resolved**. Retain its
  canonical-plan link and implementation evidence; an approved decision is not
  proof that dependent implementation is finished. Preserve existing anchors.

## Open decision index

Read this index at startup and the affected entries below. Detailed history is under [Resolved](#resolved); read a dated record only when its decision is relevant.

| Decision | Affected scope |
| --- | --- |
| [PILOT-RETENTION-SCOPE-2026-09-08](#pilot-retention-scope-2026-09-08--resolve-conflicting-production-activation-rules) | D03/D13: production retention activation; independent repairs continue. |
| [ORG-ASSOCIATE-ACCESS-CATALOGUE-2026-09-04](#org-associate-access-catalogue-2026-09-04--associate-feature-grants) | D03 when grants are enabled; existing Viewer repairs remain independent. |
| [WORK-REVIEW-CONCEPT-2026-09-01](#work-review-concept-2026-09-01--review-workspace-direction) | D08 live Review UI/D13; Task-reader repair remains independent. |
| [ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01](#org-departure-team-concept-2026-09-01--departure-and-team-impact-workflow) | Live Team/departure consumer; independent approved work can continue. |
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

### ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01 — Departure and Team impact workflow

- **Delivery dependency/resume owner:** D03 only if the departure consumer is enabled; next implementation coordinator (task identity unassigned). User decision/date pending; implementation commit not implemented. Broader departure UI remains outside the active repair sequence.
- **Date/domain/plan:** 2026-09-01 · Organisation Administration ·
  Organisation Administration, Team Access, and Personal Settings.
- **Decision needed:** approve the material Team/member-inspector and
  self-service departure-impact direction before replacing the current legacy
  remove-member action with the approved typed departure/administrative
  removal commands.
- **Why the approved contract does not settle it:** the plan specifies impact
  projections, explicit dispositions, role/Owner constraints, and mobile
  behavior, but the existing Settings member removal UI has no reviewed
  departure/confirmation concept.
- **Recommended direction:** create a compact fixture-only concept with a
  Team list/detail workspace, Owner/Admin departure queue, explicit impact
  summary and reassignment/disposition confirmation, plus a separate
  self-service countdown/withdrawal flow. It must not expose another member's
  reason/dependency details to ordinary members.
- **Alternatives/consequences:** retaining the old direct removal flow would
  bypass the approved impact/confirmation contract; delaying this UI does not
  block independent approved backend foundations or other portfolio domains.
- **Concept:** `/dev/organisation-departure-team-concept` (fixture-only;
  no live membership mutation).
- **Current review state:** the agreed revision hides scheduled departure from
  ordinary Team projections, keeps planned departure separate from immediate
  administrative removal, and replaces the removal dialog with a dedicated
  impact-and-disposition workspace. The Team collection now uses the approved
  compact operational-table anatomy, whole-row keyboard/pointer selection,
  one compact 48px desktop row contract for Members and Departure queue,
  stable column proportions, and a 60/40 split that removes repeated fields
  when its inspector opens. The collection keeps Person to a short name-only
  index;
  full work area, email, and joined date move to member details. Its small left
  collection gutter remains fixed across both states.
  The inspector has one consistent width plus aligned fixed header,
  independent body scroller, and action footer. Its body uses a compact
  scan-first hierarchy: departure timing, the two real work areas to pass on,
  the member's actual teammate note, and a dense access summary without nested
  card repetition. The self-service `Before leaving` and `My departure`
  surfaces use one consistent 3:2 desktop alignment grid for summary, timing,
  work, and teammate context, then collapse to the same single-column mobile
  flow. Their ordinary-language impact is limited to open
  tasks and important dates that genuinely belong to the member. Shared Review
  items are excluded: departure only releases a temporary active claim and the
  item stays in Review. The teammate note is described as useful context rather
  than a work-moving control. Undefined `Matter responsibility` and irrelevant
  administrator-coverage jargon are not shown to an ordinary departing member.
  `My departure` places request and withdrawal actions inside its summary on
  desktop, without a repeated header, and retains a mobile bottom action bar.
  Current-tree desktop and 320px checks pass; final user visual approval remains
  outstanding before the live caller is replaced.
- **Exact resume action:** review and approve that concept, record the decision
  here, then replace the legacy live removal caller with the smallest secure
  departure/administrative-removal closure.

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

Dated receipts are preserved separately. Earlier links remain valid through these pointers. Read relevant decisions; old next-action text does not replace the current handoff.

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
