import type { TaskDetail, TaskListItem, TaskStatus } from '@/lib/actions/tasks'

export type TaskStatusFilter = 'active' | 'all' | TaskStatus
export type TaskAssignmentFilter = 'all' | 'mine' | 'unassigned'
export type TaskWorkspaceTab = 'details' | 'comments'

export type TaskDetailReadState = 'idle' | 'loading' | 'ready' | 'unavailable' | 'error'

const TASK_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isTaskId(value: string) {
  return TASK_ID_PATTERN.test(value)
}

export function taskDetailReadState(input: {
  selectedId: string | null
  detail: TaskDetail | null
  loading: boolean
  readerError: boolean
}): TaskDetailReadState {
  if (!input.selectedId) return 'idle'
  if (input.loading) return 'loading'
  if (input.readerError) return 'error'
  return input.detail ? 'ready' : 'unavailable'
}

export const taskStatusLabels: Record<TaskStatus, string> = {
  open: 'Open',
  in_progress: 'In progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
  suspended: 'Suspended',
}

export const taskStatusVariants: Record<TaskStatus, 'default' | 'success' | 'muted' | 'warning'> = {
  open: 'default',
  in_progress: 'warning',
  completed: 'success',
  cancelled: 'muted',
  suspended: 'warning',
}

export function isActiveTask(status: TaskStatus) {
  return status === 'open' || status === 'in_progress'
}

export function filterTasks(
  tasks: TaskListItem[],
  input: {
    query: string
    status: TaskStatusFilter
    assignment: TaskAssignmentFilter
    currentUserId: string
    labels: Array<string | null | undefined>
  },
) {
  const query = input.query.trim().toLocaleLowerCase()
  return tasks.filter((task, index) => {
    const matchesQuery = !query || `${task.title} ${input.labels[index] ?? ''}`.toLocaleLowerCase().includes(query)
    const matchesStatus = input.status === 'all'
      || (input.status === 'active' ? isActiveTask(task.status) : task.status === input.status)
    const matchesAssignment = input.assignment === 'all'
      || (input.assignment === 'mine' ? task.assignee_user_id === input.currentUserId : !task.assignee_user_id)
    return matchesQuery && matchesStatus && matchesAssignment
  })
}

export function taskHref(taskId: string, tab: TaskWorkspaceTab = 'details') {
  return `/tasks?task=${encodeURIComponent(taskId)}&tab=${tab}`
}

export function taskDetailsHref(taskId: string) {
  return taskHref(taskId, 'details')
}

export function notesOriginHref(noteId: string) {
  return `/notes?note=${encodeURIComponent(noteId)}`
}

export function primaryTaskCommand(status: TaskStatus) {
  if (status === 'open') return { command: 'start' as const, label: 'Start task' }
  if (status === 'in_progress') return { command: 'complete' as const, label: 'Complete task' }
  if (status === 'completed' || status === 'cancelled') return { command: 'reopen' as const, label: 'Reopen task' }
  return null
}

export function isTaskWorkspaceTab(value: string | null | undefined): value is TaskWorkspaceTab {
  return value === 'details' || value === 'comments'
}

export function mentionedUserIdsInBody(
  body: string,
  selectedMentions: Array<{ id: string; label: string }>,
) {
  return [...new Set(selectedMentions
    .filter((mention) => body.includes(`@${mention.label}`))
    .map((mention) => mention.id))]
}
