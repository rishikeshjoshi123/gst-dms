---
title: Platform Operations
status: approved
created: 2026-08-27
updated: 2026-08-27
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

## Summary

Establish a separate, privacy-preserving Platform Operations trust domain for CaseChain. It provides controlled operator identity, MFA-protected operational actions, safe organisation and job projections, immutable provider-cost accounting, versioned configuration and quotas, audit/alerting, and a tested backup/recovery gate.

This is not a tenant-administration extension and does not grant legal-content access. It corrects the current global `/usage` and service-role shortcuts before rollout beyond the controlled pilot. Platform Operations must ship, meet its acceptance gates, and pass a restore drill before that rollout.

## Context and Goals

Current operational controls cross tenant boundaries unsafely: `/usage` sits in authenticated tenant navigation, queries all organisations with a service-role client, and is capped to 1,000 rows in client-side handling. Tenant Admins can globally overwrite `model_pricing`, authenticated tenant members can insert usage rows, pricing is overwritten instead of versioned, and costs are floating USD. Existing comments/seeds confuse characters with tokens.

Worker recovery infers work from document status and an hourly scan rather than durable domain run state. Service-role access is a broad server helper rather than a narrowly trusted boundary. Worker logs contain IDs/storage paths and raw provider errors. There is also no repository-owned backup/restore contract or platform-operator identity.

The goals are to make these functions safe, auditable, and operationally useful while preserving tenant isolation and legal evidence boundaries. The console serves health, bounded remediation, configuration, and accountability; it is never a browser for tenant content, a general database console, or a billing product.

## Decisions

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

- `/platform/overview` is action-first: health, active alerts, provider/model state, and backup freshness; it is not a vanity dashboard.
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
- Model catalogue, runtime configuration, and provider pricing are validated, versioned, effective-dated, atomic, previewed, reasoned, audited, and revision-checked. High-impact changes are Owner-only. Kill switches may pause optional AI families while preserving manual legal workflows. Tenant Admins cannot read or mutate this configuration.

### Storage and quota enforcement

- Preserve approved pilot defaults: 25 MB PDF default, up to 50 MB by justified platform approval, 100 MB unique-asset organisation entitlement, and 750 MB platform storage guard on Supabase Free.
- Warn organisations at 80% and 95%; reject/reservation-fail at 100%. Alert the platform at 70%, 85%, and 95%; fail closed for new reservations at the platform ceiling while existing reads continue.
- Enforcement is configuration-backed, transactional server-side reservation/finalisation, not UI constants. AI budgets are alert/safety controls initially and never silently block core legal work from mutable client calculations.

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
| `backup` — backup/object-copy verification | start-late warning 15m; critical 60m | warning 10m; critical 30m | warning 120m; critical 480m | successful verified-backup freshness warning at 20h; critical at 24h; never automatic retry |

- A manual retry delegates to the owning typed command only for retryable terminal state, current active source, and no live successor. It requires idempotency, actor reason, revision check, and `platform.jobs.retry`; it creates a new attempt/successor and never edits history. Do not expose arbitrary payload editing, raw Trigger replay, or cancellation unless the owning domain already proves it safe.
- Systemic failures alert platform staff. Tenant-actionable failures enter the approved Review/notification flow with minimal context.
- Add `platform_operators`, append-only `platform_audit_events`, durable `platform_alerts` (`open`, `acknowledged`, `resolved`), versioned policy/config/pricing records, `organisation_entitlements`, provider usage event/line-item tables and rollups, and secured organisation/run views/RPCs.
- Audit captures actor, capability, target type/opaque ID, action, reason, allowlisted before/after delta, correlation/idempotency, outcome, and time. App roles cannot update/delete audit; corrections append. Retain platform audit and the cost ledger at least seven years, detailed runs/alerts at least 400 days, and aggregates for trend continuity. Where a finalized plan has a stronger legal/audit rule, preserve that stronger rule.
- Structured event names and safe codes only. Normalize provider errors at the boundary. Metrics/alerts cover queue age, failures/retries, latency, unpriced usage, provider/model health, reservation leakage, storage guards, backup freshness, and restore drills. Critical alerts also notify configured operational contacts out of band without content.

### Backup, recovery, and rollout gate

- Before controlled-pilot onboarding, create vendor-independent daily encrypted logical database backups plus an encrypted independent-destination copy of the complete private object bytes, including every retained PDF/object version governed by the source system. Create a manifest for each copy with object identity/version, size, and cryptographic hash. The independent object-byte copy, database backup, and manifest are one recoverable backup set; inventory alone is never a backup. Copies and keys live outside the primary failure domain; data backups exclude application, auth, and provider secrets.
- Retain 30 daily and 12 monthly complete backup sets unless a stronger legal retention rule applies. Pilot objectives are RPO ≤24 hours and RTO ≤8 hours.
- Run an isolated non-production restore drill before pilot onboarding and at least quarterly. Restore object bytes from the independent copy and verify hashes before success; verify tenant isolation, complete version coverage, RLS/capabilities, and critical projections. Store only safe drill evidence/freshness metadata and raise alerts for failures or overdue drills.
- Restore has no browser button. It follows a controlled runbook requiring Owner privileged intent and a second authorised approver where available; a single-owner pilot exception must be documented and closed before broader rollout. It never exposes backup contents in the console.
- Rollout beyond the controlled pilot is blocked until a successful restore drill exists and no critical backup alert is overdue.

## Implementation Plan

1. Establish the approved Organisation Administration identity/RBAC foundation, then the Document Record and File Lifecycle foundation. Preserve owning-domain durable outbox/run records and safe state before adding the platform projections.
2. Add platform trust/config/accounting/audit/alert schema, enum/check constraints, append-only permissions, RLS, capability RPCs, safe projections, revision/idempotency support, and explicit retention jobs. Bootstrap the first Owner with the controlled runbook and audit it.
3. Build platform authentication/authorisation: isolated route/layout, active-operator lookup, AAL2 enforcement, 10-minute privileged intent, non-disclosing denial, account launcher, Owner lifecycle invariant, and service-role boundary narrowing.
4. Introduce versioned model/runtime/pricing catalogues and policy/organisation-entitlement records. Backfill immutable legacy price versions as `legacy_seed_pending_verification`; remove tenant global-price access/mutations only after secured replacements are proven.
5. Introduce the append-only usage ledger and line items. Dual-write trusted worker usage, reconcile exact quantities/cost snapshots and idempotency, backfill legacy rows as `legacy_unverified`, build daily rollups/unpriced alerts, then cut usage reads to secured platform projections.
6. Move quota enforcement to transactional reservation/finalisation backed by policy/entitlements. Add organisation and platform threshold alerts, reservation-leak reconciliation, safe storage projections, and bounded safety-mode commands.
7. Add common operational-run projection adapters, per-kind SLA/stuck detection, durable alerts, and typed retry delegation. Remove document-status/hourly-scan recovery inference only after adapters and retry semantics pass parity/security tests.
8. Build the console surfaces against secured server pagination/filtering and the design-system interaction contract. Remove `/usage` from tenant navigation; retire or redirect it only after `/platform/usage` is live, ensuring unauthorised tenant users receive no cross-domain data.
9. Implement complete encrypted backup sets: logical database backup, independent object-byte copy, manifest/hash verification, retention, safe freshness/drill evidence, out-of-band critical alert delivery, controlled restore runbook, and isolated restore drill.
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
```

## Testing and Acceptance Criteria

- Tenant Owner/Admin cannot access the console, configuration, another organisation's data, or forge usage. Email/environment spoofing cannot create operator authority. Role/capability/RLS/direct-ID/cross-tenant tests fail closed.
- Route/RPC tests cover every role/capability matrix cell: all read routes, Owner-only operator roster, every mutation grant/denial, Auditor's total mutation denial, and independent route-versus-command checks. Console access requires AAL2; privileged-intent classification tests prove alerts require none while every listed consequential mutation rejects an expired, forged, reused, wrong-operator, or wrong-family 10-minute intent. The last active Owner cannot be suspended/deleted.
- No service-role client/credential reaches the browser or ordinary platform mutations. Direct table/RPC tests prove append-only audit/cost rules and trusted-worker-only usage writes.
- Privacy allowlist snapshots and log tests prove the console/audit/logs exclude content, filenames, references, raw provider errors/payloads, embeddings, signed URLs, paths, secrets, messages, and email lists.
- Usage tests prove provider-unit fidelity, effective price/model version exactness, integer micro-USD snapshots, unpriced handling, dedupe/retry idempotency, daily rollups, and `legacy_unverified` labels. Characters never pass as tokens.
- Concurrent quota reservation/finalisation tests prove 70/80/85/95/100 boundary behavior, unique-asset accounting, leakage recovery, platform-ceiling failure, and continued existing reads. Quota changes cannot purge, bypass holds, or alter legal facts.
- Job tests cover the versioned SLA-profile binding invariant, each exact threshold boundary using database UTC time, claimed/running heartbeat scope, due-time scheduled lateness, warning/critical escalation, logical-run/rule/profile-version deduplication, explicit override behavior, and critical unmapped-kind alerts/manual-retry denial. They also cover retryable-terminal gating, typed successor creation, stale-source/no-live-successor rejection, idempotency, and no history mutation. Kill switches preserve manual workflows.
- Responsive/accessibility tests cover compact headers, scroll ownership, server pagination/filtering, keyboard/screen-reader operation, 44px targets, loading/empty/error/long content, and desktop/mobile list-detail behavior.
- Backup failure and overdue-drill alerts reach configured operational contacts without content. Tests cover complete private object-byte/version coverage, manifest presence, retention, missing/corrupt bytes, missing manifest entries, hash mismatch, and successful recovery from the independent copy within RPO/RTO. A full isolated restore drill proves tenant isolation, hashes/object availability, RLS/capabilities, and critical projections. The rollout gate prevents broader rollout until the successful drill exists and no overdue critical backup alert remains.

## Assumptions

- Supabase Auth remains the source of authentication and assurance level; platform authority remains separate from tenant membership.
- Platform Operations consumes, but does not replace, the owning domain's document, AI, Work/Review, realtime, and Trash contracts.
- The controlled pilot retains the approved storage defaults and uses USD only for internal provider-cost accounting.

## Open Questions

None.
