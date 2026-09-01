'use server'

import { randomUUID } from 'node:crypto'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import type { Database } from '@/lib/supabase/database.types'

export type TaskStatus = Database['public']['Enums']['task_status']
export type TaskCommand =
  | 'start'
  | 'complete'
  | 'reopen'
  | 'cancel'
  | 'set_assignee'
  | 'set_due_date'
  | 'clear_due_date'

export type TaskListItem = Database['public']['Functions']['get_my_tasks']['Returns'][number]
export type TaskDetail = Database['public']['Functions']['get_task_detail']['Returns'][number]
export type TaskTransition = Database['public']['Functions']['get_task_transition_history']['Returns'][number]

export class TaskReaderError extends Error {
  readonly code = 'task_reader_unavailable'

  constructor() {
    super('Task data is temporarily unavailable.')
  }
}

export type TaskWorkspaceContext = {
  currentUserId: string
  canManage: boolean
  people: Array<{ id: string; label: string; canBeAssigned: boolean }>
  clients: Record<string, string>
  matters: Record<string, string>
  documents: Record<string, string>
}

export async function getTasks(statuses?: TaskStatus[]) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_my_tasks', {
    p_statuses: statuses,
    p_limit: 100,
    p_offset: 0,
  })
  if (error) {
    console.error('getTasks error:', error)
    throw new TaskReaderError()
  }
  return data ?? []
}

export async function getTaskDetail(taskId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_task_detail', { p_task_id: taskId })
  if (error) {
    console.error('getTaskDetail error:', error)
    throw new TaskReaderError()
  }
  return data?.[0] ?? null
}

export async function getTaskTransitionHistory(taskId: string) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_task_transition_history', { p_task_id: taskId })
  if (error) {
    console.error('getTaskTransitionHistory error:', error)
    throw new TaskReaderError()
  }
  return data ?? []
}

/**
 * Resolve non-Task display context without exposing private Task tables to the
 * UI. Every resource lookup remains scoped to the caller's verified active
 * organisation; Task fields themselves continue to come only from Task RPCs.
 */
export async function getTaskWorkspaceContext(input: {
  clientIds?: string[]
  matterIds?: string[]
  documentIds?: string[]
} = {}): Promise<TaskWorkspaceContext | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return null

  const { data: members, error: membersError } = await supabase.rpc('get_task_workspace_members')
  const caller = members?.[0]
  if (membersError || !caller || caller.current_user_id !== user.id) return null

  const people = (members ?? []).map((member) => ({
    id: member.member_user_id,
    label: member.display_name || `Team member (${member.member_user_id.slice(0, 8)})`,
    canBeAssigned: member.can_be_assigned,
  }))

  const clientIds = [...new Set(input.clientIds ?? [])]
  const matterIds = [...new Set(input.matterIds ?? [])]
  const documentIds = [...new Set(input.documentIds ?? [])]
  const [clientResult, matterResult, documentResult] = await Promise.all([
    clientIds.length
      ? supabase.from('clients').select('id, name').eq('record_state', 'active').is('deleted_at', null).in('id', clientIds)
      : Promise.resolve({ data: [] }),
    matterIds.length
      ? supabase.from('matters').select('id, title').eq('record_state', 'active').is('deleted_at', null).in('id', matterIds)
      : Promise.resolve({ data: [] }),
    documentIds.length
      ? supabase.from('documents').select('id, display_title, reference_number, storage_path').eq('record_state', 'active').is('deleted_at', null).in('id', documentIds)
      : Promise.resolve({ data: [] }),
  ])

  return {
    currentUserId: user.id,
    canManage: caller.can_manage,
    people,
    clients: Object.fromEntries((clientResult.data ?? []).map((client) => [client.id, client.name])),
    matters: Object.fromEntries((matterResult.data ?? []).map((matter) => [matter.id, matter.title])),
    documents: Object.fromEntries((documentResult.data ?? []).map((document) => [
      document.id,
      document.display_title || document.reference_number || document.storage_path?.split('/').pop() || 'Document',
    ])),
  }
}

export async function getNoteTaskSummaries(noteIds: string[]) {
  if (noteIds.length === 0) return []
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_note_task_summaries', { p_note_ids: noteIds })
  if (error) {
    console.error('getNoteTaskSummaries error:', error)
    return []
  }
  return data ?? []
}

export async function transitionTask(input: {
  taskId: string
  command: TaskCommand
  expectedRevision: number
  assigneeUserId?: string | null
  dueDate?: string | null
  idempotencyKey?: string
}) {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('transition_task', {
    p_task_id: input.taskId,
    p_command: input.command,
    p_expected_revision: input.expectedRevision,
    p_idempotency_key: input.idempotencyKey ?? randomUUID(),
    p_assignee_user_id: input.assigneeUserId ?? undefined,
    p_due_date: input.dueDate ?? undefined,
  })
  const result = data?.[0]
  if (
    error || !result || result.code !== 'ok'
    || !result.task_id || result.revision === null || result.status === null
  ) {
    const messages: Record<string, string> = {
      conflict: 'This task changed. Refresh it before trying again.',
      context_unavailable: 'This task is unavailable because its source context is no longer active.',
      invalid_assignee: 'Choose an active operational team member.',
      invalid_transition: 'That action is not available for the task’s current status.',
      not_allowed: 'You do not have permission to change this task.',
      idempotency_conflict: 'This submission key was already used for another task action.',
      invalid_request: 'This task action is invalid.',
      invalid_timezone: 'The organisation task timezone is unavailable.',
      not_found: 'This task is no longer available.',
    }
    return {
      error: messages[result?.code ?? ''] ?? 'Unable to update this task.',
      code: result?.code ?? 'request_failed',
      currentRevision: result?.revision ?? null,
      currentStatus: result?.status ?? null,
    }
  }

  revalidatePath('/tasks')
  return {
    success: true,
    task: {
      ...result,
      task_id: result.task_id,
      revision: result.revision,
      status: result.status,
    },
  }
}
