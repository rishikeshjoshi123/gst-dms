'use client'

import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from 'react'
import Link from 'next/link'
import {
  AlertTriangle,
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  CircleAlert,
  CircleDashed,
  FileText,
  Gavel,
  ListTodo,
  MessageSquare,
  MoreHorizontal,
  PlayCircle,
  RefreshCw,
  Search,
  ShieldCheck,
  UserRound,
  Users,
  X,
  XCircle,
} from 'lucide-react'
import { toast } from 'sonner'

import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import {
  getTaskDetail,
  getTaskTransitionHistory,
  transitionTask,
  type TaskCommand,
  type TaskComment,
  type TaskCommentThread,
  type TaskDetail,
  type TaskListItem,
  type TaskTransition,
  type TaskWorkspaceContext,
} from '@/lib/actions/tasks'
import { cn } from '@/lib/utils'
import { TaskCommentsPanel } from './TaskCommentsPanel'
import {
  filterTasks,
  isTaskId,
  isTaskWorkspaceTab,
  notesOriginHref,
  primaryTaskCommand,
  taskHref,
  taskDetailReadState,
  taskStatusLabels,
  taskStatusVariants,
  type TaskAssignmentFilter,
  type TaskDetailReadState,
  type TaskStatusFilter,
  type TaskWorkspaceTab,
} from './task-model'

type EditDialog = 'assignee' | 'due' | null

function personLabel(context: TaskWorkspaceContext, userId: string | null) {
  if (!userId) return 'Unassigned'
  return context.people.find((person) => person.id === userId)?.label || 'Team member'
}

function relatedLabel(task: Pick<TaskListItem, 'client_id' | 'matter_id'>, context: TaskWorkspaceContext) {
  if (task.matter_id && context.matters[task.matter_id]) return context.matters[task.matter_id]
  if (task.client_id && context.clients[task.client_id]) return context.clients[task.client_id]
  return 'Organisation task'
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' })
    .format(new Date(`${value}T12:00:00Z`))
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
  }).format(new Date(value))
}

function formatDue(task: Pick<TaskListItem, 'due_date' | 'due_time' | 'due_timezone'>) {
  if (!task.due_date) return 'No due date'
  const date = formatDate(task.due_date)
  if (!task.due_time) return date
  return `${date} · ${task.due_time.slice(0, 5)}${task.due_timezone ? ` · ${task.due_timezone}` : ''}`
}

function StatusIcon({ status }: { status: TaskListItem['status'] }) {
  const Icon = status === 'completed'
    ? CheckCircle2
    : status === 'in_progress'
      ? PlayCircle
      : status === 'cancelled'
        ? XCircle
        : status === 'suspended'
          ? AlertTriangle
          : CircleDashed
  return <Icon className="size-3.5" aria-hidden="true" />
}

function StatusBadge({ status }: { status: TaskListItem['status'] }) {
  return (
    <Badge variant={taskStatusVariants[status]} fixedWidth="xl">
      <StatusIcon status={status} />
      {taskStatusLabels[status]}
    </Badge>
  )
}

function PriorityText({ priority }: { priority: TaskListItem['priority'] }) {
  if (priority === 'normal') return null
  return (
    <span className={cn(
      'text-xs font-medium capitalize',
      priority === 'urgent' && 'text-[var(--danger)]',
      priority === 'high' && 'text-[var(--warning)]',
      priority === 'low' && 'text-[var(--text-muted)]',
    )}>
      {priority}
    </span>
  )
}

function FilterMenu<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: T
  options: Array<{ value: T; label: string }>
  onChange: (value: T) => void
}) {
  const current = options.find((option) => option.value === value)?.label ?? label
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-11 min-w-0 lg:min-h-8">
          <span className="truncate">{current}</span>
          <ChevronDown className="size-3.5 shrink-0" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuLabel>{label}</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={value} onValueChange={(next) => onChange(next as T)}>
          {options.map((option) => (
            <DropdownMenuRadioItem key={option.value} value={option.value}>{option.label}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function QueueToolbar({
  query,
  status,
  assignment,
  count,
  onQuery,
  onStatus,
  onAssignment,
}: {
  query: string
  status: TaskStatusFilter
  assignment: TaskAssignmentFilter
  count: number
  onQuery: (value: string) => void
  onStatus: (value: TaskStatusFilter) => void
  onAssignment: (value: TaskAssignmentFilter) => void
}) {
  return (
    <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 sm:px-4">
      <div className="grid gap-2 sm:grid-cols-[minmax(180px,320px)_auto_auto_1fr] sm:items-center">
        <div className="relative min-w-0">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
          <Input value={query} onChange={(event) => onQuery(event.target.value)} aria-label="Search tasks" placeholder="Search tasks" className="pl-9" />
        </div>
        <div className="grid min-w-0 grid-cols-2 gap-2 sm:contents">
          <FilterMenu label="Status" value={status} onChange={onStatus} options={[
            { value: 'active', label: 'Active' }, { value: 'all', label: 'All statuses' },
            { value: 'open', label: 'Open' }, { value: 'in_progress', label: 'In progress' },
            { value: 'completed', label: 'Completed' }, { value: 'cancelled', label: 'Cancelled' },
            { value: 'suspended', label: 'Suspended' },
          ]} />
          <FilterMenu label="Assignment" value={assignment} onChange={onAssignment} options={[
            { value: 'all', label: 'All assignees' }, { value: 'mine', label: 'Assigned to me' },
            { value: 'unassigned', label: 'Unassigned' },
          ]} />
        </div>
        <p className="hidden justify-self-end text-xs text-[var(--text-muted)] sm:block">{count} {count === 1 ? 'task' : 'tasks'}</p>
      </div>
    </div>
  )
}

function TaskTableView({ tasks, selectedId, context, onSelect }: {
  tasks: TaskListItem[]
  selectedId: string | null
  context: TaskWorkspaceContext
  onSelect: (id: string) => void
}) {
  return (
    <Table className="table-fixed">
      <TableCaption>Organisation tasks. Select a task to view details.</TableCaption>
      <colgroup><col className="w-[46%]" /><col className="w-[19%]" /><col className="w-[18%]" /><col className="w-[17%]" /></colgroup>
      <TableHeader sticky><TableRow><TableHead>Task</TableHead><TableHead>Assignee</TableHead><TableHead>Due</TableHead><TableHead>Status</TableHead></TableRow></TableHeader>
      <TableBody>
        {tasks.map((task) => (
          <TableRow
            key={task.task_id}
            interactive
            selected={selectedId === task.task_id}
            tabIndex={0}
            aria-label={`View details for ${task.title}`}
            onClick={() => onSelect(task.task_id)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault()
                onSelect(task.task_id)
              }
            }}
            className="cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"
          >
            <TableCell><div className="flex min-h-11 min-w-0 items-center gap-3"><span className="min-w-0"><span className="block truncate font-medium">{task.title}</span><span className="mt-0.5 flex min-w-0 items-center gap-2"><span className="truncate text-xs text-[var(--text-muted)]">{relatedLabel(task, context)}</span><PriorityText priority={task.priority} /></span></span></div></TableCell>
            <TableCell className={cn('truncate text-xs font-medium', !task.assignee_user_id && 'text-[var(--warning)]')}>{personLabel(context, task.assignee_user_id)}</TableCell>
            <TableCell className="truncate font-mono text-xs text-[var(--text-secondary)]">{formatDue(task)}</TableCell>
            <TableCell><StatusBadge status={task.status} /></TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  )
}

function MobileTaskList({ tasks, context, onSelect }: {
  tasks: TaskListItem[]
  context: TaskWorkspaceContext
  onSelect: (id: string) => void
}) {
  return (
    <div>
      {tasks.map((task) => (
        <button key={task.task_id} type="button" onClick={() => onSelect(task.task_id)} className="flex min-h-[92px] w-full items-start gap-3 border-b border-[var(--border-subtle)] px-3 py-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)] sm:px-4">
          <span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{task.title}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{relatedLabel(task, context)}</span><span className="mt-2 flex min-w-0 items-center gap-2 text-xs"><span className={cn('truncate', !task.assignee_user_id && 'text-[var(--warning)]')}>{personLabel(context, task.assignee_user_id)}</span><span aria-hidden="true" className="text-[var(--border-strong)]">·</span><span className="truncate font-mono text-[var(--text-secondary)]">{formatDue(task)}</span></span></span>
          <span className="flex shrink-0 flex-col items-end gap-2"><StatusBadge status={task.status} /><PriorityText priority={task.priority} /></span>
        </button>
      ))}
    </div>
  )
}

function StateMessage({ title, body, error = false, action }: { title: string; body: string; error?: boolean; action?: React.ReactNode }) {
  const Icon = error ? CircleAlert : ListTodo
  return <div className="grid min-h-[320px] place-items-center p-6 text-center"><div><Icon className={cn('mx-auto size-8 text-[var(--text-muted)]', error && 'text-[var(--danger)]')} /><h2 className="mt-3 text-section-heading">{title}</h2><p className="mx-auto mt-2 max-w-sm text-sm text-[var(--text-muted)]">{body}</p>{action && <div className="mt-4">{action}</div>}</div></div>
}

function DetailLoading() {
  return <div className="space-y-3 p-4" aria-busy="true"><p className="sr-only">Loading task details…</p><Skeleton className="h-5 w-4/5" /><Skeleton className="h-4 w-2/5" /><Skeleton className="mt-4 h-24 w-full" /><Skeleton className="h-32 w-full" /></div>
}

function DetailItem({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="min-w-0"><dt className="text-caption text-[var(--text-muted)]">{label}</dt><dd className="mt-1 break-words text-sm font-medium">{children}</dd></div>
}

function ContextRow({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) {
  return <div className="flex min-w-0 items-center gap-3 py-3"><Icon className="size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">{label}</p><p className="break-words text-sm font-medium">{value}</p></div></div>
}

function historyTitle(item: TaskTransition, context: TaskWorkspaceContext) {
  if (item.command === 'set_assignee') return `Assigned to ${personLabel(context, item.to_assignee_user_id)}`
  if (item.command === 'set_due_date') return `Due date set to ${item.to_due_date ? formatDate(item.to_due_date) : 'No due date'}`
  if (item.command === 'clear_due_date') return 'Due date cleared'
  return ({ start: 'Task started', complete: 'Task completed', reopen: 'Task reopened', cancel: 'Task cancelled' } as Record<string, string>)[item.command] || 'Task updated'
}

function TaskHistory({ history, context }: { history: TaskTransition[]; context: TaskWorkspaceContext }) {
  return (
    <section className="mt-6" aria-labelledby="task-history-heading">
      <div className="flex items-center justify-between gap-3"><h3 id="task-history-heading" className="text-sm font-semibold">Task history</h3><span className="text-xs text-[var(--text-muted)]">Newest first</span></div>
      {!history.length ? <p className="mt-2 text-sm text-[var(--text-muted)]">No recorded transitions yet.</p> : (
        <ol className="mt-3">
          {[...history].reverse().map((item, index) => (
            <li key={item.transition_id} className="relative grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 pb-4 pl-6 last:pb-0">
              {index < history.length - 1 && <span aria-hidden="true" className="absolute bottom-0 left-[5px] top-2.5 w-px bg-[var(--border)]" />}
              <span aria-hidden="true" className={cn('absolute left-0 top-1.5 size-2.5 rounded-[var(--radius-full)] border-2 border-[var(--surface)]', index === 0 ? 'bg-[var(--accent)]' : 'bg-[var(--border-strong)]')} />
              <div className="min-w-0"><p className="text-sm font-medium">{historyTitle(item, context)}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">By {personLabel(context, item.actor_user_id)}</p></div>
              <time className="whitespace-nowrap pt-0.5 text-right text-xs text-[var(--text-muted)]">{formatDateTime(item.occurred_at)}</time>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}

function DetailBody({ detail, history, context }: { detail: TaskDetail; history: TaskTransition[]; context: TaskWorkspaceContext }) {
  const client = detail.client_id ? context.clients[detail.client_id] : null
  const matter = detail.matter_id ? context.matters[detail.matter_id] : null
  const document = detail.document_id ? context.documents[detail.document_id] : null
  return (
    <div className="p-4">
      <dl className="grid grid-cols-1 gap-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 min-[380px]:grid-cols-2"><DetailItem label="Assignee"><span className={cn(!detail.assignee_user_id && 'text-[var(--warning)]')}>{personLabel(context, detail.assignee_user_id)}</span></DetailItem><DetailItem label="Due">{formatDue(detail)}</DetailItem><DetailItem label="Created by">{personLabel(context, detail.creator_user_id)}</DetailItem><DetailItem label="Updated">{formatDateTime(detail.updated_at)}</DetailItem></dl>
      <section className="mt-5" aria-labelledby="task-description-heading"><h3 id="task-description-heading" className="text-sm font-semibold">Description</h3><p className="mt-2 whitespace-pre-wrap break-words text-sm leading-6 text-[var(--text-secondary)]">{detail.description || 'No description provided.'}</p></section>
      {detail.status === 'suspended' && <div className="mt-4 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-sm leading-6"><AlertTriangle className="mt-1 size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" /><span>This task is suspended and read-only.</span></div>}
      <section className="mt-5" aria-labelledby="task-context-heading"><h3 id="task-context-heading" className="text-sm font-semibold">Related work</h3><div className="mt-2 divide-y divide-[var(--border-subtle)] border-y border-[var(--border-subtle)]">{client && <ContextRow icon={Users} label="Client" value={client} />}{matter && <ContextRow icon={Gavel} label="Matter" value={matter} />}{document && <ContextRow icon={FileText} label="Document" value={document} />}{!client && !matter && !document && <p className="py-3 text-sm text-[var(--text-muted)]">No related record is available.</p>}</div></section>
      <section className="mt-5" aria-labelledby="task-origin-heading"><h3 id="task-origin-heading" className="text-sm font-semibold">Origin</h3>{detail.origin_available && detail.origin_note_id ? <><p className="mt-2 text-sm text-[var(--text-secondary)]">Created from a readable Note. The Note remains the immutable origin.</p><Link href={notesOriginHref(detail.origin_note_id)} className="mt-3 inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium outline-none transition-colors hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Open in Notes</Link></> : <div className="mt-2 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3"><ShieldCheck className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><p className="text-sm leading-6 text-[var(--text-muted)]">The Task origin is unavailable. No inaccessible Note details are shown.</p></div>}</section>
      <TaskHistory history={history} context={context} />
    </div>
  )
}

function TaskActions({ detail, canManage, pending, onCommand, onEdit }: {
  detail: TaskDetail
  canManage: boolean
  pending: boolean
  onCommand: (command: TaskCommand) => void
  onEdit: (dialog: EditDialog) => void
}) {
  const primary = primaryTaskCommand(detail.status)
  if (!canManage) return <div className="flex items-center gap-2 text-sm text-[var(--text-muted)]"><ShieldCheck className="size-4" aria-hidden="true" />Read-only access</div>
  if (!primary) return null
  const PrimaryIcon = primary.command === 'start' ? PlayCircle : primary.command === 'complete' ? CheckCircle2 : CircleDashed
  const active = detail.status === 'open' || detail.status === 'in_progress'
  return (
    <div className="flex w-full flex-wrap items-center justify-end gap-2">
      {active && <DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline" size="sm" disabled={pending}><MoreHorizontal className="size-4" aria-hidden="true" />More actions</Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuItem onSelect={() => onEdit('assignee')}><UserRound className="size-4" aria-hidden="true" />Reassign</DropdownMenuItem><DropdownMenuItem onSelect={() => onEdit('due')}><CalendarDays className="size-4" aria-hidden="true" />Change due date</DropdownMenuItem>{detail.due_date && <DropdownMenuItem onSelect={() => onCommand('clear_due_date')}>Clear due date</DropdownMenuItem>}<DropdownMenuSeparator /><DropdownMenuItem onSelect={() => onCommand('cancel')} className="text-[var(--danger)]"><XCircle className="size-4" aria-hidden="true" />Cancel task</DropdownMenuItem></DropdownMenuContent></DropdownMenu>}
      <Button size="sm" onClick={() => onCommand(primary.command)} loading={pending}><PrimaryIcon className="size-4" aria-hidden="true" />{primary.label}</Button>
    </div>
  )
}

function EditTaskDialog({ type, detail, context, pending, onClose, onSubmit, onClear }: {
  type: EditDialog
  detail: TaskDetail | null
  context: TaskWorkspaceContext
  pending: boolean
  onClose: () => void
  onSubmit: (input: { assigneeUserId?: string; dueDate?: string }) => void
  onClear: () => void
}) {
  const [assignee, setAssignee] = useState(detail?.assignee_user_id ?? '')
  const [dueDate, setDueDate] = useState(detail?.due_date ?? '')
  return (
    <Dialog open={type !== null} onOpenChange={(open) => { if (!open && !pending) onClose() }}>
      <DialogContent>
        <DialogHeader><DialogTitle>{type === 'assignee' ? 'Reassign task' : 'Change due date'}</DialogTitle><DialogDescription>{type === 'assignee' ? 'Choose an active operational team member.' : 'The date is interpreted in the organisation task timezone.'}</DialogDescription></DialogHeader>
        {type === 'assignee' ? <div><Label htmlFor="task-assignee">Assignee</Label><select id="task-assignee" value={assignee} onChange={(event) => setAssignee(event.target.value)} className="mt-2 min-h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><option value="" disabled>Choose a team member</option>{context.people.filter((person) => person.canBeAssigned).map((person) => <option key={person.id} value={person.id}>{person.label}</option>)}</select></div> : <div><Label htmlFor="task-due-date">Due date</Label><Input id="task-due-date" type="date" value={dueDate} onChange={(event) => setDueDate(event.target.value)} className="mt-2" />{detail?.due_timezone && <p className="mt-2 text-xs text-[var(--text-muted)]">Current timezone: {detail.due_timezone}</p>}</div>}
        <DialogFooter>{type === 'due' && detail?.due_date && <Button variant="outline" onClick={onClear} disabled={pending} className="sm:mr-auto">Clear due date</Button>}<Button variant="outline" onClick={onClose} disabled={pending}>Cancel</Button><Button onClick={() => type === 'assignee' ? onSubmit({ assigneeUserId: assignee }) : onSubmit({ dueDate })} disabled={pending || (type === 'assignee' ? !assignee : !dueDate)} loading={pending}>Save change</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function TaskDetailPane({
  detailReadState,
  detail,
  history,
  context,
  tab,
  unreadCount,
  detailState,
  transitionPending,
  initialCommentsLoaded,
  initialCommentThread,
  initialComments,
  initialCommentsReaderError,
  onBack,
  onTab,
  onUnreadCountChange,
  onCommand,
  onEdit,
}: {
  detailReadState: TaskDetailReadState
  detail: TaskDetail | null
  history: TaskTransition[]
  context: TaskWorkspaceContext
  tab: TaskWorkspaceTab
  unreadCount: number
  detailState: React.ReactNode
  transitionPending: boolean
  initialCommentsLoaded: boolean
  initialCommentThread: TaskCommentThread | null
  initialComments: TaskComment[]
  initialCommentsReaderError: boolean
  onBack: () => void
  onTab: (tab: TaskWorkspaceTab) => void
  onUnreadCountChange: (count: number) => void
  onCommand: (command: TaskCommand) => void
  onEdit: (dialog: EditDialog) => void
}) {
  const tabRefs = useRef<Record<TaskWorkspaceTab, HTMLButtonElement | null>>({ details: null, comments: null })
  const changeTabFromKeyboard = (next: TaskWorkspaceTab) => {
    onTab(next)
    requestAnimationFrame(() => tabRefs.current[next]?.focus())
  }

  if (detailReadState !== 'ready' || !detail) {
    return (
      <section aria-label="Task details" className="flex h-full min-h-0 flex-col bg-[var(--surface)]">
        <div className="flex min-h-12 shrink-0 items-center border-b border-[var(--border-subtle)] px-2">
          <Button variant="ghost" size="sm" onClick={onBack} className="xl:hidden"><ArrowLeft className="size-4" aria-hidden="true" />Back to tasks</Button>
          <Button variant="ghost" size="icon" onClick={onBack} aria-label="Close task details" className="ml-auto hidden xl:inline-flex"><X className="size-4" aria-hidden="true" /></Button>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{detailState}</div>
      </section>
    )
  }

  const related = relatedLabel(detail, context)
  return (
    <section aria-label={`Task workspace for ${detail.title}`} className="flex h-full min-h-0 min-w-0 flex-col bg-[var(--surface)]">
      <div className="flex min-h-12 shrink-0 items-center border-b border-[var(--border-subtle)] px-2 xl:hidden">
        <Button variant="ghost" size="sm" onClick={onBack}><ArrowLeft className="size-4" aria-hidden="true" />Back to tasks</Button>
        {!context.canManage && <span className="ml-auto flex items-center gap-1.5 text-xs text-[var(--text-muted)]"><ShieldCheck className="size-3.5" aria-hidden="true" />Read only</span>}
      </div>
      <header className="shrink-0 border-b border-[var(--border-subtle)] px-4 py-3">
        <div className="flex min-w-0 items-start gap-3">
          <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]"><ListTodo className="size-4" aria-hidden="true" /></span>
          <div className="min-w-0 flex-1"><h2 className="break-words text-base font-semibold leading-6">{detail.title}</h2><p className="mt-0.5 break-words text-xs text-[var(--text-muted)]">{related}</p></div>
          <Button variant="ghost" size="icon" className="-mr-2 -mt-1 hidden xl:inline-flex" onClick={onBack} aria-label="Close task details"><X className="size-4" aria-hidden="true" /></Button>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-2 pl-12"><StatusBadge status={detail.status} /><PriorityText priority={detail.priority} /></div>
        {(detail.status === 'completed' || detail.status === 'cancelled') && <p className="mt-2 pl-12 text-xs text-[var(--text-muted)]">This terminal task remains commentable; adding context does not reopen it.</p>}
      </header>
      <div className="flex min-h-11 shrink-0 items-stretch border-b border-[var(--border-subtle)] px-2" role="tablist" aria-label="Task sections">
        {(['details', 'comments'] as TaskWorkspaceTab[]).map((item) => {
          const selected = tab === item
          const label = item === 'details' ? 'Task details' : 'Comments'
          const Icon = item === 'details' ? ListTodo : MessageSquare
          const next = item === 'details' ? 'comments' : 'details'
          return (
            <button
              ref={(node) => { tabRefs.current[item] = node }}
              id={`task-${item}-tab`}
              key={item}
              type="button"
              role="tab"
              aria-selected={selected}
              aria-controls={`task-${item}-panel`}
              tabIndex={selected ? 0 : -1}
              onClick={() => onTab(item)}
              onKeyDown={(event) => {
                if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
                  event.preventDefault()
                  changeTabFromKeyboard(next)
                } else if (event.key === 'Home') {
                  event.preventDefault()
                  changeTabFromKeyboard('details')
                } else if (event.key === 'End') {
                  event.preventDefault()
                  changeTabFromKeyboard('comments')
                }
              }}
              className={cn('relative flex min-h-11 items-center gap-2 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', selected ? 'text-[var(--text-primary)] after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-[var(--primary)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]')}
            >
              <Icon className="size-4" aria-hidden="true" />{label}
              {item === 'comments' && unreadCount > 0 && <span className="size-2 rounded-[var(--radius-full)] bg-[var(--primary)]" aria-label={`${unreadCount} unread comments`} />}
            </button>
          )
        })}
        <span className="ml-auto hidden items-center text-xs text-[var(--text-muted)] sm:flex">Task-scoped conversation</span>
      </div>
      <div id="task-details-panel" role="tabpanel" aria-labelledby="task-details-tab" hidden={tab !== 'details'} className={cn('min-h-0 flex-1 flex-col', tab === 'details' && 'flex')}>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain" tabIndex={0}><DetailBody detail={detail} history={history} context={context} /></div>
        {detail.status !== 'suspended' && <div className="shrink-0 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><TaskActions detail={detail} canManage={context.canManage} pending={transitionPending} onCommand={onCommand} onEdit={onEdit} /></div>}
      </div>
      <TaskCommentsPanel
        key={detail.task_id}
        task={detail}
        context={context}
        active={tab === 'comments'}
        initialLoaded={initialCommentsLoaded}
        initialThread={initialCommentThread}
        initialComments={initialComments}
        initialReaderError={initialCommentsReaderError}
        onUnreadCountChange={onUnreadCountChange}
      />
    </section>
  )
}

export function TasksWorkspace({
  initialTasks,
  initialSelectedId,
  initialDetail,
  initialHistory,
  initialTab,
  initialCommentThread,
  initialComments,
  initialCommentsLoaded,
  initialCommentsReaderError,
  initialListReaderError,
  initialDetailReaderError,
  context,
}: {
  initialTasks: TaskListItem[]
  initialSelectedId: string | null
  initialDetail: TaskDetail | null
  initialHistory: TaskTransition[]
  initialTab: TaskWorkspaceTab
  initialCommentThread: TaskCommentThread | null
  initialComments: TaskComment[]
  initialCommentsLoaded: boolean
  initialCommentsReaderError: boolean
  initialListReaderError: boolean
  initialDetailReaderError: boolean
  context: TaskWorkspaceContext
}) {
  const [tasks, setTasks] = useState(initialTasks)
  const [selectedId, setSelectedId] = useState(initialSelectedId)
  const [detail, setDetail] = useState(initialDetail)
  const [history, setHistory] = useState(initialHistory)
  const [tab, setTab] = useState(initialTab)
  const [commentsUnreadCount, setCommentsUnreadCount] = useState(initialCommentThread?.unread_count ?? 0)
  const [detailLoading, setDetailLoading] = useState(false)
  const [detailReaderError, setDetailReaderError] = useState(initialDetailReaderError)
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<TaskStatusFilter>('active')
  const [assignmentFilter, setAssignmentFilter] = useState<TaskAssignmentFilter>('all')
  const [editDialog, setEditDialog] = useState<EditDialog>(null)
  const [isTransitionPending, startTransition] = useTransition()
  const [announcement, setAnnouncement] = useState('')
  const requestVersion = useRef(0)
  const attemptRef = useRef<{ fingerprint: string; key: string } | null>(null)

  const loadDetail = useCallback(async (taskId: string, updateUrl = true, nextTab: TaskWorkspaceTab = 'details') => {
    const version = ++requestVersion.current
    setSelectedId(taskId)
    setTab(nextTab)
    setCommentsUnreadCount(0)
    setDetailReaderError(false)
    if (updateUrl) window.history.pushState(null, '', taskHref(taskId, nextTab))
    if (!isTaskId(taskId)) {
      setDetailLoading(false)
      setDetail(null)
      setHistory([])
      return null
    }
    setDetailLoading(true)
    try {
      const [nextDetail, nextHistory] = await Promise.all([getTaskDetail(taskId), getTaskTransitionHistory(taskId)])
      if (version !== requestVersion.current) return null
      setDetailLoading(false)
      setDetail(nextDetail)
      setHistory(nextDetail ? nextHistory : [])
      return nextDetail
    } catch {
      if (version !== requestVersion.current) return null
      setDetailLoading(false)
      setDetail(null)
      setHistory([])
      setDetailReaderError(true)
      return null
    }
  }, [])

  const closeDetail = useCallback((updateUrl = true) => {
    requestVersion.current += 1
    setSelectedId(null)
    setDetail(null)
    setHistory([])
    setTab('details')
    setCommentsUnreadCount(0)
    setDetailReaderError(false)
    if (updateUrl) window.history.pushState(null, '', '/tasks')
  }, [])

  useEffect(() => {
    const onPopState = () => {
      const params = new URLSearchParams(window.location.search)
      const taskId = params.get('task')
      const requestedTab = params.get('tab')
      const nextTab = isTaskWorkspaceTab(requestedTab) ? requestedTab : 'details'
      if (taskId) void loadDetail(taskId, false, nextTab)
      else closeDetail(false)
    }
    window.addEventListener('popstate', onPopState)
    return () => window.removeEventListener('popstate', onPopState)
  }, [closeDetail, loadDetail])

  const changeTab = useCallback((nextTab: TaskWorkspaceTab) => {
    if (!selectedId || nextTab === tab) return
    setTab(nextTab)
    window.history.pushState(null, '', taskHref(selectedId, nextTab))
  }, [selectedId, tab])

  const updateUnreadCount = useCallback((count: number) => setCommentsUnreadCount(count), [])

  const labels = useMemo(() => tasks.map((task) => relatedLabel(task, context)), [context, tasks])
  const visibleTasks = useMemo(() => filterTasks(tasks, {
    query,
    status: statusFilter,
    assignment: assignmentFilter,
    currentUserId: context.currentUserId,
    labels,
  }), [assignmentFilter, context.currentUserId, labels, query, statusFilter, tasks])
  const detailReadState = taskDetailReadState({ selectedId, detail, loading: detailLoading, readerError: detailReaderError })
  const detailState = detailReadState === 'loading'
    ? <DetailLoading />
    : detailReadState === 'error'
      ? <StateMessage title="Task details unavailable" body="Task details could not be loaded. Try again." error action={<Button onClick={() => selectedId && void loadDetail(selectedId, false)}><RefreshCw className="size-4" aria-hidden="true" />Retry</Button>} />
      : detailReadState === 'unavailable'
        ? <StateMessage title="Task unavailable" body="This task does not exist or is not available to your account." error />
        : null

  const runCommand = (command: TaskCommand, values: { assigneeUserId?: string; dueDate?: string } = {}) => {
    if (!detail || isTransitionPending || !context.canManage) return
    const fingerprint = JSON.stringify([detail.task_id, command, detail.revision, values.assigneeUserId ?? null, values.dueDate ?? null])
    if (attemptRef.current?.fingerprint !== fingerprint) attemptRef.current = { fingerprint, key: crypto.randomUUID() }
    const attempt = attemptRef.current
    startTransition(async () => {
      const result = await transitionTask({
        taskId: detail.task_id,
        command,
        expectedRevision: detail.revision,
        assigneeUserId: values.assigneeUserId,
        dueDate: values.dueDate,
        idempotencyKey: attempt.key,
      })
      if (result.error || !result.task) {
        if (result.code === 'conflict') {
          attemptRef.current = null
          await loadDetail(detail.task_id, false)
        }
        const message = result.error || 'Unable to update this task.'
        toast.error(message)
        setAnnouncement(message)
        return
      }
      attemptRef.current = null
      setEditDialog(null)
      const refreshed = await loadDetail(detail.task_id, false)
      setTasks((current) => current.map((task) => task.task_id === detail.task_id ? {
        ...task,
        status: refreshed?.status ?? result.task.status,
        revision: refreshed?.revision ?? result.task.revision,
        assignee_user_id: refreshed ? refreshed.assignee_user_id : task.assignee_user_id,
        due_date: refreshed ? refreshed.due_date : task.due_date,
        due_time: refreshed ? refreshed.due_time : task.due_time,
        due_timezone: refreshed ? refreshed.due_timezone : task.due_timezone,
        updated_at: refreshed?.updated_at ?? task.updated_at,
      } : task))
      const message = `${detail.title} was updated.`
      toast.success(message)
      setAnnouncement(message)
    })
  }

  if (initialListReaderError) {
    return (
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
        <BreadcrumbSetter breadcrumbs={[{ label: 'Tasks' }]} />
        <StateMessage title="Tasks unavailable" body="Tasks could not be loaded. Try again." error action={<Button onClick={() => window.location.reload()}><RefreshCw className="size-4" aria-hidden="true" />Retry</Button>} />
      </div>
    )
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Tasks' }]} />
      <div className={cn(selectedId && 'hidden xl:block')}><QueueToolbar query={query} status={statusFilter} assignment={assignmentFilter} count={visibleTasks.length} onQuery={setQuery} onStatus={setStatusFilter} onAssignment={setAssignmentFilter} /></div>
      <div className="flex min-h-0 flex-1 overflow-hidden">
        <section aria-label="Task list" className={cn('h-full min-w-0 flex-1 overflow-y-auto overscroll-contain', selectedId && 'hidden xl:block')}>
          {!visibleTasks.length ? <StateMessage title={tasks.length ? 'No matching tasks' : 'No tasks yet'} body={tasks.length ? 'Clear the search or broaden the filters.' : 'Tasks created from Notes will appear here.'} /> : <><div className="hidden xl:block"><TaskTableView tasks={visibleTasks} selectedId={selectedId} context={context} onSelect={(id) => void loadDetail(id)} /></div><div className="xl:hidden"><MobileTaskList tasks={visibleTasks} context={context} onSelect={(id) => void loadDetail(id)} /></div></>}
        </section>
        {selectedId && (
          <aside aria-label="Selected task" className="h-full min-h-0 w-full shrink-0 bg-[var(--surface)] xl:w-[min(46%,34rem)] xl:border-l xl:border-[var(--border)]">
            <TaskDetailPane
              detailReadState={detailReadState}
              detail={detail}
              history={history}
              context={context}
              tab={tab}
              unreadCount={commentsUnreadCount}
              detailState={detailState}
              transitionPending={isTransitionPending}
              initialCommentsLoaded={Boolean(initialSelectedId && detail?.task_id === initialSelectedId && initialCommentsLoaded)}
              initialCommentThread={detail?.task_id === initialSelectedId ? initialCommentThread : null}
              initialComments={detail?.task_id === initialSelectedId ? initialComments : []}
              initialCommentsReaderError={Boolean(detail?.task_id === initialSelectedId && initialCommentsReaderError)}
              onBack={() => closeDetail()}
              onTab={changeTab}
              onUnreadCountChange={updateUnreadCount}
              onCommand={runCommand}
              onEdit={setEditDialog}
            />
          </aside>
        )}
      </div>
      <p className="sr-only" aria-live="polite">{announcement}</p>
      <EditTaskDialog key={`${editDialog}-${detail?.revision ?? 'none'}`} type={editDialog} detail={detail} context={context} pending={isTransitionPending} onClose={() => setEditDialog(null)} onSubmit={(values) => runCommand(editDialog === 'assignee' ? 'set_assignee' : 'set_due_date', values)} onClear={() => runCommand('clear_due_date')} />
    </div>
  )
}
