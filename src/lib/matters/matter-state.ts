import type { MatterStatus } from '@/lib/constants'

export const MATTER_WORK_STATES = ['active', 'stayed', 'disposed', 'closed'] as const
export type MatterWorkState = (typeof MATTER_WORK_STATES)[number]

export const MATTER_CURRENT_FORUMS = [
  'adjudication',
  'first_appeal',
  'tribunal',
  'high_court',
  'supreme_court',
  'remand',
  'other',
] as const
export type MatterCurrentForum = (typeof MATTER_CURRENT_FORUMS)[number]

export const MATTER_WORK_STATE_LABELS: Record<MatterWorkState, string> = {
  active: 'Active',
  stayed: 'Stayed',
  disposed: 'Disposed',
  closed: 'Closed',
}

export const MATTER_CURRENT_FORUM_LABELS: Record<MatterCurrentForum, string> = {
  adjudication: 'Adjudication',
  first_appeal: 'First appeal',
  tribunal: 'Tribunal',
  high_court: 'High Court',
  supreme_court: 'Supreme Court',
  remand: 'Remand',
  other: 'Other / not recorded',
}

export type MatterStateSource = {
  status?: MatterStatus | string | null
  work_state?: MatterWorkState | string | null
  current_forum?: MatterCurrentForum | string | null
}

export type NormalizedMatterState = {
  work_state: MatterWorkState
  current_forum: MatterCurrentForum
  status: MatterStatus
}

export function matterStateFromLegacy(status: MatterStatus | string | null | undefined): Pick<NormalizedMatterState, 'work_state' | 'current_forum'> {
  switch (status) {
    case 'stayed': return { work_state: 'stayed', current_forum: 'adjudication' }
    case 'disposed': return { work_state: 'disposed', current_forum: 'adjudication' }
    case 'appeal_pending': return { work_state: 'active', current_forum: 'first_appeal' }
    case 'tribunal': return { work_state: 'active', current_forum: 'tribunal' }
    case 'high_court': return { work_state: 'active', current_forum: 'high_court' }
    case 'supreme_court': return { work_state: 'active', current_forum: 'supreme_court' }
    case 'closed': return { work_state: 'closed', current_forum: 'other' }
    case 'active':
    default: return { work_state: 'active', current_forum: 'adjudication' }
  }
}

export function legacyStatusForMatterState(workState: MatterWorkState, currentForum: MatterCurrentForum): MatterStatus {
  if (workState === 'stayed') return 'stayed'
  if (workState === 'disposed') return 'disposed'
  if (workState === 'closed') return 'closed'
  switch (currentForum) {
    case 'first_appeal': return 'appeal_pending'
    case 'tribunal': return 'tribunal'
    case 'high_court': return 'high_court'
    case 'supreme_court': return 'supreme_court'
    default: return 'active'
  }
}

export function normalizeMatterState<T extends MatterStateSource>(matter: T): T & NormalizedMatterState {
  const legacy = matterStateFromLegacy(matter.status)
  const work_state = MATTER_WORK_STATES.includes(matter.work_state as MatterWorkState)
    ? matter.work_state as MatterWorkState
    : legacy.work_state
  const current_forum = MATTER_CURRENT_FORUMS.includes(matter.current_forum as MatterCurrentForum)
    ? matter.current_forum as MatterCurrentForum
    : legacy.current_forum

  return {
    ...matter,
    work_state,
    current_forum,
    status: legacyStatusForMatterState(work_state, current_forum),
  }
}

export function isOpenMatter(matter: MatterStateSource): boolean {
  const { work_state } = normalizeMatterState(matter)
  return work_state === 'active' || work_state === 'stayed'
}
