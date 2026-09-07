---
title: Platform Operations
status: approved
created: 2026-08-27
updated: 2026-09-08
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ./2026-08-26-organisation-administration.md
  - ./2026-08-24-document-record-and-file-lifecycle.md
  - ./2026-08-24-ai-extraction-and-model-lifecycle.md
  - ../features/2026-08-25-work-review-activity-notifications.md
  - ./2026-08-25-realtime-delivery-freshness-and-unread-state.md
  - ./2026-08-24-resource-trash-retention-and-purge.md
---

# Platform Operations

## Reading guide

Use the [shared reading rules](../../README.md#reading-a-large-plan). Read the scope/security links first, then relevant operations and their interfaces/acceptance. Expand dependencies when needed; recorded checkpoints require current-code reconciliation.

- **Read first:** [Usage cutover](#development-usage-and-release-cutover) · [Trust domain](#separate-platform-trust-domain) · [Privacy](#privacy-and-support-boundary).
- **Authority and controls:** [Capabilities](#initial-role-route-and-command-capability-contract) · [Surfaces](#platform-surfaces-and-interaction-contract) · [Organisation controls](#organisation-controls-and-safety-modes).
- **Operations:** [Usage and prices](#usage-cost-and-model-configuration) · [Quotas](#storage-and-quota-enforcement) · [Jobs and alerts](#jobs-health-audit-alerts-and-observability) · [Recovery gates](#backup-recovery-and-rollout-gate).
- **Checks and contracts:** [Interfaces](#interfaces-and-data-changes) · [Acceptance](#testing-and-acceptance-criteria) · [Assumptions](#assumptions) · [Open questions](#open-questions).

## Summary

Establish a separate, privacy-preserving Platform Operations trust domain for CaseChain. It provides controlled operator identity, MFA-protected operational actions, safe organisation and job projections, immutable provider-cost accounting, lightweight tenant resource metering, versioned configuration and quotas, audit/alerting, and a staged backup/recovery gate.

This is not a tenant-administration extension and does not grant legal-content access. It corrects the current global `/usage` and service-role shortcuts before rollout beyond the controlled pilot. Platform Operations must ship, meet its acceptance gates, and pass a restore drill before that rollout.

## Context and Goals

The original audit below describes legacy behavior. The user confirmed on 2026-09-07 that cross-testing-member Usage aggregation is intentional development tooling. Treat its missing environment/operator enforcement as a release-cutover gap, not an invalid development requirement; current delivery is tracked in [D03/D13](../../delivery-ledger.md).

Current operational controls cross tenant boundaries unsafely: `/usage` sits in authenticated tenant navigation, queries all organisations with a service-role client, and is capped to 1,000 rows in client-side handling. Tenant Admins can globally overwrite `model_pricing`, authenticated tenant members can insert usage rows, pricing is overwritten instead of versioned, and costs are floating USD. Existing comments/seeds confuse characters with tokens.

Worker recovery infers work from document status and an hourly scan rather than durable domain run state. Service-role access is a broad server helper rather than a narrowly trusted boundary. Worker logs contain IDs/storage paths and raw provider errors. There is also no repository-owned backup/restore contract or platform-operator identity.

The goals are to make these functions safe, auditable, and operationally useful while preserving tenant isolation and legal evidence boundaries. The console serves health, bounded remediation, configuration, and accountability; it is never a browser for tenant content, a general database console, or a billing product.

## Decisions

### Development usage and release cutover

- Preserve cross-test-organization metering in the isolated development environment. A comment or hidden navigation entry does not enforce that environment: legacy Usage reads and global pricing writes must be denied outside the authorized development/operator boundary before confidential-data release.
- Tenant administration does not confer platform pricing authority. Test direct route and action calls, including the ordinary tenant Admin. The new private platform tables do not automatically protect old service-role entry points.
- Disabling/restricting legacy routes is sufficient for this release boundary; it does not require shipping the full platform console early. The separate operator console, privacy rules and expansion/recovery gates remain as specified below.
- Usage cost and generated-type verification must survive the documented generation/refinement command; CI cannot commit regenerated types without checking the consumers. Use D01 for the shared runtime/CI repair rather than another feature-local workaround.

### Separate platform trust domain

- Add a `/platform` route tree with its own layout, navigation, and context. It is not inside the tenant `(app)` shell and has no dependency on tenant Owner/Admin membership, a hidden route, or an email/password convention.
- A Supabase Auth identity may belong to both trust domains, but platform authority is derived only from an active `platform_operators` record. Initial roles are `platform_owner`, `platform_operator`, and `platform_auditor`; capabilities are server-authoritative and fail closed.
- Platform Owner manages operators and high-impact runtime/pricing configuration. Platform Operator performs bounded operational actions. Platform Auditor is read-only. No command may suspend or delete the last active Owner.
- Bootstrap the first Owner only through a controlled one-time deploy/runbook against a verified auth UID while no Owner exists. It records an audit event; it is neither a browser bootstrap nor a committed identity.
- The account menu shows a Platform launcher only to an active operator. Direct unauthorised requests are non-disclosing. Tenant auth and tenant roles never satisfy platform authorisation.
- All console access requires an active platform operator and provider-backed MFA/AAL2. Consequential mutations additionally require a fresh, server-verifiable privileged intent, valid for at most 10 minutes and bound to the operator and command family.
- Privileged intent is required for operator lifecycle; runtime/pricing changes; quota/guard overrides; feature safety controls; and incident recovery controls. Use authenticated RLS and capability-checked RPCs. Service role is limited to trusted workers, backfills, and controlled runbooks—never a browser or ordinary platform mutation shortcut.

### Initial role, route, and command capability contract

- Every `/platform` route requires its named read capability, and every command requires its named mutation capability independently. Possessing a route/read capability never implies a command capability. The server derives actor, role, and capabilities; it rejects unknown capability keys and never accepts them from the browser.
- Active Owner, Operator, and Auditor each have `platform.overview.read`, `platform.organisations.read`, `platform.usage.read`, `platform.jobs.read`, `platform.storage.read`, `platform.models.read`, and `platform.audit.read`. These authorize `/platform/overview` (including alerts/health), `/platform/organisations`, `/platform/usage`, `/platform/jobs`, `/platform/storage`, `/platform/models`, and `/platform/audit` respectively. All three roles may read safe backup status/evidence through `platform.overview.read`.
- Only Owner has `platform.operators.read`, which authorizes `/platform/operators` and operator-roster reads. Auditor has no mutation capability, including alert actions.

| Mutation capability | Owner | Operator | Auditor | Additional requirements |
| --- | --- | --- | --- | --- |
| `platform.alerts.manage` (acknowledge/resolve) | Yes | Yes | No | AAL2, reason, expected revision, audit; no fresh privileged intent |
| `platform.jobs.retry` | Yes | Yes | No | AAL2, 10-minute privileged intent, typed retry contract |
| `platform.organisations.safety_mode.manage` | Yes | Yes | No | AAL2, 10-minute privileged intent, bounded audited safety mode |
| `platform.organisations.entitlement.manage` (within configured bounds) | Yes | Yes | No | AAL2, 10-minute privileged intent, reason/revision/audit |
| `platform.policy.storage_quota.manage` | Yes | No | No | AAL2, 10-minute privileged intent |
| `platform.models.runtime_pricing.manage` | Yes | No | No | AAL2, 10-minute privileged intent |
| `platform.features.kill_switch.manage` | Yes | No | No | AAL2, 10-minute privileged intent |
| `platform.operators.manage` (invite/activate/change role/suspend) | Yes | No | No | AAL2, 10-minute privileged intent, last-Owner invariant |

- Backup/recovery execution is not a browser capability. It is a controlled runbook requiring Owner 10-minute privileged intent plus the second-authorized-approver rule where available, or the documented single-Owner pilot exception that must close before broader rollout.

### Privacy and support boundary

- Console projections and audit/log payloads use one explicit allowlist: opaque organisation/resource/run IDs; organisation display name; plan/entitlement; safe status/failure code; byte/token/unit counts; timestamps; model/config versions; and explicitly configured operational contact data.
- Never render or log PDFs, filenames, matter/client names, document references, notes, extracted text, prompts, raw provider output/errors, embeddings, signed URLs, message bodies, user email lists, storage paths, or secrets.
- There is no impersonation, `view as user`, arbitrary SQL, content search, backup browser, or break-glass tenant-content UI. Future tenant-approved, time-limited support grants require a separate approved plan.

### Platform surfaces and interaction contract

- `/platform/overview` is action-first: health, active alerts, provider/model state, and the recovery evidence applicable to the current rollout stage; it is not a vanity dashboard.
- `/platform/organisations` provides a safe organisation inspector for entitlements, aggregate usage, feature/safety mode, configured operational contact, and safe failures.
- `/platform/usage` shows aggregate internal provider units/cost and quality flags. It replaces the global tenant Usage route only after it is ready.
- `/platform/jobs` presents an allowlisted common operational-run projection and bounded retry. `/platform/storage` manages platform guard state and organisation entitlements. `/platform/models` owns versioned model/runtime/pricing configuration. `/platform/operators` is Owner-only. `/platform/audit` is searchable safe audit.
- Use the CaseChain design-system contract: compact stable headers and primary actions outside the scrolling body; server pagination/filtering; independent list/detail presentation on desktop and mobile; explicit scroll ownership; 44x44 touch targets; and keyboard, screen-reader, loading, empty, error, and long-content states.
- Consequential actions use descriptive labels plus a reason, impact preview, confirmation, revision check, and safe result. They never rely on an icon alone.

### Organisation controls and safety modes

- Operators do not perform routine organisation deletion/purge and cannot access legal content. Full closure/purge remains under the tenant lifecycle/retention contracts or a separately approved incident runbook.
- Operators may apply bounded, auditable safety modes: `normal`, `new_ingestion_paused`, `ai_paused`, and `read_only_safety_hold`. They do not bypass legal holds or retention, silently change legal facts, or revoke existing tenant reads merely because a resource ceiling is reached.
- Versioned platform policy plus per-organisation entitlements/overrides record reason, expiry, actor, and revision. Policy changes cannot free space by purging or bypass holds/retention.

### Usage, cost, and model configuration

- Replace `ai_usage_logs` as the authoritative ledger with append-only `provider_usage_events` and line items supporting tokens, cached tokens, image/page/character, and other provider billable units. Only trusted workers insert them.
- Each event records organisation, operation/run, provider/model, model-config version, pricing version, provider-reported quantities, occurrence time, safe correlation/idempotency, and an integer micro-USD cost snapshot. Document IDs/references do not enter platform projections.
- Rates are immutable effective-dated USD versions. A price change never rewrites history. A missing or ambiguous rate yields `unpriced`, creates an alert, and never silently records zero. Character count is never substituted for tokens.
- Daily server-side rollups power the UI; raw events are restricted. Migrate legacy usage as `legacy_unverified`, retaining its historical cost snapshot without claiming reconciliation. Backfill price versions from legacy rows as `legacy_seed_pending_verification`.
- Provider cost is internal accounting, not customer billing; provider rates/configuration are not tenant-readable. Customer billing and automatic provider-invoice reconciliation are out of scope.
- Keep three measurement layers distinct:
  1. provider-reported account/project totals and invoices are authoritative for total Supabase, Vercel, Trigger, and AI-provider cost;
  2. CaseChain records only organisation-attributable resource facts that it can measure or label honestly, such as unique retained asset bytes, object-access grants, exports, processing pages, and provider units;
  3. privacy-preserving product analytics measures feature outcomes and performance but is neither the provider-cost ledger nor a customer invoice ledger.
- Store provider account/project usage as daily or monthly reconciliation snapshots without inventing an organisation split. Store organisation usage as append-only material events plus daily aggregates with an explicit quality of `measured`, `estimated`, or `provider_reported`. Never claim exact tenant attribution where provider totals include shared Auth, API, Realtime, cache, retry, transfer, or infrastructure overhead.
- The design-partner release does not itemise egress, memory, CPU, token, or per-request charges to the client. PDF access-grant issuance may record expected object bytes for learning and anomaly detection, but it is not proof that a complete download occurred. Storage overage and AI/egress pricing remain future commercial decisions based on reconciled evidence.
- Do not copy raw provider telemetry or every HTTP request into the transactional database. Per-request memory/CPU samples, logs, and time-series health belong in provider/observability systems. Database telemetry retains only durable run outcomes, material usage events, and bounded daily aggregates without document names, content, queries, prompts, URLs, paths, or user-agent/IP payloads.
- Retain non-billing raw organisation resource events for 90 days by default and retain daily/monthly aggregates for trend analysis. The immutable provider-cost ledger and legal/security audit retain their separately approved longer periods; a future customer-billing ledger requires its own retention, dispute, correction, and invoice contract.
- Model catalogue, runtime configuration, and provider pricing are validated, versioned, effective-dated, atomic, previewed, reasoned, audited, and revision-checked. High-impact changes are Owner-only. Kill switches may pause optional AI families while preserving manual legal workflows. Tenant Admins cannot read or mutate this configuration.

### Storage and quota enforcement

- Preserve the 25 MiB PDF default and allow up to 50 MiB only by justified platform approval. The single design-partner organisation receives a reviewable 350 MiB unique-asset entitlement for the known corpus. Supabase Pro replaces the former Free-plan 750 MiB platform guard; a configurable platform guard must instead preserve measured headroom below the deployed provider capacity and may not be inferred from a stale plan constant.
- Warn organisations at 80% and 95%; reject/reservation-fail at 100%. Alert the platform at 70%, 85%, and 95%; fail closed for new reservations at the platform ceiling while existing reads continue.
- Enforcement is configuration-backed, transactional server-side reservation/finalisation, not UI constants. AI budgets are alert/safety controls initially and never silently block core legal work from mutable client calculations.
- Customer-facing storage analysis uses average active unique asset bytes over time. Historical-version, Trash, Intake, extracted-text, and derived-index bytes remain separately visible so future commercial policy can decide what is billable without rewriting lifecycle facts. Exact within-organisation duplicates count once; cross-organisation deduplication and billing inference are forbidden.

### Jobs, health, audit, alerts, and observability

- Do not create a second job source of truth. Owning domain durable outbox/run records remain canonical. Expose only an allowlisted common projection with organisation, kind, safe resource/run IDs, state/stage, attempts, retryable safe code, scheduled/started/heartbeat/completed times, latency, successor, idempotency, and correlation.
- Per-kind SLA rules detect stuck work and create durable alerts. `operational_sla_profiles` is versioned; every registered domain run kind must map to exactly one active profile and may carry a versioned explicit override. An unmapped or unregistered kind raises a critical configuration alert and is not manually retryable. Actual run kinds must be explicitly bound during implementation—the categories below do not permit inference from a run name.
- Database UTC time is authoritative. Thresholds fire at `>=`. Heartbeat age applies only to claimed/running work; scheduled lateness is measured from due time. Alerts are warning at the warning threshold and critical at the critical threshold, deduplicated per logical run, rule, and SLA-profile version.

| SLA profile / covered category | Queue or start lateness | Heartbeat stale | Running elapsed | Additional rule |
| --- | --- | --- | --- | --- |
| `interactive_processing` — upload/intake/extraction, user-requested reprocess | warning 2m; critical 10m | warning 2m; critical 5m | warning 10m; critical 20m | — |
| `background_projection` — wiki/index/realtime projection/digest | queue warning 15m; critical 60m | warning 5m; critical 15m | warning 30m; critical 120m | — |
| `scheduled_maintenance` — reminders, reconciliation, reservation cleanup | start-late warning 15m; critical 60m | warning 5m; critical 15m | warning 30m; critical 120m | — |
| `destructive_lifecycle` — purge/retention cleanup | queue warning 15m; critical 60m | warning 5m; critical 15m | warning 60m; critical 360m | never automatic retry |
| `backup` — independent backup/object-copy verification after its rollout gate activates | start-late warning 15m; critical 60m | warning 10m; critical 30m | warning 120m; critical 480m | successful verified-backup freshness warning at 20h; critical at 24h; never automatic retry |

- A manual retry delegates to the owning typed command only for retryable terminal state, current active source, and no live successor. It requires idempotency, actor reason, revision check, and `platform.jobs.retry`; it creates a new attempt/successor and never edits history. Do not expose arbitrary payload editing, raw Trigger replay, or cancellation unless the owning domain already proves it safe.
- Systemic failures alert platform staff. Tenant-actionable failures enter the approved Review/notification flow with minimal context.
- Add `platform_operators`, append-only `platform_audit_events`, durable `platform_alerts` (`open`, `acknowledged`, `resolved`), versioned policy/config/pricing records, `organisation_entitlements`, provider usage event/line-item tables and rollups, and secured organisation/run views/RPCs.
- Audit captures actor, capability, target type/opaque ID, action, reason, allowlisted before/after delta, correlation/idempotency, outcome, and time. App roles cannot update/delete audit; corrections append. Retain platform audit and the cost ledger at least seven years, detailed runs/alerts at least 400 days, and aggregates for trend continuity. Where a finalized plan has a stronger legal/audit rule, preserve that stronger rule.
- Structured event names and safe codes only. Normalize provider errors at the boundary. Metrics/alerts cover queue age, failures/retries, latency, unpriced usage, provider/model health, reservation leakage, storage guards, the managed-backup status applicable to the design-partner release, and independent backup freshness/restore drills after that gate activates. Critical alerts also notify configured operational contacts out of band without content.

### Backup, recovery, and rollout gate

- The single-organisation design-partner production release may start without a CaseChain-managed independent database/object backup. It runs on Supabase Pro, verifies that the currently included last seven managed daily database restore points are active, and records the provider recovery boundary in the release runbook. Supabase database backups do not protect private Storage object bytes, and the release must not describe this arrangement as vendor-independent disaster recovery.
- The design partner retains recoverable original PDFs under the written pilot terms. Server-verified SHA-256 asset identity supports a later authorised source-rehydration workflow when database metadata survives but an object is missing. Rehydration is not an initial automatic recovery promise and cannot reconstruct lost metadata without a surviving database backup.
- Independent daily encrypted logical database backups plus an encrypted independent-destination copy of every retained private object byte become mandatory before a second production organisation is onboarded, before accepting a client that will not retain recoverable originals, or before making a stronger contractual/regulatory recovery promise—whichever occurs first. Each later backup set includes a manifest with object identity/version, size, and cryptographic hash; copies and keys live outside the primary failure domain and exclude application, Auth, and provider secrets.
- After the independent-backup gate activates, retain 30 daily and 12 monthly complete backup sets unless a stronger legal retention rule applies. Initial objectives are RPO ≤24 hours and RTO ≤8 hours.
- Run an isolated non-production restore drill before crossing that gate and at least quarterly afterward. Restore object bytes from the independent copy and verify hashes, tenant isolation, complete version coverage, RLS/capabilities, and critical projections. Store only safe drill evidence/freshness metadata and raise alerts for failures or overdue drills.
- Restore has no browser button. It follows a controlled runbook requiring Owner privileged intent and a second authorised approver where available; a single-owner pilot exception must be documented and closed before broader rollout. It never exposes backup contents in the console.
- Rollout beyond the single design-partner organisation is blocked until the independent destination/key authority exists, a successful restore drill is recorded, and no critical backup alert is overdue.

## Implementation Plan

### Completed prerequisite: platform operator identity and capability foundation (2026-09-01)

- Migration `00100` adds a private, append-only platform-operator history, safe bootstrap audit, exact fail-closed role/capability matrix, non-disclosing authenticated context, and a database-owner-only one-time bootstrap runbook contract. Tenant membership never grants platform authority; API roles cannot execute bootstrap or directly access the private tables.
- The first Owner is deliberately not created by this repository: a controlled deployment session must verify an Auth UID out of band and call the one-time bootstrap contract with a safe reason and idempotency key. No `/platform` route, console, usage, alert, AAL2, or privileged-intent consumer has migrated.
- Fresh local reset, rollback fixture, capability/tenant/append-only/last-owner/grant checks, generated-type parity review, TypeScript, migration checks, driver inspection, and fresh independent QA/recheck passed. The checked-in RPC result types deliberately model SQL `NULL` denial results because the local generator cannot express nullable `RETURNS TABLE` fields.

### Completed prerequisite: private privileged-intent foundation (2026-09-01)

- Migration `00101` adds private, append-only single-use intents and consumption receipts for the approved consequential command families. The database derives AAL2 from the verified Auth JWT, binds each intent to its active operator, capability, command family, nonce, and ten-minute expiry, and atomically prevents replay on consumption. Backup/recovery remains Owner-only.
- Intent tables and RPCs are force-RLS private and revoked from browser and service roles. Opaque audit events retain only the command family; no nonce, identity, secret, or command content is persisted. Generated database types include the final tables, enum, RPC signatures, and polymorphic audit relationship state.
- Fresh local reset, rollback fixture, AAL/actor/nonce/family/expiry/replay/append-only/privilege checks, TypeScript, migration checks, driver inspection, and fresh independent QA/recheck passed. This is a prerequisite contract only: no `/platform` route, account launcher, browser grant, or live privileged-command consumer has migrated.

### Completed prerequisite: private durable-alert foundation (2026-09-01)

- Migration `00102` adds private alert identity, immutable occurrence/event history, safe operational metadata, logical dedupe, occurrence replay fencing, and revision-fenced trusted-worker upserts. Alerts are explicitly limited to opaque platform, organisation, and operational-run subjects; their metadata and audit entries exclude legal content, paths, provider payloads, secrets, and contact data.
- The sole exposed surface is a service-only ingestion RPC. Acknowledgement and resolution deliberately remain unavailable until the later AAL2/capability-derived platform command boundary can attribute the acting operator. No alert producer, notification, console, or browser consumer has migrated.
- Fresh local rollback fixture, direct privilege/append-only/idempotency/revision/privacy checks, generated-type parity (including nullable failure results), TypeScript, migration checks, driver inspection, and fresh independent QA/recheck passed.

### Completed prerequisite: private model/runtime/pricing foundation (2026-09-01)

- Migration `00103` adds force-RLS immutable model-catalogue, runtime-config, pricing-version, and pricing-rate histories. Explicit provider-unit contracts use integer micro-USD rate items; effective windows are half-open and overlap-fenced. The resolver returns `unpriced` rather than a zero or partial rate when a version is missing, pending verification, ambiguous, or incomplete.
- The service-only legacy seed copies old `model_pricing` rows as `legacy_seed_pending_verification`, never claims their correctness, preserves character-priced embeddings as character rates, is replay/concurrency fenced, and fails closed on collision with a verified catalogue. Legacy pricing, usage writers, routes, and UI remain unchanged.
- Fresh local reset, rollback fixture, effective-window/rate-contract/replay/collision/privacy/privilege checks, generated-type parity, TypeScript, migration checks, driver inspection, and fresh independent QA/recheck passed. This is a prerequisite contract only: no browser grant, provider billing, `/platform/models`, or secured usage consumer has migrated.

### Completed prerequisite: private provider-usage ledger foundation (2026-09-01)

- Migration `00104` adds private append-only provider-usage events and line items with opaque organisation/subject correlation, exact provider units, immutable catalogue/runtime/pricing snapshot references, and integer micro-USD cost snapshots. A trusted worker can record a priced event only against one finalised, exact pricing-rate contract; missing, pending, ambiguous, incomplete, or mismatched pricing records an unpriced event and safe alert rather than a zero cost.
- Pricing rate collections now finalise as immutable snapshots before use: later rate additions are rejected, and provider-unit contracts reject extra or crossed units. The ledger is idempotency/fingerprint fenced and private; direct table access is denied to application roles. Legacy `ai_usage_logs`, pricing actions, workers, routes, and UI remain unchanged.
- Fresh local reset, both pricing/ledger rollback fixtures, contract/finalisation/replay/cross-subject/privacy/privilege checks, generated-type parity, TypeScript, migration checks, driver inspection, and fresh independent QA/recheck passed. This is a prerequisite contract only, not a live usage-writer, reader, rollup, or console migration.

### Completed: live document-extraction provider-usage writer (2026-09-01)

- Migration `00106` adds one service-only accounting command for a completed
  provenance-bound `source_analysis_run`. It accepts only that opaque run ID,
  then derives organisation, provider/model, exact input/output token units,
  occurrence time, runtime configuration, and deterministic correlation and
  idempotency identifiers from the durable run and its matching succeeded
  attempt. The append-only `00104` ledger remains the sole cost/pricing
  authority; missing units/configuration become safe unpriced observability,
  never a zero-cost entry or a legal-domain failure.
- The live `processDocument` worker reconciles that command after every
  accepted terminal provenance result, including `already_validated` and
  review-terminal replays after an accounting interruption. It never reruns
  Vertex, changes the accepted provenance state, or repeats review placement
  solely for accounting. Legacy embedding-reindex and Case Wiki
  `ai_usage_logs` writers remain deliberately unchanged because they lack this
  approved durable ledger subject.
- Focused replay/order tests, TypeScript, targeted lint, migration uniqueness,
  typed nullable-RPC assertions, diff checks, local ledger fixtures and fresh
  independent QA/recheck passed. The fresh recheck could not rerun Docker SQL
  fixtures because local Docker access was unavailable; it verified the
  service-only grant, server-derived identity, terminal replay fence, pricing,
  and privacy contracts from the current migration and tests.

### Completed: private provider-usage daily rollup consumer (2026-09-01)

- Migration `00107` adds private, force-RLS UTC daily provider-usage rollups
  and billable-unit rollups. A deferred `provider_usage_events` insert trigger
  is the sole writer: it runs after immutable line items exist, atomically
  aggregates exact quantities and integer micro-USD snapshots by opaque
  organisation/provider/model/operation/quality/day grain, and leaves unknown
  cost as `NULL`, never zero. The projection stores no document, user, path,
  content, or provider-payload dimension.
- The live caller is the existing service-only document-extraction accounting
  command from `processDocument`; accepted ledger replays do not insert a new
  event and therefore make no second rollup contribution. Per-grain advisory
  locking and overflow fences make concurrent updates fail closed rather than
  lose or corrupt accounting. Tables and trigger functions deny direct
  application and service-role access; no browser reader or new RPC grant was
  introduced.
- Disposable local reset, focused SQL and two-session concurrency fixtures,
  focused static tests, TypeScript, targeted lint, generated-type assertions,
  migration uniqueness, diff checks, and fresh independent adversarial QA
  passed. The QA reviewer could not independently reach Docker, but verified
  the privacy, privilege, trigger, replay, UTC, quality, and generated-type
  contracts read-only; the owner-run database fixtures passed.

### Deferred release prerequisite: Trigger.dev Node runtime alignment (2026-09-02)

- This is not the current portfolio tranche and does not interrupt approved
  product implementation. It becomes mandatory before the next pre-production
  Trigger worker rehearsal and before any production Trigger deployment.
- The repository currently uses Trigger.dev SDK `4.5.12`, omits an explicit
  cloud runtime, and retains several deprecated `@trigger.dev/sdk/v3` import
  paths. The developer machine's Node version does not select the deployed
  Trigger runtime.
- Pin `runtime: "node-24"` in `trigger.config.ts`; migrate compatible imports
  to `@trigger.dev/sdk`; align the repository Node engine/version file and
  Node types; and keep Node 26/Bun adoption out of this release unless separate
  compatibility evidence justifies it.
- Run TypeScript, focused task/outbox/schedule tests, the production build, and
  Trigger local-development smoke runs. Then deploy without promotion to a
  preview/pre-production worker, verify document processing, OCR/metadata,
  outbox draining, scheduled recovery, Wiki, retries, leases, and native/PDF
  dependencies, and promote only the exact verified worker version.
- Existing in-flight runs remain version-locked. Rollback restores the prior
  current worker version; a runtime upgrade never replays completed provider
  work or bypasses the owning domain's idempotency and lease fences.

1. Establish the approved Organisation Administration identity/RBAC foundation, then the Document Record and File Lifecycle foundation. Preserve owning-domain durable outbox/run records and safe state before adding the platform projections.
2. Add platform trust/config/accounting/audit/alert schema, enum/check constraints, append-only permissions, RLS, capability RPCs, safe projections, revision/idempotency support, and explicit retention jobs. Bootstrap the first Owner with the controlled runbook and audit it.
3. Build platform authentication/authorisation: isolated route/layout, active-operator lookup, AAL2 enforcement, 10-minute privileged intent, non-disclosing denial, account launcher, Owner lifecycle invariant, and service-role boundary narrowing.
4. Introduce versioned model/runtime/pricing catalogues and policy/organisation-entitlement records. Backfill immutable legacy price versions as `legacy_seed_pending_verification`; remove tenant global-price access/mutations only after secured replacements are proven.
5. Introduce the append-only usage ledger and line items. Dual-write trusted worker usage, reconcile exact quantities/cost snapshots and idempotency, backfill legacy rows as `legacy_unverified`, build daily rollups/unpriced alerts, then cut usage reads to secured platform projections.
6. Move quota enforcement to transactional reservation/finalisation backed by policy/entitlements. Add organisation and platform threshold alerts, reservation-leak reconciliation, safe storage projections, bounded safety-mode commands, material organisation resource-usage events, daily storage/index/processing aggregates, and provider account/project reconciliation snapshots. Keep health time series outside the transactional database and customer billing out of scope.
7. Add common operational-run projection adapters, per-kind SLA/stuck detection, durable alerts, and typed retry delegation. Remove document-status/hourly-scan recovery inference only after adapters and retry semantics pass parity/security tests.
8. Build the console surfaces against secured server pagination/filtering and the design-system interaction contract. Remove `/usage` from tenant navigation; retire or redirect it only after `/platform/usage` is live, ensuring unauthorised tenant users receive no cross-domain data.
9. For the design-partner release, verify Supabase Pro managed database-backup status, document that Storage objects are excluded, record client-original retention and source-rehydration limitations, and test the bounded missing-object state. Before crossing the independent-backup gate, implement complete encrypted backup sets: logical database backup, independent object-byte copy, manifest/hash verification, retention, safe freshness/drill evidence, out-of-band critical alert delivery, controlled restore runbook, and isolated restore drill.
10. Run expand/backfill/verify/cut-over/contract migrations. Narrow broad service-role helpers and delete legacy usage tables/actions only after ledger, projection, privacy, RLS, and parity tests pass. Do not alter tenant legal facts or retention/hold behavior during cutover.
11. Permit rollout beyond the controlled pilot only when all acceptance criteria pass, the backup gate is green, and no critical backup alert is overdue. Multi-region HA/PITR beyond the pilot is out of scope.

## Interfaces and Data Changes

- `platform_operators`: auth user ID, role, active state, lifecycle/revision metadata; at least one active Owner invariant.
- `platform_privileged_intents`: server-verifiable operator/command-family intent, issued/expiry/consumption metadata; maximum 10-minute validity.
- `platform_audit_events` and `platform_alerts`: append-only audit and durable alert lifecycle with allowlisted fields only.
- `platform_policy_versions`, `organisation_entitlements`, `model_catalogue_versions`, `runtime_config_versions`, and `provider_pricing_versions`: validated effective-dated revisions with actor/reason/revision data.
- `operational_sla_profiles` and explicit run-kind bindings/overrides: versioned thresholds, active profile invariant, safe profile/category metadata, and alert deduplication identity.
- `platform_backup_sets`: logical backup identity, independent object-copy identity, manifest identity/version, safe coverage counts, verification/freshness/drill evidence, retention class, and alert state; backup contents remain inaccessible to the console.
- `provider_usage_events`, `provider_usage_line_items`, and daily rollups: immutable provider quantities, pricing/model versions, micro-USD snapshots, legacy quality state, correlation/idempotency, and aggregate projections.
- `organisation_resource_usage_events` and daily rollups: material measured/estimated organisation quantities such as unique asset-byte deltas, retained-byte classes, object-access grants, export bytes, processing pages, embedding chunks/vectors, and safe operation outcomes. Raw content and per-request telemetry are excluded.
- `provider_account_usage_snapshots`: provider/service, account/project scope, UTC period, quantity/unit/cost where available, source/fetch time, and reconciliation quality. These aggregate totals are never presented as exact tenant allocation.
- Secured organisation/run projection views or capability RPCs return safe metadata only; platform commands derive actor/capability server-side and accept expected revision/idempotency/reason where relevant.

```ts
type PlatformOperatorRole = 'platform_owner' | 'platform_operator' | 'platform_auditor'
type PlatformCapability =
  | 'platform.overview.read'
  | 'platform.organisations.read'
  | 'platform.usage.read'
  | 'platform.jobs.read'
  | 'platform.storage.read'
  | 'platform.models.read'
  | 'platform.audit.read'
  | 'platform.operators.read'
  | 'platform.alerts.manage'
  | 'platform.jobs.retry'
  | 'platform.organisations.safety_mode.manage'
  | 'platform.organisations.entitlement.manage'
  | 'platform.policy.storage_quota.manage'
  | 'platform.models.runtime_pricing.manage'
  | 'platform.features.kill_switch.manage'
  | 'platform.operators.manage'
type PlatformSafetyMode = 'normal' | 'new_ingestion_paused' | 'ai_paused' | 'read_only_safety_hold'
type PlatformAlertState = 'open' | 'acknowledged' | 'resolved'
type UsageQuality = 'priced' | 'unpriced' | 'legacy_unverified'
type ResourceMeasurementQuality = 'measured' | 'estimated' | 'provider_reported'
```

## Testing and Acceptance Criteria

- A development fixture retains intended aggregate metering, while a production-like ordinary member or tenant Admin cannot read legacy global Usage or mutate platform prices through direct calls. Record actual environment/guard evidence; code comments are insufficient.

- Tenant Owner/Admin cannot access the console, configuration, another organisation's data, or forge usage. Email/environment spoofing cannot create operator authority. Role/capability/RLS/direct-ID/cross-tenant tests fail closed.
- Route/RPC tests cover every role/capability matrix cell: all read routes, Owner-only operator roster, every mutation grant/denial, Auditor's total mutation denial, and independent route-versus-command checks. Console access requires AAL2; privileged-intent classification tests prove alerts require none while every listed consequential mutation rejects an expired, forged, reused, wrong-operator, or wrong-family 10-minute intent. The last active Owner cannot be suspended/deleted.
- No service-role client/credential reaches the browser or ordinary platform mutations. Direct table/RPC tests prove append-only audit/cost rules and trusted-worker-only usage writes.
- Privacy allowlist snapshots and log tests prove the console/audit/logs exclude content, filenames, references, raw provider errors/payloads, embeddings, signed URLs, paths, secrets, messages, and email lists.
- Usage tests prove provider-unit fidelity, effective price/model version exactness, integer micro-USD snapshots, unpriced handling, dedupe/retry idempotency, daily rollups, and `legacy_unverified` labels. Characters never pass as tokens.
- Resource-metering tests prove unique asset-byte accounting, active/history/Trash/Intake separation, daily time-weighted aggregation, replay-safe material events, explicit measured/estimated/provider quality, and no invented tenant apportionment of shared provider totals. Raw query, content, filename, URL/path, prompt, IP, user-agent, and per-request memory data never enter these records.
- Concurrent quota reservation/finalisation tests prove 70/80/85/95/100 boundary behavior, unique-asset accounting, leakage recovery, platform-ceiling failure, and continued existing reads. Quota changes cannot purge, bypass holds, or alter legal facts.
- Job tests cover the versioned SLA-profile binding invariant, each exact threshold boundary using database UTC time, claimed/running heartbeat scope, due-time scheduled lateness, warning/critical escalation, logical-run/rule/profile-version deduplication, explicit override behavior, and critical unmapped-kind alerts/manual-retry denial. They also cover retryable-terminal gating, typed successor creation, stale-source/no-live-successor rejection, idempotency, and no history mutation. Kill switches preserve manual workflows.
- The Trigger runtime release gate proves the explicit Node 24 build and every
  registered worker/schedule in preview before promotion, including native
  PDF dependencies, provider calls, durable outbox delivery, bounded retries,
  version locking, and rollback to the prior worker version.
- Responsive/accessibility tests cover compact headers, scroll ownership, server pagination/filtering, keyboard/screen-reader operation, 44px targets, loading/empty/error/long content, and desktop/mobile list-detail behavior.
- The design-partner release verifies Supabase managed database-backup status, truthfully reports that Storage bytes are outside those backups, and exercises a content-safe missing-object/rehydration-match fixture without claiming an automatic restore. After the independent gate activates, backup failure and overdue-drill alerts reach configured operational contacts without content; tests cover complete private object-byte/version coverage, manifest presence, retention, missing/corrupt bytes, missing manifest entries, hash mismatch, and successful recovery from the independent copy within RPO/RTO. A full isolated restore drill proves tenant isolation, hashes/object availability, RLS/capabilities, and critical projections. The rollout gate prevents a second production organisation until the successful drill exists and no overdue critical backup alert remains.

## Assumptions

- Supabase Auth remains the source of authentication and assurance level; platform authority remains separate from tenant membership.
- Platform Operations consumes, but does not replace, the owning domain's document, AI, Work/Review, realtime, and Trash contracts.
- The controlled design-partner release uses Supabase Pro, a reviewable 350 MiB unique-asset organisation entitlement, and USD only for internal provider-cost accounting. Provider plan allowances and prices remain deployment configuration rather than hard-coded product truth.

## Open Questions

None.
