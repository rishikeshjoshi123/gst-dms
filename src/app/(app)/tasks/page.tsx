import {
  getTaskCommentThread,
  getTaskComments,
  getTaskDetail,
  getTasks,
  getTaskTransitionHistory,
  getTaskWorkspaceContext,
  type TaskDetail,
  type TaskComment,
  type TaskCommentThread,
  type TaskListItem,
  type TaskTransition,
} from '@/lib/actions/tasks'
import { TaskReaderError } from '@/lib/tasks/task-reader-error'
import { TasksWorkspace } from '@/components/tasks/TasksWorkspace'
import { isTaskId, isTaskWorkspaceTab } from '@/components/tasks/task-model'

export const metadata = { title: 'Tasks — GST Litigation DMS' }

export default async function TasksPage({
  searchParams,
}: {
  searchParams: Promise<{ task?: string | string[]; tab?: string | string[] }>
}) {
  const params = await searchParams
  const requestedTask = typeof params.task === 'string' ? params.task : null
  const selectedId = requestedTask
  const requestedTab = typeof params.tab === 'string' ? params.tab : null
  const initialTab = isTaskWorkspaceTab(requestedTab) ? requestedTab : 'details'
  let tasks: TaskListItem[] = []
  let detail: TaskDetail | null = null
  let history: TaskTransition[] = []
  let commentThread: TaskCommentThread | null = null
  const comments: TaskComment[] = []
  let commentsLoaded = false
  let commentsReaderError = false
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
      if (detail && initialTab === 'comments') {
        try {
          commentThread = await getTaskCommentThread(selectedId)
          if (commentThread) {
            let afterSequence = 0
            while (afterSequence < commentThread.latest_sequence) {
              const page = await getTaskComments({ taskId: selectedId, afterSequence, limit: 200 })
              if (!page.length) break
              comments.push(...page)
              const nextSequence = page[page.length - 1]?.sequence ?? afterSequence
              if (nextSequence <= afterSequence) break
              afterSequence = nextSequence
            }
          }
          commentsLoaded = true
        } catch (error) {
          if (!(error instanceof TaskReaderError)) throw error
          commentsReaderError = true
        }
      }
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
      initialTab={initialTab}
      initialCommentThread={commentThread}
      initialComments={comments}
      initialCommentsLoaded={commentsLoaded}
      initialCommentsReaderError={commentsReaderError}
      initialListReaderError={listReaderError}
      initialDetailReaderError={detailReaderError}
      context={context}
    />
  )
}
