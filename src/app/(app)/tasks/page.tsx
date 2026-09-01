import {
  TaskReaderError,
  getTaskDetail,
  getTasks,
  getTaskTransitionHistory,
  getTaskWorkspaceContext,
  type TaskDetail,
  type TaskListItem,
  type TaskTransition,
} from '@/lib/actions/tasks'
import { TasksWorkspace } from '@/components/tasks/TasksWorkspace'
import { isTaskId } from '@/components/tasks/task-model'

export const metadata = { title: 'Tasks — GST Litigation DMS' }

export default async function TasksPage({
  searchParams,
}: {
  searchParams: Promise<{ task?: string | string[]; tab?: string | string[] }>
}) {
  const params = await searchParams
  const requestedTask = typeof params.task === 'string' ? params.task : null
  const selectedId = requestedTask
  let tasks: TaskListItem[] = []
  let detail: TaskDetail | null = null
  let history: TaskTransition[] = []
  let listReaderError = false
  let detailReaderError = false

  try {
    tasks = await getTasks()
  } catch (error) {
    if (!(error instanceof TaskReaderError)) throw error
    listReaderError = true
  }

  if (!listReaderError && selectedId && isTaskId(selectedId)) {
    try {
      const [nextDetail, nextHistory] = await Promise.all([
        getTaskDetail(selectedId),
        getTaskTransitionHistory(selectedId),
      ])
      detail = nextDetail
      history = nextHistory
    } catch (error) {
      if (!(error instanceof TaskReaderError)) throw error
      detailReaderError = true
    }
  }

  const context = await getTaskWorkspaceContext({
    clientIds: [...tasks.flatMap((task) => task.client_id ? [task.client_id] : []), ...(detail?.client_id ? [detail.client_id] : [])],
    matterIds: [...tasks.flatMap((task) => task.matter_id ? [task.matter_id] : []), ...(detail?.matter_id ? [detail.matter_id] : [])],
    documentIds: [...tasks.flatMap((task) => task.document_id ? [task.document_id] : []), ...(detail?.document_id ? [detail.document_id] : [])],
  })

  if (!context) {
    return <div className="grid min-h-64 place-items-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6 text-center"><div><h1 className="text-section-heading">Tasks unavailable</h1><p className="mt-2 text-sm text-[var(--text-muted)]">No active organisation is available for this account.</p></div></div>
  }

  return (
    <TasksWorkspace
      initialTasks={tasks}
      initialSelectedId={selectedId}
      initialDetail={detail}
      initialHistory={history}
      initialListReaderError={listReaderError}
      initialDetailReaderError={detailReaderError}
      context={context}
    />
  )
}
