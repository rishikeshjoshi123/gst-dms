import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import {
  isOpenMatter,
  legacyStatusForMatterState,
  matterStateFromLegacy,
  normalizeMatterState,
} from './matter-state'

test('legacy statuses have the deterministic additive mapping', () => {
  assert.deepEqual(matterStateFromLegacy('active'), { work_state: 'active', current_forum: 'adjudication' })
  assert.deepEqual(matterStateFromLegacy('stayed'), { work_state: 'stayed', current_forum: 'adjudication' })
  assert.deepEqual(matterStateFromLegacy('disposed'), { work_state: 'disposed', current_forum: 'adjudication' })
  assert.deepEqual(matterStateFromLegacy('appeal_pending'), { work_state: 'active', current_forum: 'first_appeal' })
  assert.deepEqual(matterStateFromLegacy('tribunal'), { work_state: 'active', current_forum: 'tribunal' })
  assert.deepEqual(matterStateFromLegacy('high_court'), { work_state: 'active', current_forum: 'high_court' })
  assert.deepEqual(matterStateFromLegacy('supreme_court'), { work_state: 'active', current_forum: 'supreme_court' })
  assert.deepEqual(matterStateFromLegacy('closed'), { work_state: 'closed', current_forum: 'other' })
})

test('typed columns win while the compatibility status remains deterministic', () => {
  assert.deepEqual(
    normalizeMatterState({ status: 'closed', work_state: 'active', current_forum: 'remand' }),
    { status: 'active', work_state: 'active', current_forum: 'remand' },
  )
  assert.equal(legacyStatusForMatterState('active', 'first_appeal'), 'appeal_pending')
  assert.equal(legacyStatusForMatterState('active', 'other'), 'active')
  assert.equal(legacyStatusForMatterState('closed', 'supreme_court'), 'closed')
})

test('open-matter interpretation is based on work state, not legacy forum values', () => {
  assert.equal(isOpenMatter({ status: 'tribunal' }), true)
  assert.equal(isOpenMatter({ work_state: 'stayed', current_forum: 'high_court' }), true)
  assert.equal(isOpenMatter({ work_state: 'disposed', current_forum: 'tribunal' }), false)
  assert.equal(isOpenMatter({ work_state: 'closed', current_forum: 'other' }), false)
})

test('live matter lists, client counts, workspace, details, and Trash use typed state', async () => {
  const [matterActions, clientActions, list, clientPage, shell, details, trash] = await Promise.all([
    readFile(new URL('../actions/matter.ts', import.meta.url), 'utf8'),
    readFile(new URL('../actions/client.ts', import.meta.url), 'utf8'),
    readFile(new URL('../../app/(app)/matters/MattersClientView.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../../app/(app)/clients/[id]/page.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../../components/matters/MatterWorkspaceShell.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../../components/matters/MatterDetailsTab.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../trash/exact-resource.ts', import.meta.url), 'utf8'),
  ])

  assert.match(matterActions, /normalizeMatterState/)
  assert.match(clientActions, /matters\(id, status, work_state, current_forum\)/)
  assert.match(clientActions, /filter\(isOpenMatter\)/)
  for (const source of [list, clientPage, shell, details]) {
    assert.match(source, /work_state/)
    assert.match(source, /current_forum/)
    assert.doesNotMatch(source, /matter\.status/)
  }
  assert.match(trash, /normalizeMatterState/)
})
