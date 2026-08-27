---
title: Organisation Administration, Team Access, and Personal Settings
status: proposed
created: 2026-08-26
updated: 2026-08-27
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

Tenant access becomes capability-driven and auditable. Owner is an explicit, transferable authority rather than an inference from `created_by`; membership removal preserves history instead of hard-deleting it; invitation acceptance is atomic and token-safe; and role, suspension, removal, and Matter-specific grants are reconciled in one transaction. CaseChain retains one active organisation per ordinary user during the controlled pilot and removes the misleading workspace-switching affordance until multi-organisation membership receives a separate plan.

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
- Replace `/settings` with one vertically scrollable personal settings page. It renders compact `Personal profile`, `Account access`, `Appearance`, `Direct email`, and `Weekly digest` sections in that order; it has no section rail, section-switching route, or standalone Security page.
- Add organisation-scoped settings under `/settings/organisation/profile` and `/settings/organisation/operations`. Owner/Admin can edit authorised fields; other active members receive the small read-only organisation profile only and do not see privileged operational policy details. Do not expose an organisation Security/MFA tab in the initial release.
- The account menu shows user identity, current organisation and role, `My settings`, the light/dark/system appearance control, and `Sign out`. Theme control moves out of the global top bar. Destructive or administrative organisation actions do not live in the account menu.
- Team belongs in the main organisation navigation. Organisation settings are reachable from Team and My settings but do not become another high-frequency rail item.
- During the one-organisation pilot, remove the workspace switcher and label the current tenant as `Organisation`. A later multi-organisation plan may restore switching against the same membership identity contract.
- Platform administration is a separate trust domain and route tree. `/usage` must not remain an ordinary tenant route or rely on a special email/password convention; its migration belongs to the Platform Operations plan.

### One-organisation pilot and future compatibility

- One ordinary user may have exactly one active or suspended organisation membership during the controlled pilot. A removed membership does not block the user from accepting or creating a membership elsewhere.
- A suspended member cannot create or join another organisation to bypass suspension. Sign-in leads to a non-disclosing `Access suspended` state with organisation contact guidance.
- Historical membership generations use stable surrogate IDs. Rejoining an organisation after removal creates a new membership generation rather than resurrecting or overwriting the old audit record.
- Domain APIs accept an explicit organisation context and never depend on the single-organisation constraint for authorisation. This preserves a deliberate migration path if multi-organisation membership is approved later.

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
| Change Associate/Viewer role | Yes | Yes | No | No |
| Suspend/reactivate/remove Associate/Viewer | Yes | Yes | No | No |
| Change, suspend, or remove an Admin | Yes | No | No | No |
| Transfer ownership | Yes | No | No | No |
| Permanently purge eligible Trash | Yes | Yes | No | No |
| Edit personal settings | Self | Self | Self | Self |

- An Admin cannot create another Admin, demote/remove an Admin, transfer ownership, or weaken an Owner-only safeguard. Owner actions requiring elevated consequence use recent authentication and typed confirmation where specified.
- Associates and Viewers may leave the organisation after an impact preview. Admins may leave only after the Owner resolves their privileged role and any sole-admin dependency. The Owner must transfer ownership before leaving.
- Feature-specific access remains the intersection of tenant role, resource access, and explicit grant. A Matter financial-cost grant can narrow or reveal that ledger as already approved, but cannot elevate a Viewer to edit or confer administration.

### Membership lifecycle and offboarding

- Membership state is separate from role: `active`, `suspended`, or `removed`. Invitation state is not a membership state.
- Suspension is reversible and immediately blocks tenant reads, writes, realtime joins, signed asset access, Search, notifications, email digests, and worker actions for that member. Existing authored content remains attributed and readable according to other users' access.
- Reactivation restores the role that remained valid at suspension time but does not automatically restore feature grants that were explicitly revoked during review.
- Removal is durable offboarding, not row deletion. It immediately revokes tenant access, personal delivery schedules, realtime eligibility, open signed URLs, and Matter-specific grants. Historical notes, decisions, activity, and audit render from member/profile snapshots without exposing removed users to current data.
- Before suspension, removal, role downgrade, or self-leave, return an impact projection covering open tasks, Review assignments, verified deadlines, Matter responsibility, internal-cost grants, pending invitations sent by the member, scheduled digests, and privileged-role coverage.
- Consequential open work must receive an explicit disposition in the command: reassign to an eligible active member, return to the team/unassigned queue where the owning domain permits it, or block the change where an accountable owner is mandatory. No command silently marks work complete.
- Role downgrade or membership loss revokes incompatible Matter grants in the same transaction. Every feature still recalculates effective capability on read/write so stale rows or clients cannot preserve access.
- Suspending or removing the last eligible Admin is blocked. Transferring ownership verifies that the recipient is an active Admin; additional MFA policy is deferred and cannot be assumed by the initial command.

### Team directory and member profiles

- Add a tenant-safe global `user_profiles` record keyed by auth user ID with display name and optional professional title. Authentication email remains owned by Supabase Auth and is exposed through a secured member projection rather than copied into arbitrary feature tables.
- The pilot does not accept profile-image uploads or store avatar assets. Use one shared Unicode-aware initials formatter: the first grapheme of the first and last non-empty name tokens, the first two graphemes for a single-token name, and a neutral user icon when no usable display name exists. Initials are derived at render/projection time and update with the display name.
- Active organisation members can see teammates' display name, derived initials, role, and professional title for collaboration and mentions. Email address, invitation history, suspension detail, and security posture are restricted to the member themselves and authorised administrators.
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

- Organisation profile fields are: display name, optional registered name, optional logo asset, optional establishment date, optional short tagline, default timezone, locale/date format, and default currency. India-first defaults are `Asia/Kolkata`, `en-IN`, and `INR`.
- `created_at` is immutable system metadata. `established_on` is optional historical information supplied by the organisation and is never presented as the account creation date.
- The tagline is limited to restrained organisation/profile and invitation contexts; it does not consume Matter headers, Today, loading screens, or operational workspaces.
- Do not create AI-generated motivational quotes, a rotating quote table, or background quote-refresh jobs. They add cost and distraction without helping legal work. A later content feature would require evidence of user value.
- Operations settings own the already approved Trash retention options (`Manual purge only`, 30, 60, 90, 180, or 365 days), auto-purge off by default, organisation timezone, default deadline reminder policy, weekly digest defaults, and read-only storage entitlement/usage.
- Tenant administrators can choose retention within the approved policy but cannot raise platform quota, change provider pricing, see other organisations, or bypass legal holds. Initial storage entitlement remains the separately approved 100 MB of unique assets.
- Organisation defaults seed new personal preferences; they cannot force non-mandatory email on an existing user. Mandatory access/security delivery remains governed by the notification plan.
- Organisation deletion/closure is not an ordinary Settings action in the initial release. It requires a separate, support-visible, retention-aware closure design and is not implemented as a cascading delete.

### Personal settings

- `Personal profile` owns display name, professional title, locale, and personal timezone. It previews the derived initials but has no photo-upload action. Email change is a Supabase Auth verification workflow, not an ordinary profile field mutation.
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
- Remove the current RLS path that permits `org_members` self-insertion. A membership can be created only through organisation creation or validated invitation acceptance.
- Central capability definitions are versioned and tested. Feature pages consume `capabilities: string[]`; they do not maintain their own Admin/Associate/Viewer matrices.
- Service-role access is restricted to trusted email/outbox workers, expiry jobs, backfills, and platform operations. It cannot be used as a shortcut for an ordinary browser mutation.
- Material administration commands write their source change, append-only administration event, user-facing Activity event where appropriate, and transactional outbox record atomically.
- Error responses are stable and non-disclosing: unauthenticated, access suspended, not permitted, stale revision, last-admin blocked, work-reassignment required, invite expired/revoked, rate limited, and recent authentication required.

### Activity, security audit, and notification effects

- Organisation Activity receives human-useful events such as member joined, role changed, member suspended/reactivated/removed, ownership transferred, and organisation profile/policy changed. It does not expose raw invite tokens, MFA detail, provider payloads, or unnecessary email addresses.
- An Admin-only administration audit retains invitation lifecycle, capability/role changes, operational-policy changes, and access removal with actor, target snapshot, reason, correlation ID, and timestamp. It is a backend audit contract in the initial release, not a dedicated settings screen.
- Direct invitations, role/access changes, suspension/reactivation/removal, ownership transfer, and password/email changes create the approved addressed notifications. Reading one does not undo or accept the change.
- Member removal cancels future personal delivery, digest schedules, and direct unread projections that no longer have an authorised target. Historical Activity remains renderable from snapshots.

### UI layout and state contract

- Team, Organisation settings, and My settings use stable compact page/workspace headers and one deliberate content scroller. Do not introduce explanatory hero cards that push the first usable row or form below the fold.
- Desktop Team keeps its workbar and table header outside the scrolling rows. A selected member inspector may scroll independently while preserving its identity/actions. Mobile uses one principal list/detail scroller rather than a compressed table.
- My settings uses one bounded form column and one principal vertical scroller on desktop and mobile. Sections appear sequentially with compact headings; there is no persistent section rail, nested section scroller, or mobile section drill-down.
- Workbars follow the shared ordering: scope/view at left, search or context in the flexible middle, secondary controls next, and the primary action rightmost.
- Loading preserves row/form geometry; empty Team explains how to invite the first colleague; empty invitations do not render a large placeholder; partial profile failures show known identity without inventing labels such as truncated UUID names.
- Long organisation/member names wrap or truncate with access to the full value. Every destructive action uses an impact preview and explicit verb-led confirmation. Light/dark, reduced motion, keyboard, screen reader, 200% zoom, and 320px phone behavior are required.

## Implementation Plan

1. **Introduce profile and membership foundations.** Add `user_profiles`, surrogate membership IDs/generations, explicit membership state, organisation owner membership, capability definitions, constraints, timestamps, and tenant-safe member projections.
2. **Backfill ownership and profiles.** Convert each creator's current Admin membership into the explicit Owner; seed profiles from safe auth metadata through a trusted job; report missing creators, duplicate memberships, invalid roles, and organisations without exactly one eligible Owner.
3. **Replace membership RLS.** Add active-membership/capability helpers, remove self-insert and broad Admin mutation policies, and cover suspension/removed state in every tenant helper. Keep the single active/suspended organisation constraint for the pilot.
4. **Rebuild invitation commands.** Add hashed token versions, delivery limits, resend/supersession, atomic accept/reject/revoke/expire behavior, safe sign-in return flow, events, and an expiry worker.
5. **Add administration events and offboarding.** Implement impact projections and transactional role change, suspend, reactivate, remove, leave, and ownership-transfer commands with reassignment and grant reconciliation hooks.
6. **Build the Team workspace.** Add server-driven Members/Invitations views, search/filter/pagination, member inspector, invitation flow, permissions, impact confirmations, mobile drill-down, and complete loading/empty/error/long-content states.
7. **Build organisation settings.** Add profile/defaults, retention/auto-purge controls from the Trash plan, storage entitlement/usage, notification defaults, revision checks, and read-only views for ordinary members. Do not add an MFA/security-policy surface in this phase.
8. **Build My settings.** Add the single-scroll profile, password/email workflows, appearance, notification/digest preferences, and quiet hours/timezone. Defer MFA and active-session management.
9. **Update the shell and onboarding.** Move appearance control into the account menu, remove the unsupported workspace switcher, route Team/Settings correctly, and distinguish no-membership, invitation, removed, and suspended states.
10. **Integrate dependent domains.** Make Notes mentions, Tasks, Review, Deadlines, internal-cost participants, realtime topic access, Search, notification delivery, Trash, and signed file access consume membership/capability state and offboarding events.
11. **Isolate platform operations.** Remove tenant navigation to global Usage and hand the service-role aggregate to the Platform Operations plan before production onboarding.
12. **Cut over and contract legacy code.** Observe dual-read parity where needed, then remove `created_by` authority checks, composite/hard-delete membership assumptions, raw invite tokens, boolean notification preferences, service-role browser mutations, and page-local role logic.

## Interfaces and Data Changes

### Core tables and projections

- `user_profiles`: auth user ID, display name, professional title, locale, timezone, revision, and timestamps. No avatar asset, password, MFA secret, or provider token.
- `organisation_memberships`: stable membership ID, organisation/user, role, state, generation, invited-through ID, join/suspend/remove actors/reasons/timestamps, revision, and created time. One active/suspended organisation per user during the pilot and one active/suspended generation per user/organisation.
- `organisations`: retain immutable `created_by`; add current `owner_membership_id`, revision, and update metadata.
- `organisation_profiles`: names, logo asset, establishment date, tagline, timezone, locale/date format, currency, revision, and actor/timestamps.
- `organisation_operational_settings`: retention policy reference, auto-purge, deadline reminder defaults, digest defaults, storage entitlement reference/read model, and revision.
- `organisation_security_policies` is deferred; do not create an unused MFA-policy table in the initial migration.
- `organisation_invites`: normalised email, current token-hash/version, role, state, expiry, inviter, accepted user/membership, superseded/revoked/rejected data, delivery counters, revision, and timestamps.
- `organisation_invite_deliveries`: invite/version, channel/provider reference, attempt, scheduled/sent/failure state, safe error, and timestamps.
- `administration_events`: append-only actor/target snapshots, event kind/version, safe metadata, reason, correlation/idempotency, and timestamp.
- `member_capability_projection`: caller membership/role/owner overlay, capability version, effective capabilities, and state; this is a secured read model, not a client-writable ACL table.
- `notification_preferences` and digest schedules follow the Work/Review/Notifications plan; retire `user_notification_prefs` booleans after backfill.

### Command and projection contracts

```ts
type OrganisationRole = 'admin' | 'associate' | 'viewer'
type MembershipState = 'active' | 'suspended' | 'removed'
type InviteState = 'pending' | 'accepted' | 'rejected' | 'expired' | 'revoked' | 'superseded'

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
```

### Commands

- `organisation.create`, `organisation.profile.update`, `organisation.operations.update`
- `invitation.create`, `invitation.resend`, `invitation.revoke`, `invitation.accept`, `invitation.reject`, `invitation.expire`
- `membership.role_change`, `membership.suspend`, `membership.reactivate`, `membership.remove`, `membership.leave`, `membership.ownership_transfer`
- `profile.update`, `preference.update`, and provider-backed password/email commands

Every mutation accepts an idempotency key and expected revision where relevant and returns a stable success/error code, changed IDs, current revision, any required work impact, and a safe user message.

### Events

- `organisation.created`, `organisation.profile_updated`, `organisation.operations_updated`
- `invitation.created`, `invitation.delivered`, `invitation.delivery_failed`, `invitation.resent`, `invitation.accepted`, `invitation.rejected`, `invitation.revoked`, `invitation.expired`
- `membership.joined`, `membership.role_changed`, `membership.suspended`, `membership.reactivated`, `membership.removed`, `membership.left`, `organisation.ownership_transferred`
- private account security events for email/password changes, rendered without secrets

## Testing and Acceptance Criteria

- Every organisation has exactly one active Owner membership; `created_by` does not grant current authority after ownership transfer.
- Cross-organisation reads/writes, forged organisation/member IDs, stale revisions, inactive memberships, direct RPC calls, and browser-submitted role/capability values cannot bypass RLS or command checks.
- An authenticated user cannot insert themselves into an organisation. Invitation acceptance is the only join path besides atomic organisation creation.
- Single-organisation pilot constraints distinguish active/suspended/removed history. Removed users can later join elsewhere; suspended users cannot bypass suspension by creating/joining another tenant.
- Invite tokens are single-use hashes at rest. Resend invalidates the old URL, rate limits deterministically, and retries do not duplicate membership, Activity, notifications, or email delivery.
- Acceptance handles signed-out return, verified-email mismatch, expiry, revocation, rejection, existing/removed membership, and concurrent acceptance atomically without disclosing other tenant identity.
- Owner/Admin/Associate/Viewer capability tests cover every Team and organisation setting action. Admin cannot manage another Admin or create one; Viewer/Associate cannot invoke hidden administration commands directly.
- Role downgrade, suspension, removal, self-leave, and ownership transfer calculate current impact, require explicit dispositions, reconcile tasks/Review/deadlines/grants transactionally, and preserve historical authorship.
- The last eligible Admin and sole Owner invariants cannot be broken. Ownership transfer requires an eligible recipient and explicit confirmation; MFA/recent-auth enforcement is deferred until the provider-backed contract is implemented.
- Suspended/removed access disappears immediately from RLS, Workbench signing, Search, realtime joins, notification delivery, digest schedules, and Matter-specific grants without relying on sign-out.
- Personal profile data is visible only through the approved member projection. Ordinary members do not receive invitation history, security posture, suspension reasons, or unauthorised email data.
- Organisation settings distinguish immutable system creation date from optional establishment date, enforce approved retention values, keep auto-purge off initially, and never permit tenant quota elevation or legal-hold bypass.
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
