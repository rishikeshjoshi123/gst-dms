'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowLeft,
  AtSign,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  CircleDashed,
  Gavel,
  Info,
  ListTodo,
  Loader2,
  LockKeyhole,
  MessageSquare,
  Moon,
  Reply,
  RotateCcw,
  Send,
  ShieldCheck,
  Sun,
  UserRound,
  X,
  XCircle,
} from 'lucide-react'

import { Avatar } from '@/components/ui/avatar'
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
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

type TaskStatus = 'open' | 'in_progress' | 'completed' | 'cancelled' | 'suspended'
type Tab = 'details' | 'comments'
type Access = 'authorised' | 'viewer'
type PageState = 'ready' | 'loading' | 'error'

type Comment = {
  id: string
  author: string
  at: string
  body: React.ReactNode
  plainBody: string
  replyTo?: { author: string; excerpt: string }
  unread?: boolean
  edited?: boolean
}

type TaskFixture = {
  id: string
  title: string
  matter: string
  description: string
  assignee: string
  creator: string
  due: string
  status: TaskStatus
  priority: 'normal' | 'high' | 'urgent'
  origin: 'Notes' | 'Tasks'
  comments: Comment[]
}

const tasks: TaskFixture[] = [
  {
    id: 'task-482',
    title: 'Verify residual invoice set before finalising the appeal grounds',
    matter: 'Apex Auto Components · FY 2023–24 ITC mismatch appeal',
    description: 'Confirm that the eleven residual invoices are present in the signed appeal bundle and record any missing evidence.',
    assignee: 'Rishikesh Joshi',
    creator: 'Meera Shah',
    due: '2 Sep 2026 · 14:30 IST',
    status: 'in_progress',
    priority: 'urgent',
    origin: 'Notes',
    comments: [
      {
        id: 'comment-1',
        author: 'Meera Shah',
        at: 'Today, 10:28',
        plainBody: 'I reconciled the residual list against the signed bundle. Please confirm the two references flagged in the working paper.',
        body: <>I reconciled the residual list against the signed bundle. <span className="rounded-[var(--radius-sm)] bg-[var(--accent-muted)] px-1 font-medium text-[var(--accent)]">@Rishikesh Joshi</span>, please confirm the two references flagged in the working paper.</>,
      },
      {
        id: 'comment-2',
        author: 'Ananya Kapoor',
        at: 'Today, 11:04',
        plainBody: 'The signed order uses the supplier invoice date, not the upload date. I have added the page references below.',
        body: 'The signed order uses the supplier invoice date, not the upload date. I have added the page references below.',
        replyTo: { author: 'Meera Shah', excerpt: 'Please confirm the two references flagged in the working paper.' },
        edited: true,
      },
      {
        id: 'comment-3',
        author: 'Rishikesh Joshi',
        at: 'Today, 12:16',
        plainBody: 'Confirmed. Both references match the signed appeal bundle; I recorded pages 41 and 43 in the working paper.',
        body: 'Confirmed. Both references match the signed appeal bundle; I recorded pages 41 and 43 in the working paper.',
        unread: true,
      },
      {
        id: 'comment-4',
        author: 'Meera Shah',
        at: 'Today, 12:31',
        plainBody: 'Thank you. Leave the task in progress until counsel confirms the final annexure numbering.',
        body: 'Thank you. Leave the task in progress until counsel confirms the final annexure numbering.',
        unread: true,
      },
    ],
  },
  {
    id: 'task-479',
    title: 'Confirm department acknowledgement number',
    matter: 'Mehta Industrial Works · DRC-01 reply and hearing',
    description: 'Locate the stamped acknowledgement and verify the number against the filing register.',
    assignee: 'Ananya Kapoor',
    creator: 'Rishikesh Joshi',
    due: '5 Sep 2026 · date only',
    status: 'open',
    priority: 'high',
    origin: 'Tasks',
    comments: [],
  },
  {
    id: 'task-470',
    title: 'Send signed authority letter to counsel',
    matter: 'Kaveri Components · FY 2024–25 ITC reconciliation',
    description: 'Share the signed authority letter after confirming the final authorised signatory.',
    assignee: 'Rishikesh Joshi',
    creator: 'Ananya Kapoor',
    due: '29 Aug 2026 · 17:00 IST',
    status: 'completed',
    priority: 'normal',
    origin: 'Tasks',
    comments: [{
      id: 'comment-complete', author: 'Ananya Kapoor', at: '29 Aug, 16:02', unread: true,
      plainBody: 'Counsel acknowledged receipt. Adding this after completion for the record; the task remains completed.',
      body: 'Counsel acknowledged receipt. Adding this after completion for the record; the task remains completed.',
    }],
  },
  {
    id: 'task-465',
    title: 'Request duplicate transport ledger',
    matter: 'Western Freight Services · E-way bill penalty response',
    description: 'The client confirmed that the requested ledger is no longer available, so this follow-up was cancelled.',
    assignee: 'Meera Shah',
    creator: 'Meera Shah',
    due: 'No due date',
    status: 'cancelled',
    priority: 'normal',
    origin: 'Tasks',
    comments: [{
      id: 'comment-cancelled', author: 'Meera Shah', at: '28 Aug, 10:11',
      plainBody: 'The task is cancelled, but comments remain available if the client later supplies additional context.',
      body: 'The task is cancelled, but comments remain available if the client later supplies additional context.',
    }],
  },
  {
    id: 'task-461',
    title: 'Review archived annexure references',
    matter: 'Kaveri Components · Classification advisory',
    description: 'This task is paused because its owning matter is in Trash.',
    assignee: 'Ananya Kapoor',
    creator: 'Rishikesh Joshi',
    due: 'No due date',
    status: 'suspended',
    priority: 'normal',
    origin: 'Tasks',
    comments: [{
      id: 'comment-suspended', author: 'Rishikesh Joshi', at: '30 Aug, 10:31',
      plainBody: 'This conversation is preserved but read-only until restore re-evaluates the task.',
      body: 'This conversation is preserved but read-only until restore re-evaluates the task.',
    }],
  },
  {
    id: 'task-458',
    title: 'Review the consolidated supplier-confirmation reconciliation workbook and the supporting annexures for the exceptionally long legal entity name used to verify responsive wrapping',
    matter: 'Shree Venkateshwara Precision Components and Renewable Energy Systems Private Limited · Consolidated supplier confirmations and reconciliation for FY 2024–25',
    description: 'Long-content fixture: the full title, matter context, reply excerpt, and comment must wrap without widening the page or displacing controls.',
    assignee: 'Rishikesh Joshi',
    creator: 'Ananya Kapoor',
    due: '12 Sep 2026 · date only',
    status: 'open',
    priority: 'normal',
    origin: 'Tasks',
    comments: [{
      id: 'comment-long', author: 'Ananya Kapoor', at: '22 Aug, 18:03', unread: true,
      plainBody: 'The reconciliation workbook spans several reporting periods and contains supplier confirmations, an exceptions schedule, annexure references, and explanatory observations. Please review the long-form note without converting it into a narrow chat bubble; it should wrap naturally, preserve the author and time context, and keep Reply reachable at every supported width.',
      body: 'The reconciliation workbook spans several reporting periods and contains supplier confirmations, an exceptions schedule, annexure references, and explanatory observations. Please review the long-form note without converting it into a narrow chat bubble; it should wrap naturally, preserve the author and time context, and keep Reply reachable at every supported width.',
    }],
  },
]

const statusLabels: Record<TaskStatus, string> = {
  open: 'Open', in_progress: 'In progress', completed: 'Completed', cancelled: 'Cancelled', suspended: 'Suspended',
}

const statusVariants: Record<TaskStatus, 'default' | 'warning' | 'success' | 'muted'> = {
  open: 'default', in_progress: 'warning', completed: 'success', cancelled: 'muted', suspended: 'warning',
}

function StatusIcon({ status }: { status: TaskStatus }) {
  const Icon = status === 'completed' ? CheckCircle2 : status === 'cancelled' ? XCircle : status === 'suspended' ? AlertTriangle : status === 'in_progress' ? Loader2 : CircleDashed
  return <Icon className={cn('size-3.5', status === 'in_progress' && 'animate-spin motion-reduce:animate-none')} aria-hidden="true" />
}

function StatusBadge({ status }: { status: TaskStatus }) {
  return <Badge variant={statusVariants[status]} fixedWidth="xl"><StatusIcon status={status} />{statusLabels[status]}</Badge>
}

function ConceptRail() {
  return (
    <div className="relative hidden h-full w-16 shrink-0 md:block">
      <aside className="group absolute inset-y-0 left-0 z-30 flex w-16 flex-col overflow-hidden border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] text-[var(--sidebar-text)] transition-[width,box-shadow] duration-[var(--duration-base)] hover:w-56 hover:shadow-[var(--shadow-xl)] focus-within:w-56 focus-within:shadow-[var(--shadow-xl)]">
        <div className="flex h-14 shrink-0 items-center border-b border-[var(--sidebar-border,var(--border))] px-4"><Gavel className="size-5 shrink-0 text-[var(--sidebar-accent)]" aria-hidden="true" /><span className="ml-3 whitespace-nowrap text-sm font-semibold text-[var(--on-sidebar)] opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">CaseChain</span></div>
        <div className="px-2 py-4"><button type="button" className="flex min-h-11 w-full items-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] px-3 text-[var(--on-sidebar)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--sidebar-accent)]" aria-current="page"><ListTodo className="size-4 shrink-0" aria-hidden="true" /><span className="ml-3 whitespace-nowrap text-sm font-medium opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100">Tasks</span></button></div>
      </aside>
    </div>
  )
}

function PreviewMenu({ access, pageState, dark, onAccess, onPageState, onDark, onAbout }: { access: Access; pageState: PageState; dark: boolean; onAccess: (access: Access) => void; onPageState: (state: PageState) => void; onDark: (dark: boolean) => void; onAbout: () => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild><Button variant="outline" size="sm"><ChevronDown className="size-4" />Preview</Button></DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60">
        <DropdownMenuLabel>Access</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={access} onValueChange={(value) => onAccess(value as Access)}><DropdownMenuRadioItem value="authorised">Authorised collaborator</DropdownMenuRadioItem><DropdownMenuRadioItem value="viewer">Viewer · read only</DropdownMenuRadioItem></DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Comments state</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={pageState} onValueChange={(value) => onPageState(value as PageState)}><DropdownMenuRadioItem value="ready">Ready</DropdownMenuRadioItem><DropdownMenuRadioItem value="loading">Loading</DropdownMenuRadioItem><DropdownMenuRadioItem value="error">Error</DropdownMenuRadioItem></DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={() => onDark(!dark)}>{dark ? <Sun className="size-4" /> : <Moon className="size-4" />}{dark ? 'Use light appearance' : 'Use dark appearance'}</DropdownMenuItem>
        <DropdownMenuItem onSelect={onAbout}><Info className="size-4" />About this concept</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function TaskList({ selectedId, onSelect }: { selectedId: string; onSelect: (id: string) => void }) {
  return <div>{tasks.map((task) => <button key={task.id} type="button" onClick={() => onSelect(task.id)} className={cn('flex min-h-[92px] w-full items-start gap-3 border-b border-[var(--border-subtle)] px-4 py-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', selectedId === task.id && 'bg-[var(--accent-muted)]')} aria-current={selectedId === task.id ? 'true' : undefined}><span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{task.title}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{task.matter}</span><span className="mt-2 block truncate text-xs text-[var(--text-secondary)]">{task.assignee} · {task.due}</span></span><span className="flex shrink-0 flex-col items-end gap-2"><StatusBadge status={task.status} />{task.comments.some((comment) => comment.unread) && <span className="flex items-center gap-1 text-xs font-medium text-[var(--accent)]"><MessageSquare className="size-3.5" aria-hidden="true" />New</span>}</span></button>)}</div>
}

function EmptyComments() {
  return <div className="grid min-h-full place-items-center p-6 text-center"><div><MessageSquare className="mx-auto size-8 text-[var(--text-muted)]" aria-hidden="true" /><h3 className="mt-3 text-section-heading">No comments yet</h3><p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-[var(--text-muted)]">This task was created directly in Tasks, so its conversation starts empty. Notes messages are never copied here.</p></div></div>
}

function UnreadDivider({ count }: { count: number }) {
  return <div className="flex items-center gap-3" role="separator" aria-label={`${count} unread comments`}><span className="h-px flex-1 bg-[var(--border-subtle)]" /><span className="rounded-[var(--radius-full)] bg-[var(--accent-muted)] px-3 py-1 text-xs font-semibold text-[var(--accent)]">{count} new {count === 1 ? 'comment' : 'comments'}</span><span className="h-px flex-1 bg-[var(--border-subtle)]" /></div>
}

function CommentFeed({ comments, canReply, onReply }: { comments: Comment[]; canReply: boolean; onReply: (comment: Comment) => void }) {
  if (!comments.length) return <EmptyComments />
  const firstUnread = comments.findIndex((comment) => comment.unread)
  const unreadCount = comments.filter((comment) => comment.unread).length
  return <div className="mx-auto w-full max-w-3xl space-y-5 p-4 sm:p-5">{comments.map((comment, index) => <div key={comment.id}>{index === firstUnread && <div className="mb-5"><UnreadDivider count={unreadCount} /></div>}<article className="flex min-w-0 gap-3"><Avatar name={comment.author} size="sm" /><div className="min-w-0 flex-1"><div className="flex flex-wrap items-baseline gap-x-2 gap-y-1"><h3 className="text-sm font-semibold">{comment.author}</h3><time className="text-xs text-[var(--text-muted)]">{comment.at}</time>{comment.edited && <span className="text-xs text-[var(--text-muted)]">Edited</span>}</div>{comment.replyTo && <div className="mt-2 rounded-[var(--radius-sm)] border-l-2 border-[var(--border-strong)] bg-[var(--bg)] px-3 py-2"><p className="text-xs font-medium text-[var(--text-secondary)]">Replying to {comment.replyTo.author}</p><p className="mt-0.5 line-clamp-2 text-xs leading-5 text-[var(--text-muted)]">{comment.replyTo.excerpt}</p></div>}<p className="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-[var(--text-secondary)]">{comment.body}</p>{canReply && <Button variant="link" size="sm" className="mt-1 min-h-11 text-xs" onClick={() => onReply(comment)}><Reply className="size-3.5" />Reply</Button>}</div></article></div>)}</div>
}

function CommentsLoading() {
  return <div className="mx-auto w-full max-w-3xl space-y-6 p-5" aria-busy="true"><p className="sr-only">Loading task comments…</p>{[1, 2, 3].map((item) => <div key={item} className="flex gap-3" aria-hidden="true"><Skeleton className="size-8 shrink-0 rounded-[var(--radius-full)]" /><div className="min-w-0 flex-1"><Skeleton className="h-3.5 w-36" /><Skeleton className="mt-3 h-3.5 w-full" /><Skeleton className="mt-2 h-3.5 w-4/5" /></div></div>)}</div>
}

function CommentsError({ onRetry }: { onRetry: () => void }) {
  return <div className="grid min-h-full place-items-center p-6 text-center" role="alert"><div><CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" /><h3 className="mt-3 text-section-heading">Comments could not be displayed</h3><p className="mx-auto mt-2 max-w-sm text-sm text-[var(--text-muted)]">The task is still available. Try loading only this conversation again.</p><Button variant="outline" className="mt-4" onClick={onRetry}><RotateCcw className="size-4" />Try again</Button></div></div>
}

function DetailTab({ task }: { task: TaskFixture }) {
  return <div className="mx-auto w-full max-w-3xl p-4 sm:p-5"><div className="grid grid-cols-1 gap-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 min-[420px]:grid-cols-2"><div><p className="text-caption text-[var(--text-muted)]">Assignee</p><p className="mt-1 text-sm font-medium">{task.assignee}</p></div><div><p className="text-caption text-[var(--text-muted)]">Due</p><p className="mt-1 font-mono text-sm font-medium">{task.due}</p></div><div><p className="text-caption text-[var(--text-muted)]">Priority</p><p className={cn('mt-1 text-sm font-medium capitalize', task.priority === 'urgent' && 'text-[var(--danger)]', task.priority === 'high' && 'text-[var(--warning)]')}>{task.priority}</p></div><div><p className="text-caption text-[var(--text-muted)]">Created by</p><p className="mt-1 text-sm font-medium">{task.creator}</p></div></div><section className="mt-5" aria-labelledby="concept-description"><h3 id="concept-description" className="text-sm font-semibold">Description</h3><p className="mt-2 break-words text-sm leading-6 text-[var(--text-secondary)]">{task.description}</p></section><section className="mt-5" aria-labelledby="concept-origin"><h3 id="concept-origin" className="text-sm font-semibold">Origin</h3><p className="mt-2 text-sm text-[var(--text-secondary)]">Created in {task.origin}. {task.origin === 'Notes' ? 'The exact source message remains linked, but its surrounding Notes thread is not copied into Comments.' : 'This task began with an independent, empty Comments stream.'}</p></section><section className="mt-5" aria-labelledby="concept-history"><div className="flex items-center justify-between"><h3 id="concept-history" className="text-sm font-semibold">Task history</h3><span className="text-xs text-[var(--text-muted)]">Newest first</span></div><ol className="mt-3 space-y-4 border-l border-[var(--border)] pl-4"><li><p className="text-sm font-medium">Status is {statusLabels[task.status]}</p><p className="text-xs text-[var(--text-muted)]">Task-domain transition · comments remain separate</p></li><li><p className="text-sm font-medium">Task created in {task.origin}</p><p className="text-xs text-[var(--text-muted)]">By {task.creator}</p></li></ol></section></div>
}

function Composer({ replyTo, value, onChange, onCancelReply, onSend }: { replyTo: Comment | null; value: string; onChange: (value: string) => void; onCancelReply: () => void; onSend: () => void }) {
  const members = ['Rishikesh Joshi', 'Meera Shah', 'Ananya Kapoor']
  const match = value.match(/@([\p{L}\p{N}._-]*)$/u)
  const query = match?.[1] ?? null
  const choices = query === null ? [] : members.filter((member) => member.toLowerCase().includes(query.toLowerCase()))
  const focusInput = () => requestAnimationFrame(() => document.getElementById('task-comments-message')?.focus())
  const mention = () => { onChange(`${value}${value && !value.endsWith(' ') ? ' ' : ''}@`); focusInput() }
  const choose = (member: string) => { if (!match || match.index === undefined) return; onChange(`${value.slice(0, match.index)}@${member} `); focusInput() }
  return <div className="relative shrink-0 border-t border-[var(--border-subtle)] bg-[var(--bg)] p-3">{query !== null && <div role="listbox" aria-label="Mention a task collaborator" className="absolute bottom-[116px] left-3 z-20 w-[min(19rem,calc(100vw-1.5rem))] rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-md)]"><p className="border-b border-[var(--border-subtle)] px-3 py-2 text-xs text-[var(--text-muted)]">Accessible task collaborators</p>{choices.length ? choices.map((member) => <button type="button" role="option" aria-selected="false" key={member} onMouseDown={(event) => event.preventDefault()} onClick={() => choose(member)} className="flex min-h-11 w-full items-center gap-2 rounded-[var(--radius-sm)] px-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><Avatar name={member} size="xs" /><span className="text-sm font-medium">{member}</span></button>) : <p className="px-3 py-4 text-sm text-[var(--text-muted)]">No accessible members found</p>}</div>}<div className="mx-auto max-w-3xl overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] focus-within:ring-2 focus-within:ring-[var(--accent-ring)]">{replyTo && <div className="flex items-start gap-2 border-b border-[var(--border-subtle)] px-3 py-2"><div className="min-w-0 flex-1"><p className="text-xs font-medium">Replying to {replyTo.author}</p><p className="truncate text-xs text-[var(--text-muted)]">{replyTo.plainBody}</p></div><Button variant="ghost" size="icon" className="-my-1 -mr-2" aria-label="Cancel reply" onClick={onCancelReply}><X className="size-4" /></Button></div>}<Label htmlFor="task-comments-message" className="sr-only">Write a task comment</Label><textarea id="task-comments-message" value={value} onChange={(event) => onChange(event.target.value)} onKeyDown={(event) => { if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); onSend() } }} placeholder="Write a comment… Type @ to mention someone" className="min-h-16 w-full resize-none bg-transparent px-3 pt-3 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)]" /><div className="flex items-center gap-1 border-t border-[var(--border-subtle)] px-2 py-1.5"><Button variant="ghost" size="sm" onClick={mention}><AtSign className="size-4" />Mention</Button><span className="hidden text-xs text-[var(--text-muted)] sm:inline">Comments do not change task status.</span><Button size="sm" className="ml-auto" onClick={onSend} disabled={!value.trim()}><Send className="size-4" />Send</Button></div></div></div>
}

function ReadOnlyFooter({ suspended }: { suspended: boolean }) {
  return <div className={cn('shrink-0 border-t border-[var(--border-subtle)] p-3 text-sm', suspended ? 'bg-[var(--warning-muted)]' : 'bg-[var(--bg)]')}><div className="mx-auto flex max-w-3xl items-start gap-2"><LockKeyhole className={cn('mt-0.5 size-4 shrink-0', suspended ? 'text-[var(--warning)]' : 'text-[var(--text-muted)]')} aria-hidden="true" /><p className="text-[var(--text-secondary)]">{suspended ? 'Comments are preserved but read-only while the owning matter is in Trash. Restore must re-evaluate the task before writing resumes.' : 'Your Viewer role can read this conversation but cannot post, reply, edit, or remove comments.'}</p></div></div>
}

function TaskPane({ task, tab, access, pageState, mobile, onTab, onBack, onRetry }: { task: TaskFixture; tab: Tab; access: Access; pageState: PageState; mobile: boolean; onTab: (tab: Tab) => void; onBack: () => void; onRetry: () => void }) {
  const [replyTo, setReplyTo] = useState<Comment | null>(null)
  const [draft, setDraft] = useState('')
  const [localComments, setLocalComments] = useState<Record<string, Comment[]>>({})
  const comments = localComments[task.id] ?? task.comments
  const readOnly = access === 'viewer' || task.status === 'suspended'
  const tabRefs = useRef<Record<Tab, HTMLButtonElement | null>>({ details: null, comments: null })
  const send = () => { if (!draft.trim() || readOnly) return; const comment: Comment = { id: `fixture-${Date.now()}`, author: 'Rishikesh Joshi', at: 'Just now · fixture only', plainBody: draft.trim(), body: draft.trim(), replyTo: replyTo ? { author: replyTo.author, excerpt: replyTo.plainBody } : undefined }; setLocalComments((current) => ({ ...current, [task.id]: [...comments, comment] })); setDraft(''); setReplyTo(null) }
  const changeTab = (next: Tab) => { onTab(next); requestAnimationFrame(() => tabRefs.current[next]?.focus()) }
  return <section aria-label={`Task workspace for ${task.title}`} className="flex h-full min-h-0 min-w-0 flex-1 flex-col bg-[var(--surface)]">{mobile && <div className="flex min-h-12 shrink-0 items-center border-b border-[var(--border-subtle)] px-2"><Button variant="ghost" size="sm" onClick={onBack}><ArrowLeft className="size-4" />Back to tasks</Button>{access === 'viewer' && <span className="ml-auto flex items-center gap-1 text-xs text-[var(--text-muted)]"><ShieldCheck className="size-3.5" />Read only</span>}</div>}<header className="shrink-0 border-b border-[var(--border-subtle)] px-4 py-3 sm:px-5"><div className="flex min-w-0 items-start gap-3"><span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><ListTodo className="size-4" aria-hidden="true" /></span><div className="min-w-0 flex-1"><h2 className="break-words text-base font-semibold leading-6">{task.title}</h2><p className="mt-0.5 break-words text-xs text-[var(--text-muted)]">{task.matter}</p></div><StatusBadge status={task.status} /></div>{(task.status === 'completed' || task.status === 'cancelled') && <p className="mt-2 pl-12 text-xs text-[var(--text-muted)]">This terminal task remains commentable; adding context does not reopen it.</p>}</header><div className="flex min-h-11 shrink-0 items-stretch border-b border-[var(--border-subtle)] px-2" role="tablist" aria-label="Task sections">{(['details', 'comments'] as Tab[]).map((item) => { const selected = tab === item; const label = item === 'details' ? 'Task details' : 'Comments'; const Icon = item === 'details' ? ListTodo : MessageSquare; return <button ref={(node) => { tabRefs.current[item] = node }} key={item} type="button" role="tab" aria-selected={selected} aria-controls={`task-comments-${item}-panel`} tabIndex={selected ? 0 : -1} onClick={() => onTab(item)} onKeyDown={(event) => { if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); changeTab(item === 'details' ? 'comments' : 'details') } }} className={cn('relative flex min-h-11 items-center gap-2 px-3 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', selected ? 'text-[var(--text-primary)] after:absolute after:inset-x-3 after:bottom-0 after:h-0.5 after:bg-[var(--accent)]' : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]')}><Icon className="size-4" aria-hidden="true" />{label}{item === 'comments' && comments.some((comment) => comment.unread) && <span className="size-2 rounded-[var(--radius-full)] bg-[var(--accent)]" aria-label="Unread comments" />}</button> })}<span className="ml-auto hidden items-center text-xs text-[var(--text-muted)] sm:flex">{task.origin === 'Notes' ? 'Linked origin · separate conversation' : 'Direct task · independent conversation'}</span></div><div id={`task-comments-${tab}-panel`} role="tabpanel" tabIndex={0} className="min-h-0 flex-1 overflow-y-auto overscroll-contain">{tab === 'details' ? <DetailTab task={task} /> : pageState === 'loading' ? <CommentsLoading /> : pageState === 'error' ? <CommentsError onRetry={onRetry} /> : <CommentFeed comments={comments} canReply={!readOnly} onReply={(comment) => { setReplyTo(comment); requestAnimationFrame(() => document.getElementById('task-comments-message')?.focus()) }} />}</div>{tab === 'comments' && pageState === 'ready' && (readOnly ? <ReadOnlyFooter suspended={task.status === 'suspended'} /> : <Composer replyTo={replyTo} value={draft} onChange={setDraft} onCancelReply={() => setReplyTo(null)} onSend={send} />)}</section>
}

export function TaskCommentsConcept() {
  const [selectedId, setSelectedId] = useState(tasks[0].id)
  const [tab, setTab] = useState<Tab>('comments')
  const [mobileDetail, setMobileDetail] = useState(true)
  const [access, setAccess] = useState<Access>('authorised')
  const [pageState, setPageState] = useState<PageState>('ready')
  const [dark, setDark] = useState(false)
  const [aboutOpen, setAboutOpen] = useState(false)
  const selected = useMemo(() => tasks.find((task) => task.id === selectedId) ?? tasks[0], [selectedId])

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const taskId = params.get('task')
    requestAnimationFrame(() => {
      if (taskId && tasks.some((task) => task.id === taskId)) setSelectedId(taskId)
      if (params.get('tab') === 'details') setTab('details')
    })
  }, [])

  const updateRoute = (taskId: string, nextTab: Tab) => { const url = new URL(window.location.href); url.searchParams.set('task', taskId); url.searchParams.set('tab', nextTab); window.history.replaceState(null, '', `${url.pathname}${url.search}`) }
  const selectTask = (id: string) => { setSelectedId(id); setTab('comments'); setMobileDetail(true); setPageState('ready'); updateRoute(id, 'comments') }
  const changeTab = (next: Tab) => { setTab(next); updateRoute(selected.id, next) }

  return <div className={cn(dark && 'dark')}><div className="flex h-dvh max-w-full overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]"><ConceptRail /><main className="flex min-w-0 flex-1 flex-col overflow-hidden"><header className="flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border)] bg-[var(--surface)] px-3 sm:px-5"><div className="flex min-w-0 items-center gap-2"><ListTodo className="size-4 text-[var(--accent)] md:hidden" aria-hidden="true" /><span className="hidden text-sm text-[var(--text-muted)] sm:inline">Apex Tax Advocates</span><ChevronRight className="hidden size-3.5 text-[var(--text-muted)] sm:block" aria-hidden="true" /><h1 className="truncate text-sm font-semibold">Task comments concept</h1></div><div className="ml-auto flex items-center gap-2"><Badge variant="outline" className="hidden sm:inline-flex">Fixture only</Badge><PreviewMenu access={access} pageState={pageState} dark={dark} onAccess={setAccess} onPageState={setPageState} onDark={setDark} onAbout={() => setAboutOpen(true)} /></div></header><div className="min-h-0 flex-1 overflow-hidden"><div className="hidden h-full min-h-0 xl:flex"><aside aria-label="Task fixtures" className="flex w-[25rem] shrink-0 flex-col border-r border-[var(--border)] bg-[var(--surface)]"><div className="shrink-0 border-b border-[var(--border-subtle)] px-4 py-3"><p className="text-sm font-semibold">Task scenarios</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">Select lifecycle, empty, or long-content fixtures.</p></div><div className="min-h-0 flex-1 overflow-y-auto overscroll-contain"><TaskList selectedId={selected.id} onSelect={selectTask} /></div></aside><TaskPane task={selected} tab={tab} access={access} pageState={pageState} mobile={false} onTab={changeTab} onBack={() => undefined} onRetry={() => setPageState('ready')} /></div><div className="h-full min-h-0 xl:hidden">{mobileDetail ? <TaskPane task={selected} tab={tab} access={access} pageState={pageState} mobile onTab={changeTab} onBack={() => setMobileDetail(false)} onRetry={() => setPageState('ready')} /> : <section aria-label="Task fixtures" className="flex h-full min-h-0 flex-col bg-[var(--surface)]"><div className="shrink-0 border-b border-[var(--border-subtle)] px-4 py-3"><p className="text-sm font-semibold">Task scenarios</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">Select a task to review its details and comments.</p></div><div className="min-h-0 flex-1 overflow-y-auto overscroll-contain"><TaskList selectedId={selected.id} onSelect={selectTask} /></div></section>}</div></div></main><Dialog open={aboutOpen} onOpenChange={setAboutOpen}><DialogContent><DialogHeader><DialogTitle>Task Comments concept</DialogTitle><DialogDescription>This local review surface uses fixture data only. Nothing is saved or sent.</DialogDescription></DialogHeader><div className="space-y-3 text-sm leading-6 text-[var(--text-secondary)]"><p>Comments are a task-scoped conversation beside Task details. They borrow the chronological Notes feed and composer rhythm without copying Notes messages.</p><p>Use the task list to inspect direct-task empty state, completed and cancelled commentability, suspended read-only behavior, and long wrapping. Preview exposes authorised, Viewer, loading, error, light, and dark states.</p><p className="flex items-start gap-2"><UserRound className="mt-1 size-4 shrink-0" aria-hidden="true" />There is deliberately no Create task action inside the composer.</p></div><DialogFooter><Button onClick={() => setAboutOpen(false)}>Close</Button></DialogFooter></DialogContent></Dialog></div></div>
}
