'use client'

import { useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  CircleDashed,
  FileText,
  Filter,
  Gavel,
  Info,
  ListTodo,
  MoreHorizontal,
  PauseCircle,
  PlayCircle,
  Plus,
  Search,
  ShieldCheck,
  UserRound,
  Users,
  X,
  XCircle,
} from 'lucide-react'

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
import { MobileNavDrawer } from '@/components/nav/MobileNavDrawer'
import { cn } from '@/lib/utils'

type TaskStatus = 'open' | 'in_progress' | 'completed' | 'cancelled' | 'suspended'
type Priority = 'low' | 'normal' | 'high' | 'urgent'
type PreviewState = 'default' | 'loading' | 'empty' | 'error'
type Role = 'owner_admin' | 'associate' | 'viewer'
type StatusFilter = 'active' | 'all' | TaskStatus
type AssignmentFilter = 'all' | 'mine' | 'unassigned'

type Task = {
  id: string
  title: string
  description: string
  status: TaskStatus
  priority: Priority
  assignee: string | null
  creator: string
  due: { kind: 'date'; date: string } | { kind: 'time'; date: string; time: string; timezone: string } | null
  client?: string
  matter?: string
  document?: string
  origin: { kind: 'note' | 'manual'; label: string; snapshot?: string; author?: string; createdAt: string }
  updatedAt: string
}

const initialTasks: Task[] = [
  {
    id: 'task-482',
    title: 'Verify residual invoice set before finalising the appeal grounds',
    description: 'Confirm that the eleven residual invoices are present in the signed appeal bundle and record any missing evidence.',
    status: 'in_progress',
    priority: 'urgent',
    assignee: 'Rishikesh Joshi',
    creator: 'Meera Shah',
    due: { kind: 'time', date: '2 Sep 2026', time: '14:30', timezone: 'Asia/Kolkata' },
    client: 'Apex Auto Components Private Limited',
    matter: 'FY 2023–24 ITC mismatch appeal',
    document: 'Appeal grounds — working draft v7.docx',
    origin: {
      kind: 'note',
      label: 'Hearing preparation · note 18',
      snapshot: 'I created a follow-up for the invoice verification. It should be completed before we finalise the grounds.',
      author: 'Meera Shah',
      createdAt: '1 Sep 2026 · 10:17 IST',
    },
    updatedAt: 'Today · 11:42 IST',
  },
  {
    id: 'task-479',
    title: 'Confirm department acknowledgement number',
    description: 'Locate the stamped acknowledgement and verify the number against the filing register.',
    status: 'open',
    priority: 'urgent',
    assignee: null,
    creator: 'Ananya Kapoor',
    due: { kind: 'date', date: '1 Sep 2026' },
    client: 'Mehta Industrial Works',
    matter: 'DRC-01 reply and hearing',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '31 Aug 2026 · 16:05 IST' },
    updatedAt: 'Yesterday · 16:05 IST',
  },
  {
    id: 'task-476',
    title: 'Prepare hearing chronology',
    description: 'Prepare a concise event chronology for counsel using the verified matter timeline.',
    status: 'open',
    priority: 'high',
    assignee: 'Ananya Kapoor',
    creator: 'Rishikesh Joshi',
    due: { kind: 'date', date: '5 Sep 2026' },
    client: 'Suryodaya Textiles Limited',
    matter: 'Classification appeal — woven technical fabrics',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '30 Aug 2026 · 09:20 IST' },
    updatedAt: '30 Aug · 09:20 IST',
  },
  {
    id: 'task-470',
    title: 'Send signed authority letter to counsel',
    description: 'Share the signed authority letter after confirming the final authorised signatory.',
    status: 'completed',
    priority: 'normal',
    assignee: 'Rishikesh Joshi',
    creator: 'Ananya Kapoor',
    due: { kind: 'time', date: '29 Aug 2026', time: '17:00', timezone: 'Asia/Kolkata' },
    client: 'Kaveri Components Private Limited',
    matter: 'FY 2024–25 ITC reconciliation',
    document: 'Authority letter — signed.pdf',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '28 Aug 2026 · 12:08 IST' },
    updatedAt: 'Completed 29 Aug · 15:46 IST',
  },
  {
    id: 'task-465',
    title: 'Request duplicate transport ledger',
    description: 'The client confirmed that the requested ledger is no longer available, so this follow-up was cancelled.',
    status: 'cancelled',
    priority: 'low',
    assignee: 'Meera Shah',
    creator: 'Meera Shah',
    due: null,
    client: 'Western Freight Services',
    matter: 'E-way bill penalty response',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '26 Aug 2026 · 14:12 IST' },
    updatedAt: 'Cancelled 28 Aug · 10:03 IST',
  },
  {
    id: 'task-461',
    title: 'Review archived annexure references',
    description: 'This task is paused because its matter is in Trash. Restore will re-evaluate whether the work remains relevant.',
    status: 'suspended',
    priority: 'normal',
    assignee: 'Ananya Kapoor',
    creator: 'Rishikesh Joshi',
    due: null,
    client: 'Kaveri Components Private Limited',
    matter: 'Classification advisory',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '24 Aug 2026 · 11:31 IST' },
    updatedAt: 'Suspended 30 Aug · 10:32 IST',
  },
  {
    id: 'task-458',
    title: 'Review the consolidated supplier-confirmation reconciliation workbook and the supporting annexures for the exceptionally long legal entity name used to verify responsive truncation and wrapping',
    description: 'Long-content fixture: the full title must remain available in details while the queue preserves stable row geometry without widening the page.',
    status: 'open',
    priority: 'normal',
    assignee: 'Rishikesh Joshi',
    creator: 'Ananya Kapoor',
    due: { kind: 'date', date: '12 Sep 2026' },
    client: 'Shree Venkateshwara Precision Components and Renewable Energy Systems Private Limited',
    matter: 'Consolidated supplier confirmations and reconciliation for FY 2024–25',
    document: 'Supplier confirmations — consolidated ledger and annexures for Q4 FY 2024–25.pdf',
    origin: { kind: 'manual', label: 'Created in Tasks', createdAt: '22 Aug 2026 · 17:44 IST' },
    updatedAt: '22 Aug · 17:44 IST',
  },
]

const statusLabels: Record<TaskStatus, string> = {
  open: 'Open',
  in_progress: 'In progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
  suspended: 'Suspended',
}

const statusVariants: Record<TaskStatus, 'default' | 'success' | 'muted' | 'warning'> = {
  open: 'default',
  in_progress: 'warning',
  completed: 'success',
  cancelled: 'muted',
  suspended: 'muted',
}

const roleLabels: Record<Role, string> = {
  owner_admin: 'Owner / Admin',
  associate: 'Associate',
  viewer: 'Viewer',
}

function formatDue(task: Task) {
  if (!task.due) return 'No due date'
  if (task.due.kind === 'date') return task.due.date
  return `${task.due.date} · ${task.due.time} IST`
}

function StatusIcon({ status }: { status: TaskStatus }) {
  const Icon = status === 'completed'
    ? CheckCircle2
    : status === 'in_progress'
      ? PlayCircle
      : status === 'suspended'
        ? PauseCircle
        : status === 'cancelled'
          ? XCircle
          : CircleDashed
  return <Icon className="size-3.5" aria-hidden="true" />
}

function ConceptRail() {
  return <div className="relative z-20 hidden h-full w-16 shrink-0 md:block">
    <aside className="group/sidebar absolute inset-y-0 left-0 z-30 flex w-16 flex-col overflow-hidden border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] text-[var(--sidebar-text)] transition-[width,box-shadow] duration-200 ease-out hover:w-56 hover:shadow-[var(--shadow-xl)] focus-within:w-56 focus-within:shadow-[var(--shadow-xl)]">
      <div className="flex h-14 shrink-0 items-center border-b border-[var(--sidebar-border,var(--border))] px-4">
        <Gavel className="size-5 shrink-0 text-[var(--sidebar-accent)]" aria-hidden="true" />
        <span className="ml-3 whitespace-nowrap text-sm font-semibold text-[var(--on-sidebar)] opacity-0 transition-opacity group-hover/sidebar:opacity-100 group-focus-within/sidebar:opacity-100">CaseChain</span>
      </div>
      <div className="px-2 py-4">
        <button type="button" className="flex min-h-11 w-full items-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] px-3 text-[var(--on-sidebar)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--sidebar-accent)]" aria-current="page">
          <ListTodo className="size-4 shrink-0" aria-hidden="true" />
          <span className="ml-3 whitespace-nowrap text-sm font-medium opacity-0 transition-opacity group-hover/sidebar:opacity-100 group-focus-within/sidebar:opacity-100">Tasks</span>
        </button>
      </div>
    </aside>
  </div>
}

function PreviewMenu({ state, role, onStateChange, onRoleChange, onAbout }: { state: PreviewState; role: Role; onStateChange: (state: PreviewState) => void; onRoleChange: (role: Role) => void; onAbout: () => void }) {
  return <DropdownMenu>
    <DropdownMenuTrigger asChild><Button variant="outline" size="sm"><MoreHorizontal className="size-4" />Preview<ChevronDown className="size-3.5" /></Button></DropdownMenuTrigger>
    <DropdownMenuContent align="end" className="w-56">
      <DropdownMenuLabel>Page state</DropdownMenuLabel>
      <DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}>
        <DropdownMenuRadioItem value="default">Default</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="loading">Loading</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="empty">Empty</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="error">Error</DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
      <DropdownMenuSeparator />
      <DropdownMenuLabel>Role</DropdownMenuLabel>
      <DropdownMenuRadioGroup value={role} onValueChange={(value) => onRoleChange(value as Role)}>
        <DropdownMenuRadioItem value="owner_admin">Owner / Admin</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="associate">Associate</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="viewer">Viewer · read only</DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
      <DropdownMenuSeparator />
      <DropdownMenuItem onSelect={onAbout}><Info className="size-4" />About this concept</DropdownMenuItem>
    </DropdownMenuContent>
  </DropdownMenu>
}

function FilterMenu<T extends string>({ label, value, options, onChange }: { label: string; value: T; options: Array<{ value: T; label: string }>; onChange: (value: T) => void }) {
  const current = options.find((option) => option.value === value)?.label ?? label
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild><Button variant="outline" size="sm" className="min-h-11 min-w-0 lg:min-h-8"><Filter className="size-4 shrink-0" /><span className="truncate">{current}</span><ChevronDown className="size-3.5 shrink-0" /></Button></DropdownMenuTrigger>
      <DropdownMenuContent align="start">
        <DropdownMenuLabel>{label}</DropdownMenuLabel><DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={value} onValueChange={(next) => onChange(next as T)}>
          {options.map((option) => <DropdownMenuRadioItem key={option.value} value={option.value}>{option.label}</DropdownMenuRadioItem>)}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function WorkspaceHeader({ state, role, onStateChange, onRoleChange, onAbout, onCreate, canCreate }: { state: PreviewState; role: Role; onStateChange: (state: PreviewState) => void; onRoleChange: (role: Role) => void; onAbout: () => void; onCreate: () => void; canCreate: boolean }) {
  return <header className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-4 md:px-6">
    <MobileNavDrawer />
    <div className="flex min-w-0 items-center gap-2 text-sm"><span className="hidden text-[var(--text-muted)] sm:inline">Apex Tax Advocates</span><ChevronRight className="hidden size-3.5 text-[var(--text-muted)] sm:block" /><h1 className="truncate font-semibold">Tasks</h1></div>
    <div className="ml-auto flex items-center gap-2"><PreviewMenu state={state} role={role} onStateChange={onStateChange} onRoleChange={onRoleChange} onAbout={onAbout} /><Button size="sm" onClick={onCreate} disabled={!canCreate}><Plus className="size-4" />Create task</Button></div>
  </header>
}

function QueueHeader({ query, onQuery, status, onStatus, assignment, onAssignment, count }: { query: string; onQuery: (value: string) => void; status: StatusFilter; onStatus: (value: StatusFilter) => void; assignment: AssignmentFilter; onAssignment: (value: AssignmentFilter) => void; count: number | null }) {
  return <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 sm:px-4">
    <div className="grid gap-2 sm:grid-cols-[minmax(200px,320px)_auto_auto_1fr] sm:items-center">
      <div className="relative min-w-0"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input value={query} onChange={(event) => onQuery(event.target.value)} aria-label="Search tasks" placeholder="Search tasks" className="pl-9" /></div>
      <div className="grid grid-cols-2 gap-2 sm:contents"><FilterMenu label="Status" value={status} onChange={onStatus} options={[{ value: 'active', label: 'Active' }, { value: 'all', label: 'All statuses' }, { value: 'open', label: 'Open' }, { value: 'in_progress', label: 'In progress' }, { value: 'completed', label: 'Completed' }, { value: 'cancelled', label: 'Cancelled' }, { value: 'suspended', label: 'Suspended' }]} /><FilterMenu label="Assignment" value={assignment} onChange={onAssignment} options={[{ value: 'all', label: 'All assignees' }, { value: 'mine', label: 'Assigned to me' }, { value: 'unassigned', label: 'Unassigned' }]} /></div>
      {count !== null && <p className="hidden justify-self-end text-xs text-[var(--text-muted)] sm:block">{count} {count === 1 ? 'task' : 'tasks'}</p>}
    </div>
  </div>
}

function PriorityText({ priority, quiet = false }: { priority: Priority; quiet?: boolean }) {
  if (quiet && priority === 'normal') return null
  return <span className={cn('text-xs font-medium capitalize', priority === 'urgent' && 'text-[var(--danger)]', priority === 'high' && 'text-[var(--warning)]', (priority === 'normal' || priority === 'low') && 'text-[var(--text-muted)]')}>{priority}</span>
}

function formatDueCompact(task: Task) {
  if (!task.due) return 'No due date'
  if (task.due.kind === 'date') return task.due.date
  return `${task.due.date} · ${task.due.time}`
}

function TaskTable({ tasks, selectedId, onSelect }: { tasks: Task[]; selectedId: string | null; onSelect: (id: string) => void }) {
  return <Table className="table-fixed"><TableCaption>Organisation tasks. Select a task to view details.</TableCaption><colgroup><col className="w-[46%]" /><col className="w-[20%]" /><col className="w-[18%]" /><col className="w-[16%]" /></colgroup><TableHeader sticky><TableRow><TableHead>Task</TableHead><TableHead>Assignee</TableHead><TableHead>Due</TableHead><TableHead>Status</TableHead></TableRow></TableHeader><TableBody>{tasks.map((task) => <TableRow key={task.id} interactive selected={selectedId === task.id} tabIndex={0} aria-label={`View details for ${task.title}`} onClick={() => onSelect(task.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(task.id) } }} className="cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"><TableCell><div className="flex min-h-11 w-full min-w-0 items-center gap-3 text-left"><span className="min-w-0"><span className="block truncate font-medium text-[var(--text-primary)]">{task.title}</span><span className="mt-0.5 flex min-w-0 items-center gap-2"><span className="truncate text-xs text-[var(--text-muted)]">{task.matter ?? task.client ?? 'Organisation task'}</span><PriorityText priority={task.priority} quiet /></span></span></div></TableCell><TableCell className="truncate text-xs font-medium">{task.assignee ?? <span className="text-[var(--warning)]">Unassigned</span>}</TableCell><TableCell className="truncate font-mono text-xs text-[var(--text-secondary)]">{formatDueCompact(task)}</TableCell><TableCell><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge></TableCell></TableRow>)}</TableBody></Table>
}

function MobileTaskList({ tasks, onSelect }: { tasks: Task[]; onSelect: (id: string) => void }) {
  return <div>{tasks.map((task) => <button key={task.id} type="button" onClick={() => onSelect(task.id)} className="flex min-h-[88px] w-full items-start gap-3 border-b border-[var(--border-subtle)] px-3 py-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)] sm:px-4"><span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{task.title}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{task.matter ?? task.client ?? 'Organisation task'}</span><span className="mt-2 flex items-center gap-2 text-xs"><span className={cn('truncate', !task.assignee && 'text-[var(--warning)]')}>{task.assignee ?? 'Unassigned'}</span><span className="text-[var(--border-strong)]">·</span><span className="truncate font-mono text-[var(--text-secondary)]">{formatDueCompact(task)}</span></span></span><span className="flex shrink-0 flex-col items-end gap-2"><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge><PriorityText priority={task.priority} quiet /></span></button>)}</div>
}

function QueueLoading() {
  return <div aria-busy="true" aria-live="polite"><p className="sr-only">Loading tasks…</p><div className="hidden lg:block"><Table className="table-fixed"><TableCaption>Loading tasks.</TableCaption><colgroup><col className="w-[46%]" /><col className="w-[20%]" /><col className="w-[18%]" /><col className="w-[16%]" /></colgroup><TableHeader sticky><TableRow><TableHead>Task</TableHead><TableHead>Assignee</TableHead><TableHead>Due</TableHead><TableHead>Status</TableHead></TableRow></TableHeader><TableBody>{[1, 2, 3, 4, 5].map((item) => <TableRow key={item} aria-hidden="true"><TableCell><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></TableCell><TableCell><Skeleton className="h-3.5 w-24" /></TableCell><TableCell><Skeleton className="h-3.5 w-24" /></TableCell><TableCell><Skeleton className="h-6 w-28" /></TableCell></TableRow>)}</TableBody></Table></div><div className="lg:hidden">{[1, 2, 3, 4, 5].map((item) => <div key={item} className="min-h-[88px] border-b border-[var(--border-subtle)] px-3 py-3" aria-hidden="true"><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /><Skeleton className="mt-3 h-3 w-1/2" /></div>)}</div></div>
}

function QueueState({ state, tasks, selectedId, onSelect, onRetry }: { state: PreviewState; tasks: Task[]; selectedId: string | null; onSelect: (id: string) => void; onRetry: () => void }) {
  if (state === 'loading') return <QueueLoading />
  if (state === 'empty') return <StateMessage icon={ListTodo} title="No tasks yet" body="Create a task when work needs an owner or due date." />
  if (state === 'error') return <StateMessage icon={CircleAlert} title="Tasks could not be displayed" body="Try loading the task list again." action={<Button variant="outline" onClick={onRetry}>Try again</Button>} danger />
  if (!tasks.length) return <StateMessage icon={Search} title="No matching tasks" body="Clear the search or broaden the filters." />
  return <><div className="hidden lg:block"><TaskTable tasks={tasks} selectedId={selectedId} onSelect={onSelect} /></div><div className="lg:hidden"><MobileTaskList tasks={tasks} onSelect={onSelect} /></div></>
}

function StateMessage({ icon: Icon, title, body, action, danger = false }: { icon: typeof ListTodo; title: string; body: string; action?: React.ReactNode; danger?: boolean }) {
  return <div className="grid min-h-[320px] place-items-center p-6 text-center"><div><Icon className={cn('mx-auto size-8 text-[var(--text-muted)]', danger && 'text-[var(--danger)]')} /><h2 className="mt-3 text-section-heading">{title}</h2><p className="mx-auto mt-2 max-w-sm text-sm text-[var(--text-muted)]">{body}</p>{action && <div className="mt-4">{action}</div>}</div></div>
}

function DetailItem({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="min-w-0"><dt className="text-caption text-[var(--text-muted)]">{label}</dt><dd className="mt-1 break-words text-sm font-medium">{children}</dd></div>
}

function taskHistory(task: Task) {
  const currentTitle: Record<TaskStatus, string> = {
    open: 'Ready to start',
    in_progress: 'Work started',
    completed: 'Task completed',
    cancelled: 'Task cancelled',
    suspended: 'Task paused',
  }

  return [
    {
      title: currentTitle[task.status],
      detail: task.status === 'suspended' ? 'Paused while the related matter remains in Trash.' : `${statusLabels[task.status]} · ${task.assignee ?? 'Unassigned'}`,
      at: task.updatedAt,
      current: true,
    },
    ...(task.assignee ? [{ title: `Assigned to ${task.assignee}`, detail: `Assigned by ${task.creator}`, at: task.origin.createdAt, current: false }] : []),
    {
      title: task.origin.kind === 'note' ? 'Created from a note' : 'Task created',
      detail: task.origin.label,
      at: task.origin.createdAt,
      current: false,
    },
  ]
}

function TaskHistory({ task }: { task: Task }) {
  const items = taskHistory(task)
  return <section className="mt-5" aria-labelledby="task-history-heading"><div className="flex items-center justify-between gap-3"><h3 id="task-history-heading" className="text-sm font-semibold">Task history</h3><span className="text-xs text-[var(--text-muted)]">Newest first</span></div><ol className="mt-3">{items.map((item, index) => <li key={`${item.title}-${index}`} className="relative grid grid-cols-[minmax(0,1fr)_auto] gap-x-3 pb-4 pl-6 last:pb-0">{index < items.length - 1 && <span aria-hidden="true" className="absolute bottom-0 left-[5px] top-2.5 w-px bg-[var(--border)]" />}<span aria-hidden="true" className={cn('absolute left-0 top-1.5 size-2.5 rounded-[var(--radius-full)] border-2 border-[var(--surface)]', item.current ? 'bg-[var(--accent)]' : 'bg-[var(--border-strong)]')} /><div className="min-w-0"><p className="text-sm font-medium">{item.title}</p><p className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">{item.detail}</p></div><time className="whitespace-nowrap pt-0.5 text-right text-xs text-[var(--text-muted)]">{item.at}</time></li>)}</ol></section>
}

function DetailBody({ task }: { task: Task }) {
  return <div className="p-4"><div className="min-w-0"><div className="flex items-start gap-3"><span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><ListTodo className="size-4" /></span><div className="min-w-0 flex-1"><h2 className="text-base font-semibold leading-6">{task.title}</h2><p className="mt-0.5 truncate text-xs text-[var(--text-muted)]">{task.matter ?? task.client ?? 'Organisation task'}</p></div></div><div className="mt-3 flex items-center gap-2 pl-12"><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge><PriorityText priority={task.priority} /></div></div><dl className="mt-4 grid grid-cols-2 gap-x-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3"><DetailItem label="Assignee"><span className={cn(!task.assignee && 'text-[var(--warning)]')}>{task.assignee ?? 'Unassigned'}</span></DetailItem><DetailItem label="Due">{formatDue(task)}</DetailItem></dl><section className="mt-5" aria-labelledby="task-description-heading"><h3 id="task-description-heading" className="text-sm font-semibold">Description</h3><p className="mt-2 text-sm leading-6 text-[var(--text-secondary)]">{task.description}</p></section>{task.status === 'suspended' && <div className="mt-4 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-sm leading-6"><AlertTriangle className="mt-1 size-4 shrink-0 text-[var(--warning)]" /><span>This task is paused because its matter is in Trash.</span></div>}<TaskHistory task={task} /><section className="mt-5" aria-labelledby="task-context-heading"><h3 id="task-context-heading" className="text-sm font-semibold">Related work</h3><div className="mt-2 divide-y divide-[var(--border-subtle)] border-y border-[var(--border-subtle)]">{task.client && <ContextRow icon={Users} label="Client" value={task.client} />}{task.matter && <ContextRow icon={Gavel} label="Matter" value={task.matter} />}{task.document && <ContextRow icon={FileText} label="Document" value={task.document} />}</div></section>{task.origin.snapshot && <section className="mt-5" aria-labelledby="task-note-heading"><h3 id="task-note-heading" className="text-sm font-semibold">Original note</h3><blockquote className="mt-2 border-l-2 border-[var(--border-strong)] pl-3 text-sm leading-6 text-[var(--text-secondary)]">“{task.origin.snapshot}”</blockquote></section>}</div>
}

function ContextRow({ icon: Icon, label, value }: { icon: typeof Users; label: string; value: string }) {
  return <div className="flex min-w-0 items-center gap-3 py-3"><Icon className="size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">{label}</p><p className="truncate text-sm font-medium">{value}</p></div></div>
}

function TaskActions({ task, canManage, onTransition, onReassign, onDue, onPriority }: { task: Task; canManage: boolean; onTransition: (status: TaskStatus) => void; onReassign: () => void; onDue: () => void; onPriority: () => void }) {
  const primary = task.status === 'open' ? { label: 'Start task', status: 'in_progress' as TaskStatus, icon: PlayCircle } : task.status === 'in_progress' ? { label: 'Complete task', status: 'completed' as TaskStatus, icon: CheckCircle2 } : { label: 'Reopen task', status: 'open' as TaskStatus, icon: CircleDashed }
  const PrimaryIcon = primary.icon
  return <div className="flex items-center justify-end gap-2"><DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline" size="sm" disabled={!canManage}><MoreHorizontal className="size-4" />More actions</Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuItem onSelect={onReassign}><UserRound className="size-4" />Reassign</DropdownMenuItem><DropdownMenuItem onSelect={onDue}>Change due date</DropdownMenuItem><DropdownMenuItem onSelect={onPriority}>Change priority</DropdownMenuItem>{(task.status === 'open' || task.status === 'in_progress') && <><DropdownMenuSeparator /><DropdownMenuItem onSelect={() => onTransition('suspended')}><PauseCircle className="size-4" />Pause task</DropdownMenuItem><DropdownMenuItem onSelect={() => onTransition('cancelled')} className="text-[var(--danger)]"><XCircle className="size-4" />Cancel task</DropdownMenuItem></>}</DropdownMenuContent></DropdownMenu><Button size="sm" onClick={() => onTransition(primary.status)} disabled={!canManage}><PrimaryIcon className="size-4" />{primary.label}</Button></div>
}

function DetailPane({ task, role, state, mobile, onClose, onTransition, onReassign, onDue, onPriority }: { task: Task; role: Role; state: PreviewState; mobile?: boolean; onClose: () => void; onTransition: (status: TaskStatus) => void; onReassign: () => void; onDue: () => void; onPriority: () => void }) {
  const canManage = role !== 'viewer'
  return <aside aria-label={`Task details for ${task.title}`} className={cn('flex h-full min-h-0 flex-1 flex-col bg-[var(--surface)]', !mobile && 'border-l border-[var(--border)] xl:max-w-md xl:shrink-0')}><div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-4">{mobile ? <Button variant="ghost" size="sm" className="-ml-2" onClick={onClose}><ArrowLeft className="size-4" />Back to tasks</Button> : <><ListTodo className="size-4 text-[var(--accent)]" /><span className="text-sm font-semibold">Task details</span><Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close task details"><X className="size-4" /></Button></>}{role === 'viewer' && <span className="ml-auto flex items-center gap-1.5 text-xs text-[var(--text-muted)]"><ShieldCheck className="size-3.5" />Read only</span>}</div><div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{state === 'loading' ? <div className="space-y-3 p-4" aria-busy="true"><p className="sr-only">Loading task details…</p><Skeleton className="h-4 w-full" /><Skeleton className="h-4 w-4/5" /><Skeleton className="mt-4 h-32 w-full" /><Skeleton className="h-40 w-full" /></div> : state === 'error' ? <StateMessage icon={CircleAlert} title="Details unavailable" body="Try loading the workspace again." danger /> : <DetailBody task={task} />}</div>{state === 'default' && <div className="shrink-0 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><TaskActions task={task} canManage={canManage} onTransition={onTransition} onReassign={onReassign} onDue={onDue} onPriority={onPriority} /></div>}</aside>
}

function CreateTaskDialog({ open, onOpenChange, onCreate }: { open: boolean; onOpenChange: (open: boolean) => void; onCreate: (title: string) => void }) {
  const [title, setTitle] = useState('')
  const create = () => { if (!title.trim()) return; onCreate(title.trim()); setTitle('') }
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogHeader><DialogTitle>Create a fixture task</DialogTitle><DialogDescription>This preview adds one local, single-assignee task to the concept. It does not call an API or save organisation data.</DialogDescription></DialogHeader><div><Label htmlFor="fixture-task-title">Task title</Label><Input id="fixture-task-title" className="mt-2" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Describe the work to complete" /><p className="mt-2 text-xs text-[var(--text-muted)]">Assignee: Rishikesh Joshi · Priority: Normal · No due date</p></div><DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button onClick={create} disabled={!title.trim()}><Plus className="size-4" />Create fixture task</Button></DialogFooter></DialogContent></Dialog>
}

export function TasksWorkspaceConcept() {
  const [tasks, setTasks] = useState(initialTasks)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [mobileDetail, setMobileDetail] = useState(false)
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('active')
  const [assignmentFilter, setAssignmentFilter] = useState<AssignmentFilter>('all')
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [role, setRole] = useState<Role>('owner_admin')
  const [aboutOpen, setAboutOpen] = useState(false)
  const [createOpen, setCreateOpen] = useState(false)
  const [announcement, setAnnouncement] = useState('')
  const mobileListRef = useRef<HTMLDivElement>(null)
  const mobileListScroll = useRef(0)

  const visibleTasks = useMemo(() => tasks.filter((task) => {
    const text = `${task.title} ${task.client ?? ''} ${task.matter ?? ''} ${task.document ?? ''}`.toLowerCase()
    const matchesQuery = text.includes(query.trim().toLowerCase())
    const matchesStatus = statusFilter === 'all' || (statusFilter === 'active' ? task.status === 'open' || task.status === 'in_progress' : task.status === statusFilter)
    const matchesAssignment = assignmentFilter === 'all' || (assignmentFilter === 'mine' ? task.assignee === 'Rishikesh Joshi' : task.assignee === null)
    return matchesQuery && matchesStatus && matchesAssignment
  }), [assignmentFilter, query, statusFilter, tasks])

  const selectedTask = tasks.find((task) => task.id === selectedId) ?? null
  const selectMobile = (id: string) => { mobileListScroll.current = mobileListRef.current?.scrollTop ?? 0; setSelectedId(id); setMobileDetail(true) }
  const closeDetails = () => { setMobileDetail(false); setSelectedId(null); requestAnimationFrame(() => { if (mobileListRef.current) mobileListRef.current.scrollTop = mobileListScroll.current }) }
  const updateSelected = (update: (task: Task) => Task, message: string) => { if (!selectedTask) return; setTasks((current) => current.map((task) => task.id === selectedTask.id ? update(task) : task)); setAnnouncement(message) }
  const transition = (status: TaskStatus) => { if (selectedTask) updateSelected((task) => ({ ...task, status, updatedAt: `Just now · fixture ${statusLabels[status].toLowerCase()}` }), `${selectedTask.title} changed to ${statusLabels[status]} in this fixture.`) }
  const reassign = () => { if (selectedTask) updateSelected((task) => ({ ...task, assignee: task.assignee === 'Ananya Kapoor' ? 'Rishikesh Joshi' : 'Ananya Kapoor' }), `Fixture assignee changed for ${selectedTask.title}.`) }
  const changeDue = () => { if (selectedTask) updateSelected((task) => ({ ...task, due: task.due?.kind === 'date' ? { kind: 'time', date: task.due.date, time: '14:30', timezone: 'Asia/Kolkata' } : { kind: 'date', date: task.due?.date ?? '8 Sep 2026' } }), `Fixture due date changed for ${selectedTask.title}.`) }
  const changePriority = () => { if (selectedTask) updateSelected((task) => ({ ...task, priority: task.priority === 'urgent' ? 'normal' : 'urgent' }), `Fixture priority changed for ${selectedTask.title}.`) }
  const createTask = (title: string) => { const task: Task = { id: `task-fixture-${tasks.length + 1}`, title, description: 'Locally created fixture task for interaction review.', status: 'open', priority: 'normal', assignee: 'Rishikesh Joshi', creator: roleLabels[role], due: null, origin: { kind: 'manual', label: 'Created in Tasks', createdAt: 'Just now · fixture only' }, updatedAt: 'Just now · fixture created' }; setTasks((current) => [task, ...current]); setSelectedId(task.id); setMobileDetail(true); setPreviewState('default'); setCreateOpen(false); setAnnouncement(`${title} was added to this fixture.`) }

  return (
    <div className="flex h-dvh max-w-full overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <ConceptRail />
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <WorkspaceHeader state={previewState} role={role} onStateChange={setPreviewState} onRoleChange={setRole} onAbout={() => setAboutOpen(true)} onCreate={() => setCreateOpen(true)} canCreate={role !== 'viewer'} />
        {!mobileDetail && <QueueHeader query={query} onQuery={setQuery} status={statusFilter} onStatus={setStatusFilter} assignment={assignmentFilter} onAssignment={setAssignmentFilter} count={previewState === 'default' ? visibleTasks.length : null} />}

        <div className="min-h-0 flex-1 overflow-hidden">
          <div className="hidden h-full min-h-0 xl:flex">
            <section aria-label="Task list" className="min-w-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)]"><QueueState state={previewState} tasks={visibleTasks} selectedId={selectedId} onSelect={setSelectedId} onRetry={() => setPreviewState('default')} /></section>
            {selectedTask && previewState !== 'empty' && <DetailPane task={selectedTask} role={role} state={previewState} onClose={closeDetails} onTransition={transition} onReassign={reassign} onDue={changeDue} onPriority={changePriority} />}
          </div>

          <div className="h-full min-h-0 xl:hidden">
            {mobileDetail && selectedTask ? <DetailPane task={selectedTask} role={role} state={previewState} mobile onClose={closeDetails} onTransition={transition} onReassign={reassign} onDue={changeDue} onPriority={changePriority} /> : <section aria-label="Task list" ref={mobileListRef} className="h-full min-h-0 overflow-y-auto overscroll-contain bg-[var(--surface)]"><QueueState state={previewState} tasks={visibleTasks} selectedId={selectedId} onSelect={selectMobile} onRetry={() => setPreviewState('default')} /></section>}
          </div>
        </div>
      </main>

      <p className="sr-only" aria-live="polite">{announcement}</p>
      <CreateTaskDialog open={createOpen} onOpenChange={setCreateOpen} onCreate={createTask} />
      <Dialog open={aboutOpen} onOpenChange={setAboutOpen}><DialogContent><DialogHeader><DialogTitle>Tasks workspace concept</DialogTitle><DialogDescription>This review page uses local fixture data only. Nothing is saved.</DialogDescription></DialogHeader><p className="text-sm leading-6 text-[var(--text-secondary)]">Search, filters, role previews, task creation, assignment, dates, priorities, and status changes reset when the page reloads.</p><DialogFooter><Button onClick={() => setAboutOpen(false)}>Close</Button></DialogFooter></DialogContent></Dialog>
    </div>
  )
}
