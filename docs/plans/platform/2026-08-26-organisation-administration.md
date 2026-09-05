---
title: Organisation Administration, Team Access, and Personal Settings
status: in-progress
created: 2026-08-26
updated: 2026-09-01
owners:
  - product
  - engineering
related:
  - ./2026-08-24-product-architecture-portfolio.md
  - ./2026-08-24-resource-trash-retention-and-purge.md
  - ../features/2026-08-25-work-review-activity-notifications.md
  - ../features/2026-08-26-deadlines-and-financials.md
  - ./2026-08-25-realtime-delivery-freshness-and-unread-state.md
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# Organisation Administration, Team Access, and Personal Settings

## Summary

Replace the current mixed Settings card with three explicit experiences: a dedicated **Team** workspace for memberships and invitations, an **Organisation** settings area for tenant profile and operational policy, and one scrollable **My settings** page for a user's profile, password change, appearance, notifications, and digest.

Tenant access becomes capability-driven and auditable. Owner is an explicit, transferable authority rather than an inference from `created_by`; membership removal preserves history instead of hard-deleting it; invitation acceptance is atomic and token-safe; and role, suspension, departure, removal, and Matter-specific grants are reconciled through typed lifecycle commands. CaseChain retains one active organisation per ordinary user during the controlled pilot, removes the misleading workspace-switching affordance, and gives every membership a predictable 30- or 60-day departure-notice contract with governed handover and automatic offboarding. Personal profiles remain portable while professional contribution summaries remain private and organisation-scoped.

## Context and Goals

The current `/settings` route combines a read-only organisation card with a primitive member list. It cannot resolve most member names or email addresses because there is no tenant-safe profile projection. It supports invitation, revocation, and hard membership deletion, but not role changes, suspension, reactivation, ownership transfer, offboarding impact, resend, invitation history, personal preferences, organisation policy, or security controls.

The current identity model has several unsafe or incomplete contracts:

- organisation ownership is inferred from `organisations.created_by` while the member role remains `admin`;
- every authenticated member can insert themselves into an organisation under the broad RLS policy if they can supply its ID;
- invite acceptance inserts membership and marks the invitation accepted in separate operations;
- raw invitation tokens are stored in the database;
- admin Server Actions use service-role access and page-local role conditions rather than one capability contract;
- member removal physically deletes the row and does not reconcile tasks, Review, deadlines, cost grants, realtime access, or historical actor rendering;
- a unique `org_members.user_id` constraint enforces one organisation, while the shell still displays a workspace switcher and queries multiple organisations;
- personal information lives only in auth metadata, leaving normal tenant reads unable to render colleagues;
- notification preferences are five booleans and cannot represent quiet hours, verified-deadline lead times, or the approved weekly digest;
- the development Usage page crosses every tenant through a service client because no isolated platform-admin surface exists.

The goal is not to make Settings larger. It is to establish a secure tenancy and administration domain that every feature can consume without inventing page-local role logic.

## Decisions

### Product surfaces and navigation

- Add `/team` as a first-class organisation workspace. It owns active/suspended members, invitation lifecycle, role management, ownership transfer, and offboarding. Team does not live inside My settings.
- Replace `/settings` with one vertically scrollable personal settings page. It renders compact `Personal profile`, `Contribution`, `Account access`, `Appearance`, `Direct email`, and `Weekly digest` sections in that order, followed by the personal `Leave organisation` action; it has no section rail, section-switching route, or standalone Security page.
- Add organisation-scoped settings under `/settings/organisation/profile` and `/settings/organisation/operations`. Owner/Admin can edit authorised fields; other active members receive the small read-only organisation profile only and do not see privileged operational policy details. Do not expose an organisation Security/MFA tab in the initial release.
- The account menu shows user identity, current organisation and role, `My settings`, the light/dark/system appearance control, and `Sign out`. Theme control moves out of the global top bar. Destructive or administrative organisation actions do not live in the account menu.
- Team belongs in the main organisation navigation. Organisation settings are reachable from Team and My settings but do not become another high-frequency rail item.
- During the one-organisation pilot, remove the workspace switcher and label the current tenant as `Organisation`. A later multi-organisation plan may restore switching against the same membership identity contract.
- Platform administration is a separate trust domain and route tree. `/usage` must not remain an ordinary tenant route or rely on a special email/password convention; its migration belongs to the Platform Operations plan.

### One-organisation pilot and future compatibility

- One ordinary user may have exactly one active or suspended organisation membership during the controlled pilot. A removed membership does not block the user from accepting or creating a membership elsewhere.
- A suspended member cannot create or join another organisation to bypass suspension. Sign-in leads to a non-disclosing `Access suspended` state with organisation contact guidance.
- Historical membership generations use stable surrogate IDs. Rejoining an organisation after removal creates a new membership generation rather than resurrecting or overwriting the old audit record.
- Organisation creation, invitation acceptance, and rejoining serialize eligibility by authenticated user and enforce the same database uniqueness invariant; two concurrent join paths cannot create two active/suspended memberships.
- Tenant RPCs derive the organisation only from `auth.uid()` and that user's exactly one active membership, then independently validate organisation lineage and current capability. They never select a newest membership and never trust a browser organisation ID, cookie, or selected-workspace record. Zero active memberships is ordinary no-access state; more than one is an invariant incident that fails closed, raises a safe operational alert, and is repaired only through a privileged runbook.
- Multi-organisation access, workspace selection, and session-bound organisation context remain unavailable until a separate plan deliberately replaces this invariant and migrates every tenant RPC together.

### Roles, ownership, and capabilities

- Keep the initial role families `Admin`, `Associate`, and `Viewer`. Owner is one explicit organisation authority layered on an Admin membership, not a fourth value silently inferred in the UI.
- `organisations.created_by` remains immutable historical provenance. Add `owner_membership_id` as the current authority and require exactly one active Owner.
- Server projections return capability keys. UI code may render from capabilities but cannot infer authority solely from a role label. RLS and every domain command independently revalidate active membership, organisation lineage, capability, record revision, and recent-auth requirements.
- Initial capability policy:

| Capability | Owner | Admin | Associate | Viewer |
| --- | --- | --- | --- | --- |
| View active Team directory | Yes | Yes | Yes | Yes |
| Invite Associate or Viewer | Yes | Yes | No | No |
| Invite or promote Admin | Yes | No | No | No |
| Edit organisation profile/defaults | Yes | Yes | No | No |
| Edit organisation operations policy | Yes | Yes | No | No |
| Change between Associate and Viewer | Yes | Yes | No | No |
| Suspend/reactivate/remove Associate/Viewer | Yes | Yes | No | No |
| Change, suspend, or remove an Admin | Yes | No | No | No |
| Transfer ownership | Yes | No | No | No |
| Permanently purge eligible Trash | Yes | Yes | No | No |
| Edit personal settings | Self | Self | Self | Self |

- An Admin cannot create another Admin, demote/remove an Admin, transfer ownership, or weaken an Owner-only safeguard. Owner actions requiring elevated consequence use typed confirmation now; provider-backed recent authentication is added only when the deferred advanced-security contract ships.
- The same snapshotted 30/60-day notice applies to Owner, Admin, Associate, and Viewer departures. Admin offboarding cannot execute until the Owner resolves privileged-role and last-eligible-Admin coverage; the Owner must transfer ownership before offboarding can execute.
- Feature-specific access remains the intersection of tenant role, resource access, and explicit grant. A Matter financial-cost grant can narrow or reveal that ledger as already approved, but cannot elevate a Viewer to edit or confer administration.

### Membership lifecycle and offboarding

- Membership state is separate from role: `active`, `suspended`, or `removed`. Invitation state is not a membership state.
- Organisation operations policy chooses a departure notice of 30 or 60 days, default 30. Invitation acceptance or organisation creation snapshots the current value and policy version onto the new membership generation; later policy changes are prospective and cannot silently lengthen or shorten an existing member's accepted notice.
- A departure notice is a separate case rather than a membership state. Submission keeps the membership active, records the computed effective local date, optional reason and handover note, and shows the user the exact midnight-IST effective time plus whole days remaining. The self-service impact page explains access loss, preserved authorship, open Tasks/Review, verified deadlines, Matter responsibility, grants, pending invitations, digests, and privileged coverage before confirmation.
- Owner/Admin users alone see current departure cases in Team and on the affected member's inspector, including effective date, remaining days, notice snapshot, dependency counts, handover state, and pending early-release request. Associates and Viewers do not receive an organisation-wide departures queue or another member's notice detail.
- A member may submit at most three early-release requests per active departure case and at most one may be pending. Each request supplies a desired earlier effective date and optional reason. Approval authority follows the membership matrix: Admin may decide Associate/Viewer requests, Owner may also decide non-owner Admin requests, and a current Owner cannot approve their own request before transferring ownership. Approval shortens the effective date, while decline leaves the original notice intact. Approval for the earliest release executes at the next midnight maintenance boundary unless a separately governed immediate administrative removal is required.
- A member may withdraw until offboarding execution begins. Withdrawal cancels the scheduled offboarding and any pending early-release request, preserves private audit history, and notifies Owner/Admin. It does not reverse Tasks, grants, or responsibilities already deliberately reassigned during handover.
- Suspension is reversible and immediately blocks tenant reads, writes, all authenticated loaders and actions, realtime joins, new signed asset issuance, Search, notifications, email digests, and worker actions for that member. Already-issued short-lived signed URLs expire at their bounded TTL. Existing authored content remains attributed and readable according to other users' access.
- Reactivation restores the role that remained valid at suspension time but does not automatically restore feature grants that were explicitly revoked during review.
- Removal is durable offboarding, not user or history deletion. It immediately revokes tenant access, all authenticated loaders and actions, personal delivery schedules, realtime eligibility, new signed asset issuance, and Matter-specific grants. Already-issued short-lived signed URLs expire at their bounded TTL. The global account and self-maintained profile survive for later membership elsewhere; historical notes, decisions, activity, and audit render from membership/profile snapshots without exposing removed users to current data.
- Before suspension, administrative removal, role downgrade, departure submission, or departure execution, return the appropriate impact projection covering open tasks, Review assignments, verified deadlines, Matter responsibility, internal-cost grants, pending invitations sent by the member, scheduled digests, and privileged-role coverage.
- Consequential open work must receive an explicit disposition in the command: reassign to an eligible active member, return to the team/unassigned queue where the owning domain permits it, or block the change where an accountable owner is mandatory. No command silently marks work complete.
- Role downgrade or membership loss revokes incompatible Matter grants in the same transaction. Every feature still recalculates effective capability on read/write so stale rows or clients cannot preserve access.
- Suspending or removing the last eligible Admin is blocked. Transferring ownership verifies that the recipient is an active Admin; additional MFA policy is deferred and cannot be assumed by the initial command.
- A typed maintenance coordinator runs at 00:00 `Asia/Kolkata`, uses authoritative database time, and invokes bounded idempotent domain jobs rather than holding unrestricted cleanup authority. Due offboarding executes access revocation and membership removal atomically where possible; if dependent cleanup fails, access still fails closed, the case enters `failed_pending_cleanup`, and a safe operational alert plus catch-up retry is created. Missed schedules are recoverable and the product promises execution at or shortly after midnight, not at an exact second.
- Administrative suspension/removal remains a separate security path and may revoke access immediately after its own impact and authority checks; it does not wait for the self-service notice period.

### Team directory and member profiles

- Add a tenant-safe global `user_profiles` record keyed by auth user ID with display name, optional professional title, short professional bio, locale, and timezone. Add bounded ordered professional-profile entries for practice areas/expertise, qualifications or jurisdictions, languages, education, and selected prior experience. Authentication email remains owned by Supabase Auth and is exposed through a secured member projection rather than copied into arbitrary feature tables.
- The initial profile is a compact professional operating identity, not a social network: no date of birth, public profile, follower graph, feed, endorsements, popularity counters, or employer-verification claim. Self-maintained global fields remain portable between organisations, while organisation role, joined date, notice snapshot, access history, and contribution facts remain membership-scoped.
- The pilot does not accept profile-image uploads or store avatar assets. Use one shared Unicode-aware initials formatter: the first grapheme of the first and last non-empty name tokens, the first two graphemes for a single-token name, and a neutral user icon when no usable display name exists. Initials are derived at render/projection time and update with the display name.
- Active organisation members can see teammates' display name, derived initials, role, and professional title for collaboration and mentions. Email address, invitation history, suspension detail, and security posture are restricted to the member themselves and authorised administrators.
- A user's initial `Contribution` summary is self-only and derives from canonical organisation-scoped Task, Review, and Activity facts with explicit time windows and definitions. It may show Tasks completed/currently assigned, Review decisions completed, Matters contributed to, and recent activity trend; it never becomes an editable counter, portable cross-organisation history, productivity score, leaderboard, hours-online measure, or peer ranking. Owner/Admin Team views receive current responsibility/impact needed for operations, not a performance score.
- The Team desktop view is a real server-driven table with `Person`, `Role`, `Status`, `Joined`, and one stable row action. Search covers name and authorised email; filters cover role and lifecycle state. Repeated role/status badges have collection-wide fixed widths.
- Pending, expired, rejected, and revoked invitations live in an `Invitations` Team view instead of being mixed beneath members. The default list shows pending actionable invitations; terminal history is available through filters.
- Selecting a member opens a stable detail inspector with identity, role/capabilities summary, work impact, Matter grants, access history, and only the actions the caller can perform. On mobile it becomes an explicit detail route/drawer with a clear Back action.
- `Invite member` is the rightmost primary Team workbar action. Role explanation appears before sending. Inviting an Admin is visually and procedurally distinct and Owner-only.

### Invitation lifecycle

- Invitation email is normalised and compared case-insensitively. Store only a cryptographic hash of the single-use token; the raw token exists only in the delivery URL.
- Invitation states are `pending`, `accepted`, `rejected`, `expired`, `revoked`, and `superseded`. Status changes are append-audited; administrators do not hard-delete invitations.
- Initial invitation lifetime is seven days. Resend rotates the token, supersedes the prior invitation version, and extends expiry from the resend time. Limit delivery to three sends per address per 24 hours and 50 invitation sends per organisation per 24 hours; return a safe retry time without revealing whether an external account exists.
- Admin may invite Associate/Viewer. Owner may also invite Admin. Duplicate pending invitations for the same normalised email and organisation are blocked with a Resend action.
- Acceptance requires an authenticated user whose verified auth email matches the invitation. Sign-in/sign-up returns to the invitation intent without placing tokens in client persistence.
- Accepting performs eligibility validation, membership insertion, invitation acceptance, organisation context creation, Activity/outbox append, and notification cancellation atomically. A retry returns the same result.
- During the single-organisation pilot, an account with another active/suspended membership receives a non-disclosing incompatibility message. The inviting organisation is not told which other organisation holds the account.
- Rejection does not block a later invitation. Revocation/expiry cannot be accepted from a stale link. Terminal invitations retain necessary audit metadata for 180 days, after which the address is redacted while an opaque audit tombstone remains.

### Organisation profile and operational policy

- Organisation profile fields are: display name, optional registered name, optional logo asset, optional establishment date, optional short tagline, locale/date format, and default currency. India-first defaults are operational timezone `Asia/Kolkata` and profile locale/currency `en-IN` and `INR`.
- `created_at` is immutable system metadata. `established_on` is optional historical information supplied by the organisation and is never presented as the account creation date.
- The tagline is limited to restrained organisation/profile and invitation contexts; it does not consume Matter headers, Today, loading screens, or operational workspaces.
- Do not create AI-generated motivational quotes, a rotating quote table, or background quote-refresh jobs. They add cost and distraction without helping legal work. A later content feature would require evidence of user value.
- Operations settings own organisation timezone, the prospective 30/60-day departure-notice policy (default 30), default deadline reminder policy, weekly digest defaults, and read-only storage entitlement/usage. Trash retention is owned by the Trash contract: Owner/Admins choose one automatic 30-, 60-, or 90-day period (default 90); there is no manual-only option or separate auto-purge switch. They also own an Owner/Admin-only initial document-placement policy: `manual_suggestions` (default), `strong_evidence_auto_place`, or `intended_matter_only`. The setting describes how unassigned Intake may be placed; it can never silently move an already assigned document.
- Tenant administrators can choose the approved Trash retention period but cannot raise platform quota, change provider pricing, see other organisations, or bypass legal holds. Initial storage entitlement remains the separately approved 100 MB of unique assets.
- Organisation defaults seed new personal preferences; they cannot force non-mandatory email on an existing user. Mandatory access/security delivery remains governed by the notification plan.
- Organisation deletion/closure is not an ordinary Settings action in the initial release. It requires a separate, support-visible, retention-aware closure design and is not implemented as a cascading delete.

### Personal settings

- `Personal profile` owns display name, professional title, short bio, bounded professional entries, locale, and personal timezone. It previews the derived initials but has no photo-upload action. `Contribution` presents the self-only organisation-scoped summary with definition and period context. Email change is a Supabase Auth verification workflow, not an ordinary profile field mutation.
- `Leave organisation` opens the dedicated impact/notice page rather than performing an inline destructive action. After submission the same route becomes the member's countdown, handover, early-release, and withdrawal surface.
- `Account access` contains the provider-backed `Change password` action. The UI does not claim a password-change timestamp unless the provider supplies authoritative data.
- `Appearance` offers `System`, `Light`, and `Dark` for the Civic Ink appearance only. There is no separate CaseChain motion override in the initial release: the shared application shell, primitives, and feature UI must honor the device/browser `prefers-reduced-motion` setting everywhere. Apply the approved restrained colour transition for other users, and do not add stars, sunrise scenes, decorative gradients, or arbitrary theme colours.
- `Notifications` consumes the approved per-event-family contract: mentions, task assignments, Review assignments, verified deadline reminders, invitation/security events, and assigned failures. Routine upload/processing completion is not offered because it is not a notification.
- Optional direct-email families and the weekly digest are off by default for every new user. Users opt in per family; mandatory access and security delivery has no off switch and is not represented as an optional preference.
- Users configure eligible delivery mode, verified-deadline lead times, quiet hours, timezone, and the weekly email digest. The digest is weekly only; users choose enabled/disabled, included non-urgent families, weekday, local send time, and timezone.
- The optional AI-written digest overview remains disabled behind its separate evaluation flag. When eventually enabled it is an explicit personal opt-in and cannot replace the deterministic digest.
- Personal preference writes are user-only, revisioned for conflict detection, and do not create noisy organisation Activity. Material security changes enter the private security audit and send the required security notification.

### Deferred advanced account security

- MFA enrollment, MFA enforcement policy, recovery-code management, active-session review/revocation, and a standalone personal or organisation Security page are not part of the initial implementation.
- When these capabilities are scheduled, use Supabase Auth assurance levels, factors, and sessions; never build a parallel password, OTP, authenticator-secret, recovery-code, or session store.
- Commands that eventually require recent authentication must ship only with a provider-backed, short-lived server-verifiable intent bound to user, organisation, command family, and expiry. Do not simulate this requirement in the pilot UI.
- The initial Account access section supports password change only. Account recovery continues through the provider's existing verified recovery flow rather than a custom CaseChain screen.

### Authorisation, transactions, and service boundaries

- Replace broad page Server Actions and service-role multi-step writes with typed domain commands backed by security-definer database functions or equivalent transactions. Each command derives the caller from auth context and the organisation from the active membership; it does not trust a browser-submitted role or tenant ID.
- Organisation creation, invitation acceptance, and membership re-entry serialize on the authenticated user and share the database-enforced one-active-or-suspended-membership invariant. Ordinary RPCs cannot repair an impossible duplicate; they deny tenant data, emit safe diagnostics, and leave correction to a controlled runbook.
- Remove the current RLS path that permits `org_members` self-insertion. A membership can be created only through organisation creation or validated invitation acceptance.
- Central capability definitions are versioned and tested. Feature pages consume `capabilities: string[]`; they do not maintain their own Admin/Associate/Viewer matrices.
- Service-role access is restricted to trusted email/outbox workers, expiry jobs, backfills, and platform operations. It cannot be used as a shortcut for an ordinary browser mutation.
- Material administration commands write their source change, append-only administration event, user-facing Activity event where appropriate, and transactional outbox record atomically.
- Error responses are stable and non-disclosing: unauthenticated, access suspended, not permitted, stale revision, last-admin blocked, work-reassignment required, invite expired/revoked, rate limited, and recent authentication required.

### Activity, security audit, and notification effects

- Organisation Activity receives human-useful events such as member joined, role changed, member suspended/reactivated/removed, ownership transferred, and organisation profile/policy changed. It does not expose raw invite tokens, MFA detail, provider payloads, or unnecessary email addresses.
- An Owner/Admin-only administration audit retains invitation lifecycle, departure submission/withdrawal/early-release decisions, capability/role changes, operational-policy changes, and access removal with actor, target snapshot, reason, correlation ID, and timestamp. It is a backend audit contract in the initial release, not a dedicated settings screen.
- Direct invitations, role/access changes, suspension/reactivation/removal, ownership transfer, and password/email changes create the approved addressed notifications. Reading one does not undo or accept the change.
- Departure submission, early-release request and decision, withdrawal, seven-day/one-day reminders, successful offboarding, and operational failure create mandatory durable addressed notification intents that users cannot disable. Resend is the initial replaceable email adapter; source transactions never send email inline, retries do not duplicate delivery, delivery failure never reverses membership state, and emails contain safe summaries plus authenticated links rather than Matter/client/work detail.
- Member removal cancels future personal delivery, digest schedules, and direct unread projections that no longer have an authorised target. Historical Activity remains renderable from snapshots.

### UI layout and state contract

- Team, Organisation settings, and My settings use stable compact page/workspace headers and one deliberate content scroller. Do not introduce explanatory hero cards that push the first usable row or form below the fold.
- Desktop Team keeps its workbar and table header outside the scrolling rows. A selected member inspector may scroll independently while preserving its identity/actions. Mobile uses one principal list/detail scroller rather than a compressed table.
- My settings uses one bounded form column and one principal vertical scroller on desktop and mobile. Sections appear sequentially with compact headings; there is no persistent section rail, nested section scroller, or mobile section drill-down.
- The departure impact/status route has one principal scroller and keeps exact effective date, days remaining, handover state, `Request early release`, and `Withdraw notice` available without implying that email delivery controls access. Team departure cards and lists are Owner/Admin-only and never expose another member's reason or dependency detail to ordinary members.
- Workbars follow the shared ordering: scope/view at left, search or context in the flexible middle, secondary controls next, and the primary action rightmost.
- Loading preserves row/form geometry; empty Team explains how to invite the first colleague; empty invitations do not render a large placeholder; partial profile failures show known identity without inventing labels such as truncated UUID names.
- Long organisation/member names wrap or truncate with access to the full value. Every destructive action uses an impact preview and explicit verb-led confirmation. Light/dark, reduced motion, keyboard, screen reader, 200% zoom, and 320px phone behavior are required.

## Implementation Plan

### Implemented foundation: prospective departure-policy snapshots

- Migration `00112_organisation_departure_notice_snapshots` makes the private operational departure policy live with validated `30` or `60` days (default `30`) and an independent policy version. Every post-migration canonical membership generation receives an atomic, immutable days/version/accepted-at snapshot through the retained `org_members` compatibility bridge; the bridge remains the actual creation, invitation-acceptance, and rejoin writer boundary.
- Pre-migration membership generations retain an explicit all-NULL compatibility snapshot. This preserves the absence of a historical accepted policy instead of fabricating one; later departure-case work must define any required treatment of that legacy state.
- No departure-policy setter is introduced yet. There is no current safe Organisation Operations caller, so Owner/Admin authority, idempotency, and compare-and-swap requirements remain a prerequisite of the future settings command rather than an unused RPC.

### Implemented foundation: private departure-case history

- Migration `00122_membership_departure_cases_foundation` adds private, FORCE-RLS departure-case storage bound at insert to one canonical membership generation and that member's accepted notice snapshot. It accepts only a complete validated 30/60 snapshot or an explicit all-NULL `legacy_unavailable` state, keeps the case facts immutable (including its ID), serializes state/revision changes, and prevents a second coordinator-open case for the same membership.
- There is intentionally no browser grant, RPC, coordinator, Team/My settings UI, or legacy member-removal connection. Direct authenticated reads/writes are denied. The focused disposable-database fixture and independent read-only QA passed on 2026-09-05.
- Before any update-capable departure command is introduced, harden `organisation_memberships` identity so its `org_id`/`user_id` lineage cannot drift after the insert-time departure-case fence (or replace that fence with an equivalent durable composite identity constraint). Then resume the approved typed departure/early-release command closure; do not infer its UI or legacy-removal policy while `ORG-DEPARTURE-TEAM-CONCEPT-2026-09-01` remains open.

**Current approval boundary:** the existing legacy Settings member-removal
control has no approved impact/disposition workflow and must not be connected to
the typed departure or administrative-removal commands. The fixture-only Team
and self-service departure concept at `/dev/organisation-departure-team-concept`
is tracked in
[Approval-based blockers](../../approval-based-blockers.md#org-departure-team-concept-2026-09-01--departure-and-team-impact-workflow).
Approve that fixture-only concept before replacing the live removal caller;
continue independent approved foundations in the meantime.

1. **Introduce profile and membership foundations.** Add expanded portable professional profiles, surrogate membership IDs/generations, explicit membership state, membership notice snapshots, organisation owner membership, capability definitions, constraints, timestamps, tenant-safe member projections, and self-only contribution projection contracts.
2. **Backfill ownership and profiles.** Convert each creator's current Admin membership into the explicit Owner; seed profiles from safe auth metadata through a trusted job; report missing creators, duplicate memberships, invalid roles, and organisations without exactly one eligible Owner.
3. **Replace membership RLS.** Add active-membership/capability helpers, remove self-insert and broad Admin mutation policies, and cover suspension/removed state in every tenant helper. Keep the single active/suspended organisation constraint for the pilot.
4. **Rebuild invitation commands.** Add hashed token versions, delivery limits, resend/supersession, atomic accept/reject/revoke/expire behavior, safe sign-in return flow, events, and an expiry worker.
5. **Add administration events and governed offboarding.** Implement impact projections and transactional role change, suspend, reactivate, administrative remove, departure submit/withdraw, bounded early-release request/decision, due-offboarding execution, and ownership-transfer commands with reassignment and grant reconciliation hooks. Add the midnight-IST typed maintenance coordinator, catch-up recovery, safe alerts, and durable Resend delivery effects.
6. **Build the Team workspace.** Add server-driven Members/Invitations views, search/filter/pagination, member inspector, Owner/Admin-only departure queue/cards, invitation flow, permissions, impact confirmations, mobile drill-down, and complete loading/empty/error/long-content states.
7. **Build organisation settings.** Add profile/defaults, prospective 30/60 departure-notice policy, the Trash plan's 30/60/90 automatic-retention selector, storage entitlement/usage, notification defaults, revision checks, and read-only views for ordinary members. Do not add an MFA/security-policy surface in this phase.
8. **Build My settings.** Add the single-scroll professional profile, self-only Contribution summary, departure impact/status workflow, password/email workflows, appearance, notification/digest preferences, and quiet hours/timezone. Defer MFA and active-session management.
9. **Update the shell and onboarding.** Move appearance control into the account menu, remove the unsupported workspace switcher, route Team/Settings correctly, and distinguish no-membership, invitation, removed, and suspended states.
10. **Integrate dependent domains.** Make Notes mentions, Tasks, Review, Deadlines, internal-cost participants, realtime topic access, Search, notification delivery, Trash, and signed file access consume membership/capability state and offboarding events.
11. **Isolate platform operations.** Remove tenant navigation to global Usage and hand the service-role aggregate to the Platform Operations plan before production onboarding.
12. **Cut over and contract legacy code.** Observe dual-read parity where needed, then remove `created_by` authority checks, composite/hard-delete membership assumptions, raw invite tokens, boolean notification preferences, service-role browser mutations, and page-local role logic.

## Interfaces and Data Changes

### Core tables and projections

- `user_profiles`: auth user ID, display name, professional title, short professional bio, locale, timezone, revision, and timestamps. No date of birth, avatar asset, password, MFA secret, provider token, popularity field, or productivity score.
- `user_profile_entries`: user, entry kind (`expertise`, `qualification`, `jurisdiction`, `language`, `education`, or `prior_experience`), bounded structured value/date/summary fields, display order, revision, and timestamps. Entries are self-maintained portable profile data, not verified employment claims or organisation Activity.
- `organisation_memberships`: stable membership ID, organisation/user, role, state, generation, invited-through ID, notice-days/policy-version/accepted-at snapshot, join/suspend/remove actors/reasons/timestamps, revision, and created time. One active/suspended organisation per user during the pilot and one active/suspended generation per user/organisation.
- `organisations`: retain immutable `created_by`; add current `owner_membership_id`, revision, and update metadata.
- `organisation_profiles`: names, logo asset, establishment date, tagline, locale/date format, currency, revision, and actor/timestamps.
- `organisation_operational_settings`: organisation timezone, prospective departure notice (`30` or `60`, default `30`), deadline reminder defaults, digest defaults, storage entitlement reference/read model, and revision. The implemented `organisation_retention_settings` remains the sole owner of the separate Trash 30/60/90 automatic-retention policy.
- `organisation_security_policies` is deferred; do not create an unused MFA-policy table in the initial migration.
- `organisation_invites`: normalised email, current token-hash/version, role, state, expiry, inviter, accepted user/membership, superseded/revoked/rejected data, delivery counters, revision, and timestamps.
- `organisation_invite_deliveries`: invite/version, channel/provider reference, attempt, scheduled/sent/failure state, safe error, and timestamps.
- `membership_departure_cases`: membership/organisation, snapshotted notice days/policy version, state, submitted/effective/execution/completion/withdrawal timestamps, optional bounded reason/handover note, actor, revision, idempotency, safe failure code, and immutable original effective date. At most one non-terminal case exists per membership.
- `membership_early_release_requests`: departure case, ordinal attempt (maximum three), desired effective date, optional bounded reason, state, requester/decider, decision reason, revision, and timestamps. At most one request is pending per case.
- `administration_events`: append-only actor/target snapshots, event kind/version, safe metadata, reason, correlation/idempotency, and timestamp.
- `member_capability_projection`: caller membership/role/owner overlay, capability version, effective capabilities, and state; this is a secured read model, not a client-writable ACL table.
- `member_contribution_projection`: self-only organisation/membership/window-scoped aggregates derived from canonical Task, Review, and Activity facts with definition versions; it is not a mutable counter table and is unavailable after membership loss except through separately authorised historical audit.
- `notification_preferences` and digest schedules follow the Work/Review/Notifications plan; retire `user_notification_prefs` booleans after backfill.

### Command and projection contracts

```ts
type OrganisationRole = 'admin' | 'associate' | 'viewer'
type MembershipState = 'active' | 'suspended' | 'removed'
type InviteState = 'pending' | 'accepted' | 'rejected' | 'expired' | 'revoked' | 'superseded'
type DepartureState =
  | 'submitted'
  | 'scheduled'
  | 'blocked_privileged_coverage'
  | 'executing'
  | 'completed'
  | 'withdrawn'
  | 'failed_pending_cleanup'
type EarlyReleaseState = 'pending' | 'approved' | 'declined' | 'withdrawn'

type TeamCapability =
  | 'team.view'
  | 'team.invite.standard'
  | 'team.invite.admin'
  | 'team.role.manage_standard'
  | 'team.role.manage_admin'
  | 'team.membership.suspend_standard'
  | 'team.membership.manage_admin'
  | 'team.ownership.transfer'
  | 'organisation.profile.manage'
  | 'organisation.operations.manage'
  | 'trash.purge'

type MembershipImpact = {
  membershipId: string
  revision: number
  openTasks: number
  reviewAssignments: number
  accountableDeadlines: number
  matterResponsibilities: number
  costGrants: number
  pendingInvitesCreated: number
  privilegedCoverage: 'safe' | 'last_admin' | 'owner_transfer_required'
  requiredDispositions: Array<{
    domain: 'task' | 'review' | 'deadline' | 'matter'
    sourceId: string
    allowed: Array<'reassign' | 'return_to_team' | 'block'>
  }>
}

type TeamMemberProjection = {
  membershipId: string
  profile: { displayName: string; professionalTitle?: string }
  authorisedEmail?: string
  role: OrganisationRole
  owner: boolean
  state: MembershipState
  joinedAt: string
  capabilities: TeamCapability[]
  revision: number
}

type MemberDepartureProjection = {
  caseId: string
  membershipId: string
  state: DepartureState
  noticeDaysSnapshot: 30 | 60
  originalEffectiveOn: string
  effectiveOn: string
  effectiveAt: string
  daysRemaining: number
  earlyReleaseAttemptsUsed: number
  pendingEarlyRelease?: { requestId: string; desiredEffectiveOn: string }
  impact: MembershipImpact
  revision: number
}

type MemberContributionSummary = {
  membershipId: string
  period: { from: string; to: string; timezone: string }
  definitionVersion: number
  tasksCompleted: number
  tasksCurrentlyAssigned: number
  reviewDecisionsCompleted: number
  mattersContributedTo: number
}
```

### Commands

- `organisation.create`, `organisation.profile.update`, `organisation.operations.update`
- `invitation.create`, `invitation.resend`, `invitation.revoke`, `invitation.accept`, `invitation.reject`, `invitation.expire`
- `membership.role_change`, `membership.suspend`, `membership.reactivate`, `membership.remove`, `membership.ownership_transfer`
- `membership.departure.submit`, `membership.departure.withdraw`, `membership.early_release.request`, `membership.early_release.approve`, `membership.early_release.decline`, `membership.departure.execute_due`
- `profile.update`, `preference.update`, and provider-backed password/email commands

Every mutation accepts an idempotency key and expected revision where relevant and returns a stable success/error code, changed IDs, current revision, any required work impact, and a safe user message.

### Events

- `organisation.created`, `organisation.profile_updated`, `organisation.operations_updated`
- `invitation.created`, `invitation.delivered`, `invitation.delivery_failed`, `invitation.resent`, `invitation.accepted`, `invitation.rejected`, `invitation.revoked`, `invitation.expired`
- `membership.joined`, `membership.role_changed`, `membership.suspended`, `membership.reactivated`, `membership.removed`, `membership.left`, `organisation.ownership_transferred`
- `membership.departure_submitted`, `membership.departure_withdrawn`, `membership.early_release_requested`, `membership.early_release_approved`, `membership.early_release_declined`, `membership.departure_due`, `membership.departure_completed`, `membership.departure_failed`
- private account security events for email/password changes, rendered without secrets

## Testing and Acceptance Criteria

- Every organisation has exactly one active Owner membership; `created_by` does not grant current authority after ownership transfer.
- Cross-organisation reads/writes, forged organisation/member IDs, stale revisions, inactive memberships, direct RPC calls, and browser-submitted role/capability values cannot bypass RLS or command checks.
- An authenticated user cannot insert themselves into an organisation. Invitation acceptance is the only join path besides atomic organisation creation.
- Single-organisation pilot constraints distinguish active/suspended/removed history. Removed users can later join elsewhere; suspended users and active users serving notice cannot bypass the invariant by creating/joining another tenant. Concurrent organisation creation, invitation acceptance, and rejoin fixtures prove that at most one active/suspended membership can commit; impossible pre-existing duplicates deny ordinary RPCs and surface safe repair diagnostics.
- Invite tokens are single-use hashes at rest. Resend invalidates the old URL, rate limits deterministically, and retries do not duplicate membership, Activity, notifications, or email delivery.
- Acceptance handles signed-out return, verified-email mismatch, expiry, revocation, rejection, existing/removed membership, and concurrent acceptance atomically without disclosing other tenant identity.
- Owner/Admin/Associate/Viewer capability tests cover every Team and organisation setting action. Admin cannot manage another Admin or create one; Viewer/Associate cannot invoke hidden administration commands directly.
- Role downgrade, suspension, administrative removal, departure submission/execution, and ownership transfer calculate current impact, require the applicable dispositions, reconcile tasks/Review/deadlines/grants transactionally, and preserve historical authorship.
- Departure policy accepts only 30 or 60 days and defaults to 30. New membership generations snapshot the current value/version at join; later policy changes affect only later memberships. Owner/Admin, Associate, and Viewer countdowns use their own snapshot, while Owner transfer and last-Admin coverage remain hard execution prerequisites.
- Departure submission shows the exact effective date/time and deterministic whole-day countdown to the member. Only Owner/Admin can list organisation departure cases or inspect another member's dependency card; ordinary teammates cannot infer another member's notice, reason, or counts.
- Early-release fixtures enforce at most three submissions and one pending request per case, validate a genuinely earlier date, preserve the original notice after decline, and shorten it only after an authorised approval. Withdrawal before execution cancels due work and a pending request without reversing deliberate reassignment; execution and post-completion withdrawal races resolve once.
- The 00:00 `Asia/Kolkata` coordinator claims due cases with database time, processes bounded idempotent batches, survives duplicate/missed/overlapping invocations, and catches up safely. Removal revokes access and current grants even when later cleanup fails; failure records `failed_pending_cleanup`, raises a content-safe alert, and never sends a false success email.
- Departure emails use durable deduplicated delivery intents through the Resend adapter for submission, early-release request/decision, withdrawal, seven-day/one-day reminders, completion, and operational failure. Provider retry cannot duplicate or roll back membership state, and payload tests exclude client, Matter, Task, signed URL, and secret content.
- The last eligible Admin and sole Owner invariants cannot be broken. Ownership transfer requires an eligible recipient and explicit confirmation; MFA/recent-auth enforcement is deferred until the provider-backed contract is implemented.
- Suspended/removed users are immediately denied by RLS and all authenticated loaders/actions, including Workbench signing, Search, realtime joins, notification delivery, digest schedules, and Matter-specific grants, without relying on sign-out. New signed asset issuance is blocked; already-issued short-lived signed URLs remain usable only until their bounded TTL expires.
- Personal profile data is visible only through the approved member projection. Ordinary members do not receive invitation history, security posture, suspension reasons, or unauthorised email data. The initial professional profile stores no date of birth or social graph; portable profile entries cannot expose contribution history from a former organisation.
- Contribution summaries are self-only, windowed, definition-versioned, and reconcile to canonical Task/Review/Activity facts including reopen/correction behavior. Tests reject cross-member, removed-member, cross-organisation, mutable-counter, leaderboard, productivity-score, hours-online, and peer-ranking surfaces.
- Organisation settings distinguish immutable system creation date from optional establishment date, surface the approved 30/60/90 automatic Trash retention policy without a manual/toggle alternative, and never permit tenant quota elevation or legal-hold bypass.
- Personal settings implement per-family delivery, quiet hours, verified-deadline offsets, timezone, and the approved weekly digest. Optional email and digest preferences begin off; routine processing has no notification toggle; mandatory security delivery cannot be disabled.
- Appearance supports System/Light/Dark and the existing semantic token contract without decorative transition scenes. All app animation and transitions honor `prefers-reduced-motion`; no app-specific motion toggle is stored.
- Password and email flows use the auth provider, require provider verification where appropriate, and never store or expose secrets in application tables/logs. MFA and session-management UI are absent from the initial release.
- Team desktop table and mobile drill-down retain equivalent actions, fixed-width collection badges, stable headers/workbars, deliberate scroll ownership, long-content access, and usable loading/empty/error states.
- The single-scroll settings page remains keyboard/screen-reader usable at 320px through wide desktop, 200% zoom, light/dark, and reduced motion without page-level horizontal overflow.
- The account menu contains appearance and My settings; the unsupported organisation switcher and ordinary-tenant global Usage route are absent before production cut-over.
- Additive migration reports every organisation/user/membership/invite disposition and blocks cut-over on missing Owner, duplicate active membership, unsafe raw-token migration, unresolved auth profile, or capability mismatch.

## Assumptions

- CaseChain remains in a controlled one-active-organisation-per-user pilot until multi-organisation membership has an explicit product and security plan.
- Supabase Auth remains authoritative for credentials, verified email, and sessions. Its MFA/assurance capabilities are reserved for the deferred advanced-security phase.
- The approved Work/Review/Notifications, Trash, Realtime, and Deadlines/Financials plans provide the dependent hooks referenced here.
- Platform operators are distinct from tenant Owner/Admin and cannot be represented by tenant role, a hard-coded email, or a hidden navigation item.
- Organisation deletion, domain-based auto-join, SSO/SCIM, custom roles, and arbitrary per-field ACLs are outside the initial implementation.

## Open Questions

None.
