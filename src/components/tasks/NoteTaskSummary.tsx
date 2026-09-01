'use client'

import Link from 'next/link'
import { AlertTriangle, ArrowUpRight, CalendarDays, ListTodo, UserRound } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import type { Database } from '@/lib/supabase/database.types'

export type NoteTaskSummaryValue = Database['public']['Functions']['get_note_task_summaries']['Returns'][number]

const statusLabels: Record<Database['public']['Enums']['task_status'], string> = {
  open: 'Open',
  in_progress: 'In progress',
  completed: 'Completed',
  cancelled: 'Cancelled',
  suspended: 'Suspended',
}

const statusVariants: Record<Database['public']['Enums']['task_status'], 'default' | 'success' | 'muted' | 'warning'> = {
  open: 'default',
  in_progress: 'warning',
  completed: 'success',
  cancelled: 'muted',
  suspended: 'warning',
}

function formatDue(summary: NoteTaskSummaryValue) {
  if (!summary.due_date) return 'No due date'
  const date = new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(new Date(`${summary.due_date}T12:00:00Z`))
  if (!summary.due_time) return date
  return `${date} · ${summary.due_time.slice(0, 5)}${summary.due_timezone ? ` · ${summary.due_timezone}` : ''}`
}

export function NoteTaskSummary({
  summary,
  assigneeLabel,
}: {
  summary: NoteTaskSummaryValue | null | undefined
  assigneeLabel?: string | null
}) {
  if (!summary) {
    return (
      <div className="mt-3 rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--bg)] p-3">
        <div className="flex items-start gap-2">
          <AlertTriangle className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" />
          <div className="min-w-0">
            <p className="text-sm font-semibold">Linked task unavailable</p>
            <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">
              Current task status and details cannot be shown. This note remains the immutable origin.
            </p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="mt-3 rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--bg)] p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="flex items-center gap-2 text-sm font-semibold">
          <ListTodo className="size-4 text-[var(--primary)]" aria-hidden="true" />
          Linked task
        </span>
        <Badge className="ml-auto" variant={statusVariants[summary.status]} fixedWidth="xl">
          {statusLabels[summary.status]}
        </Badge>
      </div>
      <div className="mt-3 grid gap-2 text-xs text-[var(--text-secondary)] sm:grid-cols-2">
        <span className="flex min-w-0 items-center gap-2">
          <UserRound className="size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
          <span className="truncate">{summary.assignee_user_id ? assigneeLabel || 'Assigned team member' : 'Unassigned'}</span>
        </span>
        <span className="flex min-w-0 items-center gap-2 font-mono">
          <CalendarDays className="size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
          <span className="min-w-0 break-words">{formatDue(summary)}</span>
        </span>
      </div>
      <Link
        href={`/tasks?task=${encodeURIComponent(summary.task_id)}&tab=details`}
        className="mt-3 inline-flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium text-[var(--text-primary)] outline-none transition-colors hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
      >
        Open task
        <ArrowUpRight className="size-4" aria-hidden="true" />
      </Link>
    </div>
  )
}
