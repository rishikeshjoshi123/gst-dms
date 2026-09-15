import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const migration = readFileSync(new URL('../../../supabase/migrations/00161_governed_standard_member_suspension.sql', import.meta.url), 'utf8')
const actions = readFileSync(new URL('../actions/org.ts', import.meta.url), 'utf8')
const workspace = readFileSync(new URL('../../app/(app)/team/TeamWorkspace.tsx', import.meta.url), 'utf8')
const shell = readFileSync(new URL('../../app/(app)/layout.tsx', import.meta.url), 'utf8')
const proxy = readFileSync(new URL('../../proxy.ts', import.meta.url), 'utf8')
const notifications = readFileSync(new URL('../actions/notifications.ts', import.meta.url), 'utf8')

test('suspension authority is exact-active, capability based, ordinary-member only, CAS and globally idempotent', () => {
  assert.match(migration, /current_active_tenant_membership\(\)/)
  assert.match(migration, /team\.membership\.suspend_standard/)
  assert.match(migration, /v_target\.role NOT IN \('associate','viewer'\)/)
  assert.match(migration, /v_target\.user_id=v_actor/)
  assert.match(migration, /v_target\.revision<>p_expected_revision/)
  assert.match(migration, /idempotency_key uuid PRIMARY KEY/)
  assert.match(migration, /actor_user_id<>v_actor/)
  assert.match(migration, /idempotency_subject_mismatch/)
  assert.match(migration, /FOR UPDATE/)
  assert.match(migration, /tasks_assignee_active_update_fence/)
  assert.match(migration, /Task assignee must be an active eligible organisation member/)
  assert.match(migration, /transition_task_pre_suspension_fence/)
  assert.match(migration, /task_transition_receipts receipt WHERE receipt\.idempotency_key=p_idempotency_key/)
  assert.ok(migration.indexOf('task_transition_receipts receipt WHERE') < migration.indexOf("IF v_command='set_assignee'"))
  assert.match(migration, /OLD\.assignee_user_id IS DISTINCT FROM NEW\.assignee_user_id/)
})

test('suspension returns only active open work to the queue and appends Task and administration evidence atomically', () => {
  assert.match(migration, /task\.status IN \('open','in_progress'\)/)
  assert.match(migration, /task\.lifecycle_state='active'/)
  assert.match(migration, /SET assignee_user_id=NULL,revision=task\.revision\+1/)
  assert.match(migration, /return_to_team_for_member_suspension/)
  assert.match(migration, /append_activity_event/)
  assert.match(migration, /organisation_membership\.suspended\.v1/)
  assert.match(migration, /state='suspended',suspended_at=now\(\),suspended_by=v_actor/)
  assert.match(migration, /REVOKE INSERT,UPDATE,DELETE ON public\.org_members FROM service_role/)
})

test('the live Team flow requires impact, bounded reason and explicit task disposition', () => {
  assert.match(actions, /get_standard_member_suspension_impact/)
  assert.match(actions, /p_task_disposition: 'return_open_tasks_to_team'/)
  assert.match(actions, /min\(3\)\.max\(500\)/)
  assert.match(workspace, /Preview suspension/)
  assert.match(workspace, /Reason for suspension/)
  assert.match(workspace, /I accept returning all/)
  assert.match(workspace, /Suspend access and return tasks/)
  assert.match(workspace, /max-h-\[calc\(100dvh-2rem\)\]/)
  assert.match(workspace, /requestAnimationFrame\(\(\) => suspendButtonRef\.current\?\.focus\(\)\)/)
  assert.match(actions, /taskImpactFingerprint/)
  assert.match(workspace, /Assigned work changed\. Review the updated impact/)
  assert.match(workspace, /inspectorHeadingRef\.current\?\.focus\(\)/)
})

test('the protected shell rechecks canonical active context and never uses legacy org_members as access', () => {
  assert.match(shell, /get_my_organisation_context/)
  assert.match(shell, /activeContexts\.length !== 1 \|\| \(contexts \?\? \[\]\)\.length !== 1/)
  assert.doesNotMatch(shell, /\.from\('org_members'\)/)
  assert.match(shell, /redirect\('\/onboarding'\)/)
  assert.match(proxy, /get_my_organisation_context/)
  assert.match(proxy, /contexts \?\? \[\]\)\.length === 1/)
  assert.match(proxy, /Next 16 request boundary/)
})

test('notification reads and mutations require canonical active membership in actions and RLS', () => {
  assert.match(migration, /DROP POLICY notifications_select/)
  assert.match(migration, /current_active_tenant_membership\(\)/)
  assert.match(notifications, /if \(!await getCurrentOrgId\(\)\) return \{ notifications: \[\], unreadCount: 0 \}/)
  assert.match(notifications, /Organisation access is unavailable\./)
})
