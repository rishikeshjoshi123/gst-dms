'use client'

import { useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  CalendarClock,
  Check,
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
  MessageSquareText,
  MoreHorizontal,
  PauseCircle,
  PlayCircle,
  Plus,
  Search,
  ShieldCheck,
  UserRound,
  Users,
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

const priorityVariants: Record<Priority, 'danger' | 'warning' | 'outline' | 'muted'> = {
  urgent: 'danger',
  high: 'warning',
  normal: 'outline',
  low: 'muted',
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

function dueContract(task: Task) {
  if (!task.due) return 'No date or time set'
  if (task.due.kind === 'date') return 'Date only · organisation day in Asia/Kolkata'
  return `Timed · ${task.due.time} in ${task.due.timezone}`
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

function AppRail() {
  return (
    <aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] lg:flex">
      <span className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]" aria-label="CaseChain">
        <Gavel className="size-5" aria-hidden="true" />
      </span>
      <div className="group relative mt-5">
        <button type="button" aria-label="Tasks" className="flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--sidebar-accent)]">
          <ListTodo className="size-5" aria-hidden="true" />
        </button>
        <span role="tooltip" className="pointer-events-none absolute left-12 top-1/2 z-30 -translate-y-1/2 rounded-[var(--radius-sm)] bg-[var(--sidebar-hover)] px-2 py-1 text-xs font-medium text-[var(--on-sidebar)] opacity-0 shadow-[var(--shadow-md)] group-focus-within:opacity-100 group-hover:opacity-100">Tasks</span>
      </div>
      <span className="mt-auto flex size-9 items-center justify-center rounded-[var(--radius-full)] border border-[var(--sidebar-border)] text-xs font-semibold">RJ</span>
    </aside>
  )
}

function RoleMenu({ role, onChange }: { role: Role; onChange: (role: Role) => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-11 lg:min-h-8"><ShieldCheck className="size-4" />{roleLabels[role]}<ChevronDown className="size-3.5" /></Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>Preview capability</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={role} onValueChange={(value) => onChange(value as Role)}>
          <DropdownMenuRadioItem value="owner_admin">Owner / Admin</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="associate">Associate</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="viewer">Viewer · read only</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function PreviewMenu({ state, onChange, onAbout }: { state: PreviewState; onChange: (state: PreviewState) => void; onAbout: () => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="min-h-11 lg:min-h-8"><MoreHorizontal className="size-4" />Preview<ChevronDown className="size-3.5" /></Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuLabel>Workspace state</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onChange(value as PreviewState)}>
          <DropdownMenuRadioItem value="default">Default</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="loading">Loading</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="empty">Empty</DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="error">Error</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={onAbout}><Info className="size-4" />About this concept</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
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

function QueueHeader({ query, onQuery, status, onStatus, assignment, onAssignment, count }: { query: string; onQuery: (value: string) => void; status: StatusFilter; onStatus: (value: StatusFilter) => void; assignment: AssignmentFilter; onAssignment: (value: AssignmentFilter) => void; count: number }) {
  return (
    <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] p-3">
      <div className="flex items-center justify-between gap-3">
        <div><h2 className="text-sm font-semibold">Task queue</h2><p className="mt-0.5 text-xs text-[var(--text-muted)]">{count} shown · organisation tasks</p></div>
        <Badge variant="outline">Asia/Kolkata</Badge>
      </div>
      <div className="mt-3 grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto_auto]">
        <div className="relative min-w-0"><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input value={query} onChange={(event) => onQuery(event.target.value)} aria-label="Search tasks" placeholder="Search tasks" className="pl-9" /></div>
        <FilterMenu label="Status" value={status} onChange={onStatus} options={[
          { value: 'active', label: 'Active work' }, { value: 'all', label: 'All statuses' }, { value: 'open', label: 'Open' }, { value: 'in_progress', label: 'In progress' }, { value: 'completed', label: 'Completed' }, { value: 'cancelled', label: 'Cancelled' }, { value: 'suspended', label: 'Suspended' },
        ]} />
        <FilterMenu label="Assignment" value={assignment} onChange={onAssignment} options={[
          { value: 'all', label: 'All assignees' }, { value: 'mine', label: 'Assigned to me' }, { value: 'unassigned', label: 'Unassigned' },
        ]} />
      </div>
    </div>
  )
}

function TaskRow({ task, selected, onSelect }: { task: Task; selected: boolean; onSelect: () => void }) {
  return (
    <button type="button" onClick={onSelect} aria-current={selected ? 'true' : undefined} className={cn('group w-full border-b border-[var(--border-subtle)] p-3 text-left outline-none transition-colors hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', selected && 'bg-[var(--accent-muted)]')}>
      <div className="flex min-w-0 items-start gap-3">
        <span className={cn('mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)]', task.priority === 'urgent' ? 'bg-[var(--danger-muted)] text-[var(--danger)]' : 'bg-[var(--bg-overlay)] text-[var(--text-muted)]')}><ListTodo className="size-4" aria-hidden="true" /></span>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-sm font-semibold text-[var(--text-primary)]">{task.title}</span>
          <span className="mt-1 flex min-w-0 items-center gap-1.5 text-xs text-[var(--text-muted)]"><span className="truncate">{task.client ?? 'Organisation task'}</span>{task.matter && <><ChevronRight className="size-3 shrink-0" /><span className="truncate">{task.matter}</span></>}</span>
          <span className="mt-2 flex flex-wrap items-center gap-2"><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge><Badge variant={priorityVariants[task.priority]} fixedWidth="lg" className="capitalize">{task.priority}</Badge></span>
          <span className="mt-2 grid grid-cols-2 gap-2 text-xs"><span className="min-w-0"><span className="block text-[var(--text-muted)]">Assignee</span><span className={cn('mt-0.5 block truncate font-medium', !task.assignee && 'text-[var(--danger)]')}>{task.assignee ?? 'Unassigned'}</span></span><span className="min-w-0"><span className="block text-[var(--text-muted)]">Due</span><span className="mt-0.5 block truncate font-mono font-medium">{formatDue(task)}</span></span></span>
        </span>
        <ChevronRight className="mt-1 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
      </div>
    </button>
  )
}

function QueueLoading() {
  return <div aria-busy="true" aria-live="polite"><p className="sr-only">Loading tasks…</p>{[1, 2, 3, 4].map((item) => <div key={item} className="flex min-h-36 gap-3 border-b border-[var(--border-subtle)] p-3" aria-hidden="true"><Skeleton className="size-8 shrink-0" /><span className="min-w-0 flex-1"><Skeleton className="h-3.5 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /><span className="mt-3 flex gap-2"><Skeleton className="h-6 w-32" /><Skeleton className="h-6 w-24" /></span><span className="mt-3 grid grid-cols-2 gap-3"><Skeleton className="h-8" /><Skeleton className="h-8" /></span></span></div>)}</div>
}

function QueueState({ state, tasks, selectedId, onSelect, onRetry }: { state: PreviewState; tasks: Task[]; selectedId: string; onSelect: (id: string) => void; onRetry: () => void }) {
  if (state === 'loading') return <QueueLoading />
  if (state === 'empty') return <div className="grid min-h-full place-items-center p-6 text-center"><div><ListTodo className="mx-auto size-8 text-[var(--text-muted)]" /><h3 className="mt-3 text-section-heading">No tasks match</h3><p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-[var(--text-muted)]">Try a broader status or assignment filter. Nothing was changed.</p></div></div>
  if (state === 'error') return <div className="grid min-h-full place-items-center p-6 text-center"><div><CircleAlert className="mx-auto size-8 text-[var(--danger)]" /><h3 className="mt-3 text-section-heading">Tasks could not be displayed</h3><p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-[var(--text-muted)]">The fixture list did not load. Try the preview again without changing task state.</p><Button variant="outline" className="mt-4" onClick={onRetry}>Try again</Button></div></div>
  return tasks.length ? <div>{tasks.map((task) => <TaskRow key={task.id} task={task} selected={selectedId === task.id} onSelect={() => onSelect(task.id)} />)}</div> : <div className="grid min-h-full place-items-center p-6 text-center"><div><Search className="mx-auto size-8 text-[var(--text-muted)]" /><h3 className="mt-3 text-section-heading">No matching tasks</h3><p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-[var(--text-muted)]">Clear the search or broaden the filters to return to the queue.</p></div></div>
}

function DefinitionItem({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="min-w-0"><dt className="text-xs text-[var(--text-muted)]">{label}</dt><dd className="mt-1 break-words text-sm font-medium text-[var(--text-primary)]">{children}</dd></div>
}

function DetailBody({ task }: { task: Task }) {
  return (
    <div className="mx-auto w-full max-w-3xl p-4 sm:p-5">
      <section aria-labelledby="task-overview-heading">
        <h3 id="task-overview-heading" className="text-section-heading">Task overview</h3>
        {task.title.length > 100 && <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] p-3"><p className="text-xs text-[var(--text-muted)]">Full task title</p><p className="mt-1 break-words text-sm font-semibold leading-6">{task.title}</p></div>}
        <p className="mt-2 text-sm leading-6 text-[var(--text-secondary)]">{task.description}</p>
        <dl className="mt-4 grid gap-4 border-y border-[var(--border-subtle)] py-4 sm:grid-cols-2">
          <DefinitionItem label="Assignee"><span className={cn('inline-flex items-center gap-1.5', !task.assignee && 'text-[var(--danger)]')}><UserRound className="size-4" />{task.assignee ?? 'Unassigned'}</span></DefinitionItem>
          <DefinitionItem label="Created by">{task.creator}</DefinitionItem>
          <DefinitionItem label="Due">{formatDue(task)}</DefinitionItem>
          <DefinitionItem label="Due contract">{dueContract(task)}</DefinitionItem>
          <DefinitionItem label="Last activity">{task.updatedAt}</DefinitionItem>
          <DefinitionItem label="Task reference"><span className="font-mono">{task.id.toUpperCase()}</span></DefinitionItem>
        </dl>
      </section>

      <section className="mt-5" aria-labelledby="task-context-heading">
        <h3 id="task-context-heading" className="text-section-heading">Work context</h3>
        <div className="mt-3 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          {task.client && <div className="flex gap-3 border-b border-[var(--border-subtle)] p-3"><Users className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">Client</p><p className="mt-0.5 break-words text-sm font-medium">{task.client}</p></div></div>}
          {task.matter && <div className="flex gap-3 border-b border-[var(--border-subtle)] p-3"><Gavel className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">Matter</p><p className="mt-0.5 break-words text-sm font-medium">{task.matter}</p></div></div>}
          {task.document && <div className="flex gap-3 p-3"><FileText className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" /><div className="min-w-0"><p className="text-xs text-[var(--text-muted)]">Document</p><p className="mt-0.5 break-words text-sm font-medium">{task.document}</p></div></div>}
        </div>
      </section>

      <section className="mt-5" aria-labelledby="task-origin-heading">
        <div className="flex flex-wrap items-center gap-2"><h3 id="task-origin-heading" className="text-section-heading">Origin</h3><Badge variant="muted"><ShieldCheck className="size-3.5" />Immutable</Badge></div>
        <div className="mt-3 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4">
          <div className="flex items-start gap-3"><span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]">{task.origin.kind === 'note' ? <MessageSquareText className="size-4" /> : <ListTodo className="size-4" />}</span><div className="min-w-0"><p className="text-sm font-semibold">{task.origin.label}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">{task.origin.author ? `${task.origin.author} · ` : ''}{task.origin.createdAt}</p></div></div>
          {task.origin.snapshot && <blockquote className="mt-3 border-l-2 border-[var(--border-strong)] pl-3 text-sm leading-6 text-[var(--text-secondary)]">“{task.origin.snapshot}”</blockquote>}
          <div className="mt-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
            <div className="flex flex-wrap items-center gap-2"><span className="text-xs font-semibold text-[var(--text-primary)]">Live Task summary</span><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge></div>
            <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">The note keeps this origin snapshot read-only. Current status, assignee, priority, and due contract come only from the Task and change only here in Tasks.</p>
          </div>
        </div>
      </section>

      {task.status === 'suspended' && <div className="mt-5 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-sm leading-6"><AlertTriangle className="mt-1 size-4 shrink-0 text-[var(--warning)]" /><span>This fixture task is suspended because its matter is in Trash. It is absent from active personal work until restore re-evaluates relevance.</span></div>}
    </div>
  )
}

function DetailLoading() {
  return <div className="mx-auto w-full max-w-3xl p-5" aria-busy="true"><p className="sr-only">Loading task details…</p><Skeleton className="h-5 w-36" /><Skeleton className="mt-4 h-4 w-full" /><Skeleton className="mt-2 h-4 w-4/5" /><div className="mt-5 grid grid-cols-2 gap-4 border-y border-[var(--border-subtle)] py-4">{[1, 2, 3, 4, 5, 6].map((item) => <span key={item}><Skeleton className="h-3 w-20" /><Skeleton className="mt-2 h-4 w-4/5" /></span>)}</div><Skeleton className="mt-6 h-5 w-28" /><Skeleton className="mt-3 h-40 w-full" /><Skeleton className="mt-6 h-5 w-20" /><Skeleton className="mt-3 h-56 w-full" /></div>
}

function DetailPane({ task, role, state, mobile, onBack, onTransition, onReassign, onDue, onPriority }: { task: Task; role: Role; state: PreviewState; mobile?: boolean; onBack?: () => void; onTransition: (status: TaskStatus) => void; onReassign: () => void; onDue: () => void; onPriority: () => void }) {
  const canManage = role !== 'viewer'
  const showComplete = task.status === 'open' || task.status === 'in_progress'
  const showReopen = task.status === 'completed' || task.status === 'cancelled' || task.status === 'suspended'
  if (state === 'empty') return <section aria-label="Task details" className="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-[var(--bg)]"><div className="flex min-h-16 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] p-3 sm:p-4">{mobile && <Button variant="ghost" size="sm" className="-ml-2 min-h-11 shrink-0" onClick={onBack}><ArrowLeft className="size-4" />Back to tasks</Button>}<div><h2 className="text-base font-semibold">No task selected</h2><p className="mt-0.5 text-xs text-[var(--text-muted)]">The queue preview is empty</p></div></div><div className="grid min-h-0 flex-1 place-items-center overflow-y-auto p-6 text-center"><div><ListTodo className="mx-auto size-8 text-[var(--text-muted)]" /><h3 className="mt-3 text-section-heading">Select a task when work appears</h3><p className="mt-2 text-sm text-[var(--text-muted)]">Details and task actions will open here without moving the queue header.</p></div></div></section>
  return (
    <section aria-label={`Task details for ${task.title}`} className="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-[var(--bg)]">
      <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] p-3 sm:p-4">
        <div className="flex min-w-0 items-start gap-3">
          {mobile && <Button variant="ghost" size="sm" className="-ml-2 min-h-11 shrink-0" onClick={onBack}><ArrowLeft className="size-4" />Back to tasks</Button>}
          <div className={cn('min-w-0 flex-1', mobile && 'hidden sm:block')}><div className="flex flex-wrap items-center gap-2"><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge><Badge variant={priorityVariants[task.priority]} fixedWidth="lg" className="capitalize">{task.priority}</Badge></div><h2 className="mt-2 line-clamp-2 text-base font-semibold leading-6 text-[var(--text-primary)]">{task.title}</h2><p className="mt-1 truncate text-xs text-[var(--text-muted)]">{task.matter ?? task.client ?? 'Organisation task'}</p></div>
          {!mobile && <Button variant="outline" size="sm" onClick={onReassign} disabled={!canManage}><UserRound className="size-4" />Reassign task</Button>}
        </div>
        {mobile && <div className="mt-2 min-w-0 sm:hidden"><div className="flex flex-wrap items-center gap-2"><Badge variant={statusVariants[task.status]} fixedWidth="xl"><StatusIcon status={task.status} />{statusLabels[task.status]}</Badge><Badge variant={priorityVariants[task.priority]} fixedWidth="lg" className="capitalize">{task.priority}</Badge></div><h2 className="mt-2 line-clamp-2 text-base font-semibold leading-6">{task.title}</h2></div>}
        {role === 'viewer' && <div className="mt-3 flex items-start gap-2 rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] p-2.5 text-xs leading-5 text-[var(--text-muted)]"><ShieldCheck className="mt-0.5 size-4 shrink-0" /><span>Viewer preview is read-only. Task creation, assignment, and state changes are unavailable.</span></div>}
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{state === 'loading' ? <DetailLoading /> : state === 'error' ? <div className="grid min-h-full place-items-center p-6 text-center"><div><CircleAlert className="mx-auto size-8 text-[var(--danger)]" /><h3 className="mt-3 text-section-heading">Task details are unavailable</h3><p className="mt-2 text-sm text-[var(--text-muted)]">Return to the queue or retry the workspace preview.</p></div></div> : <DetailBody task={task} />}</div>
      {state === 'default' && <div className="shrink-0 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3">
        <div className="flex flex-wrap items-center justify-end gap-2 [&_button]:min-h-11 lg:[&_button]:min-h-8">
          <Button variant="outline" size="sm" onClick={onDue} disabled={!canManage}><CalendarClock className="size-4" />Change due date</Button>
          <Button variant="outline" size="sm" onClick={onPriority} disabled={!canManage}><AlertTriangle className="size-4" />Change priority</Button>
          {mobile && <Button variant="outline" size="sm" onClick={onReassign} disabled={!canManage}><UserRound className="size-4" />Reassign task</Button>}
          {task.status === 'open' && <Button size="sm" onClick={() => onTransition('in_progress')} disabled={!canManage}><PlayCircle className="size-4" />Start task</Button>}
          {showComplete && <Button size="sm" onClick={() => onTransition('completed')} disabled={!canManage}><Check className="size-4" />Complete task</Button>}
          {showComplete && <Button variant="outline" size="sm" onClick={() => onTransition('suspended')} disabled={!canManage}><PauseCircle className="size-4" />Suspend task</Button>}
          {showComplete && <Button variant="destructive" size="sm" onClick={() => onTransition('cancelled')} disabled={!canManage}><XCircle className="size-4" />Cancel task</Button>}
          {showReopen && <Button size="sm" onClick={() => onTransition('open')} disabled={!canManage}><CircleDashed className="size-4" />Reopen task</Button>}
        </div>
      </div>}
    </section>
  )
}

function CreateTaskDialog({ open, onOpenChange, onCreate }: { open: boolean; onOpenChange: (open: boolean) => void; onCreate: (title: string) => void }) {
  const [title, setTitle] = useState('')
  const create = () => { if (!title.trim()) return; onCreate(title.trim()); setTitle('') }
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent><DialogHeader><DialogTitle>Create a fixture task</DialogTitle><DialogDescription>This preview adds one local, single-assignee task to the concept. It does not call an API or save organisation data.</DialogDescription></DialogHeader><div><Label htmlFor="fixture-task-title">Task title</Label><Input id="fixture-task-title" className="mt-2" value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Describe the work to complete" /><p className="mt-2 text-xs text-[var(--text-muted)]">Assignee: Rishikesh Joshi · Priority: Normal · No due date</p></div><DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button onClick={create} disabled={!title.trim()}><Plus className="size-4" />Create fixture task</Button></DialogFooter></DialogContent></Dialog>
}

export function TasksWorkspaceConcept() {
  const [tasks, setTasks] = useState(initialTasks)
  const [selectedId, setSelectedId] = useState(initialTasks[0].id)
  const [mobileDetail, setMobileDetail] = useState(false)
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
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

  const selectedTask = tasks.find((task) => task.id === selectedId) ?? tasks[0]
  const selectMobile = (id: string) => { mobileListScroll.current = mobileListRef.current?.scrollTop ?? 0; setSelectedId(id); setMobileDetail(true) }
  const backToList = () => { setMobileDetail(false); requestAnimationFrame(() => { if (mobileListRef.current) mobileListRef.current.scrollTop = mobileListScroll.current }) }
  const updateSelected = (update: (task: Task) => Task, message: string) => { setTasks((current) => current.map((task) => task.id === selectedTask.id ? update(task) : task)); setAnnouncement(message) }
  const transition = (status: TaskStatus) => updateSelected((task) => ({ ...task, status, updatedAt: `Just now · fixture ${statusLabels[status].toLowerCase()}` }), `${selectedTask.title} changed to ${statusLabels[status]} in this fixture.`)
  const reassign = () => updateSelected((task) => ({ ...task, assignee: task.assignee === 'Ananya Kapoor' ? 'Rishikesh Joshi' : 'Ananya Kapoor' }), `Fixture assignee changed for ${selectedTask.title}.`)
  const changeDue = () => updateSelected((task) => ({ ...task, due: task.due?.kind === 'date' ? { kind: 'time', date: task.due.date, time: '14:30', timezone: 'Asia/Kolkata' } : { kind: 'date', date: task.due?.date ?? '8 Sep 2026' } }), `Fixture due contract changed for ${selectedTask.title}.`)
  const changePriority = () => updateSelected((task) => ({ ...task, priority: task.priority === 'urgent' ? 'normal' : 'urgent' }), `Fixture priority changed for ${selectedTask.title}.`)
  const createTask = (title: string) => { const task: Task = { id: `task-fixture-${tasks.length + 1}`, title, description: 'Locally created fixture task for interaction review.', status: 'open', priority: 'normal', assignee: 'Rishikesh Joshi', creator: roleLabels[role], due: null, origin: { kind: 'manual', label: 'Created in Tasks', createdAt: 'Just now · fixture only' }, updatedAt: 'Just now · fixture created' }; setTasks((current) => [task, ...current]); setSelectedId(task.id); setPreviewState('default'); setCreateOpen(false); setAnnouncement(`${title} was added to this fixture.`) }

  return (
    <div className="flex h-dvh max-w-full overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <AppRail />
      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
          <div className="flex min-h-16 flex-wrap items-center gap-2 px-3 py-2 sm:px-4">
            <div className="min-w-0 flex-1"><div className="flex items-center gap-2"><ListTodo className="size-5 shrink-0 text-[var(--accent)]" /><h1 className="text-page-title truncate">Tasks</h1></div><p className="mt-0.5 truncate text-xs text-[var(--text-muted)]">Organisation task queue · Task is the live source of state</p></div>
            <div className="flex flex-wrap items-center justify-end gap-2"><RoleMenu role={role} onChange={setRole} /><PreviewMenu state={previewState} onChange={setPreviewState} onAbout={() => setAboutOpen(true)} /><Button size="sm" className="min-h-11 lg:min-h-8" onClick={() => setCreateOpen(true)} disabled={role === 'viewer'}><Plus className="size-4" />Create task</Button></div>
          </div>
          <div className="flex min-h-9 items-center gap-2 border-t border-[var(--border-subtle)] px-3 text-xs text-[var(--text-muted)] sm:px-4"><Info className="size-3.5 shrink-0" /><span className="truncate">Approval concept · local fixture transitions only · no production data</span></div>
        </header>

        <div className="min-h-0 flex-1 overflow-hidden">
          <div className="hidden h-full min-h-0 lg:flex">
            <section aria-label="Task queue" className="flex w-[44%] min-w-[390px] max-w-[610px] shrink-0 flex-col border-r border-[var(--border)] bg-[var(--surface)]">
              <QueueHeader query={query} onQuery={setQuery} status={statusFilter} onStatus={setStatusFilter} assignment={assignmentFilter} onAssignment={setAssignmentFilter} count={previewState === 'default' ? visibleTasks.length : 0} />
              <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain"><QueueState state={previewState} tasks={visibleTasks} selectedId={selectedId} onSelect={setSelectedId} onRetry={() => setPreviewState('default')} /></div>
            </section>
            <DetailPane task={selectedTask} role={role} state={previewState} onTransition={transition} onReassign={reassign} onDue={changeDue} onPriority={changePriority} />
          </div>

          <div className="h-full min-h-0 lg:hidden">
            {mobileDetail ? <DetailPane task={selectedTask} role={role} state={previewState} mobile onBack={backToList} onTransition={transition} onReassign={reassign} onDue={changeDue} onPriority={changePriority} /> : <section aria-label="Task queue" className="flex h-full min-h-0 flex-col bg-[var(--surface)]"><QueueHeader query={query} onQuery={setQuery} status={statusFilter} onStatus={setStatusFilter} assignment={assignmentFilter} onAssignment={setAssignmentFilter} count={previewState === 'default' ? visibleTasks.length : 0} /><div ref={mobileListRef} className="min-h-0 flex-1 overflow-y-auto overscroll-contain"><QueueState state={previewState} tasks={visibleTasks} selectedId={selectedId} onSelect={selectMobile} onRetry={() => setPreviewState('default')} /></div></section>}
          </div>
        </div>
      </main>

      <p className="sr-only" aria-live="polite">{announcement}</p>
      <CreateTaskDialog open={createOpen} onOpenChange={setCreateOpen} onCreate={createTask} />
      <Dialog open={aboutOpen} onOpenChange={setAboutOpen}><DialogContent><DialogHeader><DialogTitle>Tasks workspace concept</DialogTitle><DialogDescription>This is a fixture-only browser concept for visual and interaction approval. It does not implement the secured reader or task commands.</DialogDescription></DialogHeader><div className="space-y-3 text-sm leading-6 text-[var(--text-secondary)]"><p className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">Search, filters, role previews, task creation, assignment, due, priority, and lifecycle buttons change only local component state. Reloading restores the original fixtures.</p><p className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">The concept intentionally excludes recurrence, subtasks, dependencies, multi-assignee work, time tracking, bulk completion, notifications, My Work, and Review.</p></div><DialogFooter><Button onClick={() => setAboutOpen(false)}>Close concept details</Button></DialogFooter></DialogContent></Dialog>
    </div>
  )
}
