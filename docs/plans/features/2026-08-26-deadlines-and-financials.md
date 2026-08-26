---
title: Verified Deadlines and Matter Financials
status: approved
created: 2026-08-26
updated: 2026-08-26
owners:
  - product
  - engineering
related:
  - ./2026-08-25-matter-workspace-and-procedural-timeline.md
  - ./2026-08-25-work-review-activity-notifications.md
  - ./2026-08-25-document-hub-ingestion-and-workbench.md
  - ./2026-08-25-notes-and-case-brief.md
  - ../platform/2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../platform/2026-08-24-resource-trash-retention-and-purge.md
---

# Verified Deadlines and Matter Financials

## Summary

Replace CaseChain's minimal deadline rows and flat `raw_metadata.extracted_amounts` object with two evidence-centred domains.

**Deadlines** owns legally or procedurally consequential dates, scheduled authority events, verification, responsibility, completion, and reminder scheduling. Internal work dates remain first-class Task due dates and may be projected into the same agenda without becoming legal deadlines.

**Financials** owns versioned financial statements and line items that distinguish proposals, taxpayer positions, operative findings, payments, pre-deposits, relief, refunds, and adjustments across GST proceedings. It renders deterministic, evidence-linked evolution rather than asking AI to invent a graph or a universal net exposure. Optional internal litigation costs use a separate permissioned ledger.

Both domains consume normalized extraction candidates, preserve human authority, open exact source evidence, emit Activity/outbox events, integrate with Review/My Work/Today, and provide Matter and organisation projections. The review implementation is demonstrated at `/dev/deadlines-financials-concept`.

## Context and Goals

The current `deadlines` table stores only Matter, optional Document, enum type, date, description, two fixed reminder booleans, and resolved state. It lacks organisation lineage, evidence, verification, ownership, timezone/time precision, cancellation/supersession, reminder recipients, and safe correction history. The ingestion worker blindly inserts every extracted deadline on each full retry and discards source page, quotation, and confidence, so duplicate reminders and untraceable dates are possible. The daily reminder job is a placeholder, while the dashboard excludes overdue dates.

Financial data has no canonical domain. The extractor returns one flat set of `tax`, `interest`, `penalty`, `fee`, `pre_deposit`, `total_demand`, `amount_in_dispute`, and `amount_relief` values in document JSON. Those values cannot say whether an amount is alleged, proposed, admitted, disputed, confirmed, paid, dropped, stayed, refunded, or adjusted; cannot represent tax head; and cannot safely show how an SCN becomes an order or appeal.

The design must reflect GST evidence without pretending to calculate law. Official demand/payment material distinguishes tax or cess, interest, penalty, fee, and other amounts, commonly across IGST, CGST, SGST/UTGST, and Cess. Orders, rectifications, payments, and appeals can change different components differently. The application therefore preserves source statements and their legal character rather than subtracting arbitrary numbers into a misleading “current exposure.”

Success means:

- extracted dates and amounts remain useful immediately but cannot trigger consequential reminders or verified portfolio totals without the approved verification policy;
- every material date and financial line opens exact document-version/page evidence or states its human/manual basis;
- retries, re-extraction, replacement PDFs, and corrections never duplicate or silently replace records;
- overdue dates remain visible and actionable instead of disappearing;
- Matter Financials explains how material amounts changed across proceedings without mixing incompatible totals or internal expenses;
- organisation pages provide secured operational projections without copying source state;
- desktop and mobile retain equivalent workflows with explicit scroll ownership and no gratuitous dashboards.

Out of scope are automatic legal advice, AI-calculated limitation dates, tax-return/accounting reconciliation, bank/payment execution, invoicing, time billing, trust accounting, currency conversion, client portal access, and arbitrary AI-generated charts.

## Decisions

### Domain boundaries

- A **legal deadline** is an externally consequential last date or obligation tied to law, an authority/court direction, or a proceeding.
- A **scheduled event** is a dated occurrence such as a hearing. It appears in the deadline agenda but uses event language (`Scheduled`, `Occurred`, `Adjourned`) rather than completion language.
- An **internal milestone** such as `research draft discussion` is a Task due date. The Deadlines UI may project it when `Include internal milestones` is enabled, but it is created and completed through Tasks.
- A **financial statement** records what one source says at one procedural stage and from one perspective. Its line items are not automatically the Matter's present payable balance.
- **Internal litigation costs** are operational expenses such as filing, travel, research vendor, courier, or consultant cost. They never mix with tax demand, penalty, interest, payment, relief, or refund totals.
- Timeline owns document sequence. Deadlines and Financials link to Timeline documents but do not create graph nodes. Case Brief may show compact verified current facts and deep-link here; it does not duplicate these visualizations.

### Deadline classes and origins

- `deadline_class` is `legal_deadline` or `scheduled_event`. Task milestones retain `task` identity in projections rather than entering this enum.
- Initial legal types are `reply_due`, `appeal_due`, `payment_or_predeposit_due`, `compliance_due`, `stay_application_due`, and `other_legal`.
- Initial event types are `hearing`, `conference`, `inspection`, and `other_event`.
- `origin` is `document_explicit`, `manual`, or `rule_calculated`. Initial release implements document-explicit and manual origins. Rule-calculated records require the later controlled rule catalogue described below.
- Document extraction creates a provisional candidate only when an explicit calendar date is stated. Relative text such as `within three months of communication` is preserved as an unresolved source candidate and never converted into a date by the model.
- The prompt extracts date/time/timezone only when explicit, plus classification, description, triggering language, source page/quote/region, and confidence. Domain validation checks real dates, page bounds, duplicate semantic keys, and consistency with document type.

### Deadline time contract

- Preserve the source's precision: `date_only` or `date_time`. A date-only obligation is not silently stored as UTC midnight.
- Date-time records store local timestamp, IANA timezone, and derived UTC instant. Organisation timezone is the default only for a human-entered time without an explicit source timezone and is visibly disclosed.
- Date-only due status changes at the organisation's configured end-of-day boundary. Scheduled events use their explicit/local start time and optional end time.
- Display source timezone when it differs from the current user's timezone. Calendar grouping uses organisation timezone; personal reminder delivery uses the recipient's timezone without changing the legal due value.

### Verification and lifecycle

- `verification_state` is `provisional`, `verified`, `rejected`, or `conflict`. Extracted candidates begin provisional. Human-created legal dates begin verified with human provenance.
- Provisional dates are visible in Matter Deadlines and, when assigned for verification, Review/My Work. They do not create reminders, urgent Today items, external emails, or verified organisation counts.
- One focused Review item handles weak evidence, conflicting sources, changed document version, or consequential first activation. Safe dates may be verified inline by an authorised Associate; conflicts remain individual Review decisions.
- Editing an extracted date appends a human correction referencing the candidate and preserves the original. Re-extraction cannot replace that correction.
- Legal deadline lifecycle is `open`, `satisfied`, `cancelled`, or `superseded`. `Overdue` is derived from verified due value plus open state; it is never hidden or automatically marked satisfied.
- Scheduled event lifecycle is `scheduled`, `occurred`, `adjourned`, `cancelled`, or `superseded`. Adjournment creates/links the replacement event and retains the original history.
- Satisfying, cancelling, superseding, reopening, correcting, or rejecting requires an actor and reason where consequence would otherwise be ambiguous. Material transitions append Activity atomically.
- Do not expose one overloaded deadline `state`. Presentation keeps four independent axes: kind (`Legal deadline`, `Scheduled event`, or projected `Task milestone`), verification, domain lifecycle, and derived temporal condition (`Upcoming`, `Due soon`, `Due today`, or `Missed`). Reminder readiness is a fifth derived operational fact, never another lifecycle value.
- `monitoring_state` is a secured projection, not an editable enum: `setup_required` when a future consequential date is provisional, unassigned, or lacks an eligible schedule; `active` only when the date is verified, open, assigned, and has current durable reminder instances; and `inactive` for closed/history records. UI language is `Setup required`, `Alerts active`, or an explicit outcome. It never claims that reminders guarantee compliance.

### Responsibility and reminders

- A verified deadline may have one accountable member and optional subscribers. Viewer cannot be assigned operational responsibility in the first release.
- Assignment is independent from notification read state. Removing a member unassigns active dates and surfaces urgent items to Admin/Owner without changing their legal lifecycle.
- Reminder preferences and delivery modes follow the Work/Notification plan. Supported offsets come from the validated preference catalogue; fixed columns such as `reminder_sent_7d` are removed.
- Durable reminder instances are keyed by deadline revision, recipient, channel, and offset. Correction/supersession cancels pending instances and schedules replacements; already delivered reminders remain audit history.
- The scheduler evaluates verified, active, accessible, non-trashed dates in organisation timezone, then applies recipient timezone and quiet-hour rules. It is resumable, idempotent, and safe across daily retries.
- Realtime is not enabled for the full Deadlines page initially. Mutations refresh their local projection; other sessions show ordinary freshness text and update on browser refresh. Today/notifications remain durable, not Broadcast-dependent.

### Controlled calculated deadlines

- AI never calculates statutory limitation. A later deterministic rule engine may propose a calculated deadline from a versioned, jurisdiction-specific rule definition and verified trigger fact such as communication date.
- A rule definition records authority, provision, applicability dates, units, counting convention, exclusion/holiday policy, required inputs, source citation, reviewer, and version.
- Every calculated result stores rule version, inputs, calculation trace, timezone/calendar version, and evidence. It remains provisional until human verification and is visibly labelled `Calculated`.
- No rule catalogue ships merely from prompt text or developer memory. Legal/content review and regression fixtures are required per rule/version.

### Deadline presentation

- Matter Deadlines starts immediately below the shared section strip with one compact toolbar and no hero heading.
- Matter Deadlines has one operational agenda only. It does not add a proportional runway, summary infographic, dashboard metrics, or Matter calendar; those treatments add density without improving the immediate decision.
- Every agenda record exposes its kind in a dedicated, text-labelled field: `Legal deadline`, `Scheduled event`, or `Task milestone`. Origin (`Extracted`, calculated, or manual) remains separate because provenance and operational kind answer different questions.
- The stable deadline workbar uses one highly compact segmented tab control beside Search, Filters, and Add date. It exposes `Attention`, `Monitoring`, `Milestones`, and `History` with short labels, equal circular counters, and an unmistakable selected treatment. Only the chosen group's records render; groups are never stacked vertically. `Needs attention` is selected by default whenever it contains records, otherwise `Monitoring` is selected. The same accessible tab set uses a four-column fit on phones and an intrinsic-width row on larger screens without horizontal page scrolling.
- Desktop uses Date, Obligation/Event, Kind, Origin, Owner, and Readiness/Outcome rather than one ambiguous State column. Within Needs attention, missed unresolved precedes incomplete setup; Monitoring and Milestones use nearest-due-first; History uses event date descending. A user-selected newest/oldest sort may be offered within a tab.
- Missed but unresolved deadlines remain danger-treated and actionable. Only satisfied, cancelled, superseded, rejected, or occurred history uses muted/disabled visual treatment; muting must not disable evidence access.
- Selecting a record opens a context pane with source evidence, independent state facts, type-specific lifecycle actions, reminders, and an ordered operational trail. The trail derives from immutable candidate/run, version/decision, assignment, reminder-instance, delivery, and outcome events; each checkpoint names actor/system, timestamp, source/revision, and current/pending state.
- Amend is append-only and type-specific: correct/amend legal deadline with reason, adjourn/amend scheduled event, or edit Task milestone in My Work. Primary actions depend on current condition, such as `Review extracted date`, `Record outcome`, `Mark satisfied`, or `Open in My Work`; impossible or stale transitions are not shown.
- Mobile uses prioritised agenda cards in one scroller; detail/actions open as a drawer or drill-down.
- Filters include responsibility, class/type, origin, verification, lifecycle, time window, client, and Matter. Search covers title, description, Matter/client, and source document identity.
- `Add date` offers explicit choices: `Legal/procedural date` and `Internal task milestone`. The latter routes to task creation; it does not masquerade as a legal deadline.
- Extracted/manual/calculated origin is always textual. Urgency uses neutral/warning/danger semantics plus words. Missed/overdue dates remain in the default agenda until satisfied, cancelled, or superseded.
- `/deadlines` is the organisation projection with `My agenda` default, authorised `Team agenda`, Agenda/Calendar views, and filters. Provisional verification belongs to Review, with a compact link/count rather than a duplicate decision queue.

### Financial statement model

- A `financial_statement` belongs to one Matter and normally one immutable document version. It records statement date, procedural stage, perspective, legal effect, source/evidence set, verification state, and optional tax period.
- Initial perspectives are `authority`, `taxpayer`, `court_or_tribunal`, and `system_import`; human corrections record their actor separately.
- Initial legal effects are `proposed`, `admitted`, `disputed`, `confirmed`, `reduced`, `dropped`, `stayed`, `paid`, `pre_deposited`, `refunded`, `adjusted`, and `informational`.
- A statement contains line items with `component` (`tax`, `interest`, `penalty`, `fee`, `other`, `total`), `tax_head` (`IGST`, `CGST`, `SGST_UTGST`, `CESS`, `aggregate`, `unknown`), exact signed integer paise, currency `INR`, source label, and evidence.
- Source-stated totals are stored as total line items and marked `source_stated`. Derived totals are separate projection values with formula/version and never overwrite the source total. Components and totals are never double-counted.
- Signed adjustments are preserved. Direction/legal effect explains whether a value increases, decreases, pays, refunds, or otherwise changes a position; UI never relies on a minus sign alone.
- One document may yield multiple statements, for example an authority-confirmed demand and a taxpayer-disputed position. Their perspectives remain separate.

### Extraction, verification, and effective financial projections

- Replace flat `extracted_amounts` with a versioned `financial_statements[]` extraction contract containing stage, perspective, legal effect, line items, period, and evidence per material line/group.
- The model must distinguish allegation/proposal, submission/admission/dispute, finding/order, payment, and relief. It must abstain when it cannot assign legal character.
- Provider output passes the shared Zod schema, deterministic normalization, arithmetic checks that never invent a missing total, tax-head/component validation, page-bound validation, and semantic candidate dedupe.
- Valid candidates display provisionally. Treating a statement as an operative Matter position, payment, relief, refund, or portfolio exposure is Tier C and requires verification under the AI plan.
- Human creation/correction uses the same statement/line model with human provenance and begins verified. Corrections append decisions/versions; they do not rewrite source candidates.
- New documents may supersede or modify earlier statements only through explicit verified relationships. An appeal filing does not silently erase a confirmed demand; a payment does not silently prove that liability was admitted.
- `matter_financial_position` is a secured projection of selected verified statements, not an editable source. It may expose separately labelled `latest confirmed demand`, `amount under challenge`, `verified payments/pre-deposits`, `verified relief`, and `verified refunds`.
- Do not expose a universal `current exposure` or `net payable` unless a verified source explicitly states it or a separately approved deterministic calculation can prove comparability and formula. When unavailable, say `Not determined` rather than subtracting incompatible values.

### Financial presentation

- Matter Financials starts with compact, qualified metrics such as Latest confirmed demand, Under challenge, Paid/pre-deposited, and Relief obtained. Each value states date/stage and opens its evidence chain.
- The primary visualization is a deterministic **legal amount evolution** across verified comparable statements. Document/event points link to source evidence; provisional candidates use a distinct review treatment and are excluded from solid verified lines.
- Payment/pre-deposit/refund markers are overlaid or listed separately; they are not plotted as though they were replacement demand totals.
- Below the visualization, a semantic table lists Date, Proceeding/source, Legal effect, Tax, Interest, Penalty, Other, and Source-stated total. Selecting a row opens statement lines, tax-head split, evidence, verification/history, and correction actions.
- The Financial workbar follows the common Matter-section anatomy and never duplicates actions: view tabs stay left; `Legal position` alone shows the verified-facts qualifier in the middle; Owner/Admin-only `Participants`, Filters, and the current primary action stay right, with `Add financial entry` or `Add cost` always rightmost. The cost body starts directly with a single slim `Total recorded` treatment and the ledger; entry count, receipt count, and a repeated internal-cost title/description/action header are omitted.
- Selecting any legal statement or cost entry opens the same stable inspector shell with type-specific content. Legal statements expose exact components, effect, evidence, verification/history, and permitted review/correction actions. Cost entries expose incurred date, category, payer/payee, receipt, creator/version history, and capability-gated receipt, edit, and remove actions.
- If statements are not comparable, replace the misleading chart with an ordered change ledger explaining what each document says. No chart is preferable to a false trend.
- Mobile replaces the wide chart/table with a vertical financial evolution and expandable statement cards. Exact values remain available; lakh/crore abbreviations may supplement but never replace exact INR.
- `/financials` is an authorised organisation projection for verified legal positions with client/Matter/stage/component/time filters. It is not an accounting balance sheet and never includes inaccessible Matters or provisional values in verified totals.
- Realtime is not enabled initially. Financial mutations use authoritative responses; other sessions use browser refresh/freshness treatment.

### Internal litigation costs

- Internal costs use separate `matter_cost_entries`; they never share legal statement totals or chart series.
- Initial categories are filing/court fee, travel, courier/printing, external counsel/consultant, research/data, and other. Entries record exact amount, incurred date, payer/payee text, description, optional receipt document locator, creator, and version history.
- Costs are optional and disabled by default during the pilot. Owner/Admin may enable them per organisation after acknowledging the privacy boundary.
- Owner/Admin has inherent view/edit/export access to every enabled internal-cost ledger and exclusively manages its participant list. A Matter-specific grant may add an active organisation member as `view` or `edit`; it never grants access to the rest of the Matter or to another Matter's costs.
- Effective cost access is the intersection of organisation role, current Matter access, and the Matter grant. Associate may receive `view` or `edit`. Viewer may receive `view` only; an attempted Viewer `edit` grant is rejected rather than silently elevated or coerced. No Matter grant can confer Owner/Admin-only access management, export, organisation settings, or destructive authority.
- Membership suspension/removal, loss of Matter access, or role downgrade takes effect immediately. The membership command revokes or reduces incompatible grants transactionally, while every read/mutation still recalculates effective capability so stale rows or clients cannot retain access.
- Members without effective cost access do not receive ledger rows, receipts, totals, participant identity/counts, exports, Search results, Activity details, realtime topics, or evidence locators. The `Internal costs` switch is absent for them rather than exposing an empty-but-revealing ledger.
- In the authorised Matter UI, `Participants` is visible only to Owner/Admin and opens a searchable organisation-member list with `None`, `View`, or `Edit` choices constrained by role. Editors may add/correct ordinary entries; viewers receive a read-only ledger; collaborators cannot change participants or export unless separately authorised by their global role.
- Cost export, reimbursement, invoicing, tax credit/accounting treatment, and client billing remain out of scope.

### Activity, Review, Search, Trash, and access

- Deadline and financial mutations emit approved Activity events and outbox records atomically. Reminder delivery attempts are operational/delivery history, not general Activity.
- Review types are deadline verification/conflict and financial verification/conflict. Each shows exact evidence and typed actions; neither supports unsafe bulk resolution.
- Search indexes verified and provisional labels with appropriate status and locators. Search never presents a provisional amount as verified current position.
- Viewer reads permitted legal deadlines/financials but cannot mutate; a Matter-specific cost grant may additionally reveal that Matter's internal-cost ledger in read-only form. Associate may create/verify/correct ordinary dates and legal statements, be assigned deadlines, and edit internal costs only when explicitly granted for that Matter. Owner/Admin controls team triage, organisation projections/settings, calculated-rule activation, cost participant grants, exports, and internal costs.
- Trashed Client/Matter/Document suspends reminders, organisation projections, search, AI processing, and all mutations while preserving read-only deadlines, statements, costs, evidence, and history. Restore revalidates sources and reminder schedules before reactivation.
- Permanent purge is blocked or dependency-ordered for surviving evidence links, Review, reminder, export, and cost-receipt references according to the Trash plan.

## Implementation Plan

1. **Introduce shared value/evidence contracts.** Reuse `DocumentSourceLocator`, integer-paise money, organisation timezone, Activity/outbox, Review, Tasks, and notification preference contracts.
2. **Expand Deadline schema.** Add organisation lineage, class/type/origin, precision/timezone, verification/lifecycle, responsibility, source candidate/locator, revisions, subscriptions, reminder instances, and semantic dedupe keys.
3. **Migrate deadlines.** Backfill legacy rows as document-explicit provisional or human/manual verified where provenance proves it. Preserve resolved state, derive organisation through Matter, mark missing evidence, and collapse only provable duplicates.
4. **Replace ingestion writes.** Materialize stable deadline candidates from normalized extraction; idempotently create/compare domain records; retain page/quote/region; create Review only for consequence/conflict.
5. **Build Deadline commands and reminders.** Implement create, verify, correct, reject, assign, satisfy, cancel, supersede/adjourn, subscribe, and idempotent scheduling/delivery.
6. **Build Matter and organisation Deadline projections/UI.** Add the compact Matter agenda/context pane, explicit date-kind presentation, mobile drill-down, organisation calendar/agenda, source opening, filters, deep links, and Task-milestone projection.
7. **Introduce Financial schema.** Add statements, line items, candidate/decision/version/evidence links, comparable-series metadata, position projection, and optional cost tables.
8. **Upgrade the extraction contract.** Add financial statements with perspective/effect/component/tax-head/evidence, evaluate prompt/schema changes, and dual-materialize while legacy `extracted_amounts` remains readable.
9. **Build Financial commands/projections.** Implement human create/correct/verify/reject/supersede, comparable evolution, selected current-position facts, evidence links, and idempotent re-extraction comparison.
10. **Build Matter and organisation Financial UI.** Add qualified facts, deterministic chart/change ledger, semantic table/cards, statement inspector, provenance/history, filters, and mobile evolution.
11. **Add optional costs.** Ship behind organisation setting after permission, privacy, receipt, export exclusion, and audit tests pass.
12. **Cut over and contract.** Shadow counts/amounts, verify migration per Matter, switch Today/My Work/Review/Case Brief/Search consumers, observe, then remove fixed reminder booleans, blind deadline insert, and flat amount consumers within a rollback-bounded migration.

## Interfaces and Data Changes

### Deadline tables

- `deadlines`: organisation/Matter lineage, class/type/origin, title/description, date/time precision and timezone fields, verification/lifecycle, assignee, current revision, semantic key, created/updated metadata.
- `deadline_versions`: immutable due value, source/rule/manual basis, actor/decision, revision reason, timestamps.
- `deadline_evidence`: deadline/version or candidate to typed document source locator and quotation/region.
- `deadline_candidate_bindings`: extraction candidate, document version, semantic key, materialization/decision state.
- `deadline_subscriptions`: deadline/member notification relationship and origin.
- `deadline_reminder_instances`: deadline revision, recipient, offset, channel, scheduled time, state, dedupe key, delivery relationship.
- Future `deadline_rule_definitions` and `deadline_calculation_runs` are introduced only with the controlled rule-engine phase.

### Financial tables

- `financial_statements`: organisation/Matter/document-version lineage, statement date/stage, perspective, legal effect, period, verification/current revision, semantic key, comparability group.
- `financial_statement_versions`: immutable statement metadata and change reason/actor/run.
- `financial_line_items`: statement/version, component, tax head, exact signed paise, currency, direction/source-total qualification, semantic key.
- `financial_evidence`: statement/line/candidate to source locator and quotation/region.
- `financial_candidate_bindings` and `financial_decisions`: normalized extraction candidates and append-only human accept/correct/reject/supersede decisions.
- `matter_financial_position`: maintained secured projection of separately qualified verified facts and source revisions.
- `matter_cost_entries`, `matter_cost_entry_versions`, and receipt locators: separate optional internal-cost ledger.
- `matter_cost_access_grants`: organisation/Matter/member lineage, `view|edit` level, grant/revoke actor and timestamp, active/revoked state, and reason; unique active grant per Matter/member. Owner/Admin access is derived and is not duplicated as a grant row.

Every tenant row carries `org_id`; composite constraints or trusted functions enforce organisation consistency with Matter, Document version, member, Review, and Task. New monetary values use integer paise. Legacy numeric rupee values convert exactly with migration validation.

### Commands and events

- Deadline commands: `createLegalDeadline`, `verifyDeadline`, `correctDeadline`, `rejectDeadlineCandidate`, `assignDeadline`, `satisfyDeadline`, `cancelDeadline`, `supersedeDeadline`, `adjournScheduledEvent`, `subscribeToDeadline`.
- Financial commands: `createFinancialStatement`, `verifyFinancialStatement`, `correctFinancialStatement`, `rejectFinancialCandidate`, `supersedeFinancialStatement`, `createMatterCost`, `correctMatterCost`, `removeMatterCost`, `grantMatterCostAccess`, and `revokeMatterCostAccess`.
- Activity/outbox events include `deadline.created|verified|corrected|assigned|satisfied|cancelled|superseded`, `scheduled_event.adjourned`, `financial.statement_created|verified|corrected|superseded`, and permissioned cost/access events. Cost event payloads are delivered only to actors who remain authorised to see that Matter's ledger.
- Typed errors cover inaccessible source/Matter/member, invalid date/timezone, stale revision, invalid transition, unresolved/provisional consequence, duplicate semantic candidate, incompatible financial comparison, unknown component/tax head, arithmetic mismatch, and Trash/read-only state.

## Testing and Acceptance Criteria

### Automated coverage

- RLS and command tests prevent cross-organisation access and enforce Viewer/Associate/Admin/Owner and internal-cost boundaries, including Viewer-edit denial, ungranted Associate denial, grant revocation, role downgrade, member suspension/removal, forged Matter/member IDs, receipt access, export exclusion, Search/Activity redaction, and direct RPC attempts.
- Deadline tests cover date-only/timezone semantics, leap days, overdue derivation, explicit versus relative dates, candidate dedupe, retry/re-extraction, version correction, conflict, assignment/removal, lifecycle transitions, adjournment, Trash suspension/restore, and stale optimistic writes.
- Reminder tests cover offsets, organisation/user timezone, quiet hours, correction cancellation/reschedule, exact-once delivery, retries, overdue policy, revoked access, member removal, Trash, and resolved/superseded races.
- Financial schema tests cover perspective/effect, component/tax-head catalogue, signed adjustment, paise conversion, source-stated versus derived totals, duplicate candidate, multiple statements per document, version correction, replacement source, and incompatible comparability.
- Projection tests prove that appeal does not erase confirmed demand, payment does not imply admission, components/totals are not double-counted, provisional values stay out of verified totals, and undetermined current exposure is not fabricated.
- Prompt/evaluation fixtures include DRC notices/orders/payments/rectifications/appeals with multiple figures, tax heads, partial payment, relief, negative adjustment, poor scans, and conflicting positions. Critical date/amount/evidence regressions block promotion.
- UI/accessibility tests cover table/card semantics, exact INR, origin/verification text, keyboard/date actions, evidence opening, no-chart fallback, long content, empty/loading/error/read-only, 320px mobile, 200% zoom, and reduced motion.
- Migration tests reconcile row/amount counts per organisation/Matter, preserve legacy resolution, report unresolved evidence, collapse only exact duplicates, and support pre-contract rollback.

### Manual acceptance

- Agenda never collapses kind, verification, lifecycle, temporal condition, and reminder readiness into one State value. A user can explain why an item is in `Needs attention`, `Monitoring`, `Milestones`, or `History` without relying on colour.
- Switching the compact deadline tabs replaces the current list rather than stacking another section. Needs attention defaults open when non-empty; short labels, circular counts, selected state, keyboard navigation, and mobile touch targets remain clear without horizontal page overflow.
- Default ordering keeps missed unresolved ahead of setup work, monitored dates and milestones nearest first, and History newest first. Missed unresolved remains visually urgent, while closed history is muted but inspectable.
- Matter Deadlines contains no summary infographic or calendar. Organisation `/deadlines` retains Agenda/Calendar views for portfolio-scale date density.
- The selected-item operational trail reproduces extraction, verification/correction, assignment, reminder activation/delivery, and outcome checkpoints from durable records with actor/system, timestamp, and source/revision metadata. Pending checkpoints are visibly distinct from completed ones.
- An extracted hearing date appears provisional with page evidence. Verifying it schedules eligible reminders exactly once; correcting it cancels stale pending reminders and preserves history.
- A missed reply deadline remains at the top of Matter and organisation agendas until explicitly satisfied/cancelled/superseded.
- `Add date` clearly separates legal/procedural date from internal task milestone.
- Desktop keeps Matter identity, section strip, toolbar, and selected-row context stable while the agenda body scrolls. Mobile has one principal scroller and no covered last row.
- An SCN proposal, OIO confirmation, payment/pre-deposit, and appeal display as distinct financial statements. The chart links each comparable verified point to evidence and does not treat appeal filing as automatic reduction.
- When only incompatible or provisional figures exist, Financials shows a change ledger/review state instead of a confident trend or total.
- Exact tax-head/component lines and source-stated totals remain inspectable on desktop and mobile.
- Internal costs, when enabled, are visually and permission-wise separate and never alter legal financial metrics.
- Owner/Admin can search active Matter-accessible organisation members and grant/revoke Matter-specific cost visibility or editing. An Associate grant affects only that Matter; a Viewer can be granted view but never edit; revocation or role downgrade removes effective access immediately without requiring sign-out.
- Organisation pages exclude inaccessible/trashed Matters and provisional amounts from verified aggregates. Case Brief links here instead of reproducing the progression chart.

Completion requires typecheck, lint for touched files, domain/unit/integration/RLS/migration tests, prompt evaluation gates, desktop/mobile/dark browser verification, keyboard/screen-reader review, and scheduler/projection observability.

## Assumptions

- Initial currency is INR, but storage keeps an ISO currency column for explicitness.
- Organisation timezone and notification preference contracts ship from the Organisation and Work plans before reminder cut-over.
- Document Workbench provides immutable versions, OCR/page regions, and typed source locators.
- Matter access remains organisation-based until a separate Matter-access plan narrows it; all projections use current authorized Matter scope.
- Internal costs are disabled by default and do not block the legal Financials release.

## Open Questions

None.
