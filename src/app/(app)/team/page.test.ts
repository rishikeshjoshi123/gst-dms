import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('Team page normalizes URL input before reading and rendering', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')
  assert.match(source, /normalizeTeamDirectoryParams\(query\)/)
  assert.match(source, /getTeamDirectory\(normalizedQuery\)/)
  assert.match(source, /get_my_organisation_context/)
  assert.match(source, /capabilities\.includes\('team\.invite\.standard'\)/)
  assert.match(source, /get_organisation_invites/)
  assert.match(source, /p_state: invitationState/)
  assert.match(source, /activeContexts\.length === 1/)
  assert.match(source, /requestedView === 'invitations' && !canAdministerInvitations \? 'members'/)
  assert.doesNotMatch(source, /as TeamDirectoryParams/)
})

test('personal Settings does not read or administer organisation invitations', () => {
  const page = readFileSync(new URL('../settings/page.tsx', import.meta.url), 'utf8')
  const client = readFileSync(new URL('../settings/SettingsClient.tsx', import.meta.url), 'utf8')
  assert.doesNotMatch(page, /get_organisation_invites|pendingInvites/)
  assert.doesNotMatch(client, /inviteMember|resendInvite|deleteInvite|revokeInvite|Invitations/)
})
