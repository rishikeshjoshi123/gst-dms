'use client'

import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from 'react'
import {
  AtSign,
  CircleAlert,
  LockKeyhole,
  MessageSquare,
  Reply,
  RotateCcw,
  Send,
  X,
} from 'lucide-react'
import { toast } from 'sonner'

import { Avatar } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import {
  getTaskCommentThread,
  getTaskComments,
  postTaskComment,
  type TaskComment,
  type TaskCommentThread,
  type TaskDetail,
  type TaskWorkspaceContext,
} from '@/lib/actions/tasks'
import { cn } from '@/lib/utils'
import { mentionedUserIdsInBody } from './task-model'

type CommentsReadState = 'idle' | 'loading' | 'ready' | 'error'
type Mention = { id: string; label: string }

function personLabel(context: TaskWorkspaceContext, userId: string) {
  return context.people.find((person) => person.id === userId)?.label || 'Former team member'
}

function formatCommentTime(value: string) {
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value))
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function CommentBody({ comment, context }: { comment: TaskComment; context: TaskWorkspaceContext }) {
  const mentions = comment.mentioned_user_ids
    .map((id) => ({ id, label: personLabel(context, id) }))
    .filter((mention) => mention.label !== 'Former team member')
    .sort((left, right) => right.label.length - left.label.length)

  if (!mentions.length) {
    return <p className="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-[var(--text-secondary)]">{comment.body}</p>
  }

  const labels = [...new Set(mentions.map((mention) => mention.label))]
  const expression = new RegExp(`(@(?:${labels.map(escapeRegExp).join('|')}))`, 'gi')
  const mentionByToken = new Map(mentions.map((mention) => [`@${mention.label}`.toLocaleLowerCase(), mention]))

  return (
    <p className="mt-1 whitespace-pre-wrap break-words text-sm leading-6 text-[var(--text-secondary)]">
      {comment.body.split(expression).map((part, index) => {
        const mention = mentionByToken.get(part.toLocaleLowerCase())
        return mention ? (
          <span
            key={`${mention.id}-${index}`}
            className="rounded-[var(--radius-sm)] bg-[var(--accent-muted)] px-1 font-medium text-[var(--primary)]"
            aria-label={`Mentioned ${mention.label}`}
          >
            {part}
          </span>
        ) : <span key={index}>{part}</span>
      })}
    </p>
  )
}

function EmptyComments() {
  return (
    <div className="grid min-h-full place-items-center p-6 text-center">
      <div>
        <MessageSquare className="mx-auto size-8 text-[var(--text-muted)]" aria-hidden="true" />
        <h3 className="mt-3 text-section-heading">No comments yet</h3>
        <p className="mx-auto mt-2 max-w-sm text-sm leading-6 text-[var(--text-muted)]">
          Start a task-scoped conversation here. Messages from the originating Note are never copied into Comments.
        </p>
      </div>
    </div>
  )
}

function UnreadDivider({ count }: { count: number }) {
  return (
    <div className="flex items-center gap-3" role="separator" aria-label={`${count} unread comments`}>
      <span className="h-px flex-1 bg-[var(--border-subtle)]" />
      <span className="rounded-[var(--radius-full)] bg-[var(--accent-muted)] px-3 py-1 text-xs font-semibold text-[var(--primary)]">
        {count} new {count === 1 ? 'comment' : 'comments'}
      </span>
      <span className="h-px flex-1 bg-[var(--border-subtle)]" />
    </div>
  )
}

function CommentFeed({
  comments,
  thread,
  context,
  canReply,
  onReply,
}: {
  comments: TaskComment[]
  thread: TaskCommentThread | null
  context: TaskWorkspaceContext
  canReply: boolean
  onReply: (comment: TaskComment) => void
}) {
  if (!comments.length) return <EmptyComments />

  const commentById = new Map(comments.map((comment) => [comment.comment_id, comment]))
  const firstUnreadIndex = thread && thread.unread_count > 0
    ? comments.findIndex((comment) => comment.sequence > thread.observed_sequence)
    : -1

  return (
    <div className="mx-auto w-full max-w-3xl space-y-5 p-4 sm:p-5">
      {comments.map((comment, index) => {
        const replyTarget = comment.reply_to_comment_id ? commentById.get(comment.reply_to_comment_id) : null
        return (
          <div key={comment.comment_id}>
            {index === firstUnreadIndex && thread && <div className="mb-5"><UnreadDivider count={thread.unread_count} /></div>}
            <article className="flex min-w-0 gap-3" aria-labelledby={`task-comment-author-${comment.comment_id}`}>
              <Avatar name={personLabel(context, comment.author_user_id)} size="sm" />
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                  <h3 id={`task-comment-author-${comment.comment_id}`} className="text-sm font-semibold">
                    {personLabel(context, comment.author_user_id)}
                  </h3>
                  <time dateTime={comment.created_at} className="text-xs text-[var(--text-muted)]">
                    {formatCommentTime(comment.created_at)}
                  </time>
                </div>
                {comment.reply_to_comment_id && (
                  <div className="mt-2 rounded-[var(--radius-sm)] border-l-2 border-[var(--border-strong)] bg-[var(--bg)] px-3 py-2">
                    <p className="text-xs font-medium text-[var(--text-secondary)]">
                      Replying to {replyTarget ? personLabel(context, replyTarget.author_user_id) : `comment ${comment.reply_to_sequence ?? ''}`.trim()}
                    </p>
                    <p className="mt-0.5 line-clamp-2 break-words text-xs leading-5 text-[var(--text-muted)]">
                      {replyTarget?.body || 'The earlier comment is outside this loaded conversation view.'}
                    </p>
                  </div>
                )}
                <CommentBody comment={comment} context={context} />
                {canReply && (
                  <Button variant="link" size="sm" className="mt-1 min-h-11 text-xs" onClick={() => onReply(comment)}>
                    <Reply className="size-3.5" aria-hidden="true" />Reply
                  </Button>
                )}
              </div>
            </article>
          </div>
        )
      })}
    </div>
  )
}

function CommentsLoading() {
  return (
    <div className="mx-auto w-full max-w-3xl space-y-6 p-5" aria-busy="true">
      <p className="sr-only">Loading task comments…</p>
      {[1, 2, 3].map((item) => (
        <div key={item} className="flex gap-3" aria-hidden="true">
          <Skeleton className="size-8 shrink-0 rounded-[var(--radius-full)]" />
          <div className="min-w-0 flex-1"><Skeleton className="h-3.5 w-36" /><Skeleton className="mt-3 h-3.5 w-full" /><Skeleton className="mt-2 h-3.5 w-4/5" /></div>
        </div>
      ))}
    </div>
  )
}

function CommentsError({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="grid min-h-full place-items-center p-6 text-center" role="alert">
      <div>
        <CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" />
        <h3 className="mt-3 text-section-heading">Comments could not be displayed</h3>
        <p className="mx-auto mt-2 max-w-sm text-sm text-[var(--text-muted)]">The task is still available. Try loading only this conversation again.</p>
        <Button variant="outline" className="mt-4" onClick={onRetry}><RotateCcw className="size-4" aria-hidden="true" />Try again</Button>
      </div>
    </div>
  )
}

async function readCommentSnapshot(taskId: string) {
  const thread = await getTaskCommentThread(taskId)
  if (!thread) return { thread: null, comments: [] as TaskComment[] }

  const comments: TaskComment[] = []
  let afterSequence = 0
  while (afterSequence < thread.latest_sequence) {
    const page = await getTaskComments({ taskId, afterSequence, limit: 200 })
    if (!page.length) break
    comments.push(...page)
    const nextSequence = page[page.length - 1]?.sequence ?? afterSequence
    if (nextSequence <= afterSequence) break
    afterSequence = nextSequence
  }
  return { thread, comments }
}

function Composer({
  taskId,
  context,
  replyTo,
  pending,
  error,
  onCancelReply,
  onSubmit,
}: {
  taskId: string
  context: TaskWorkspaceContext
  replyTo: TaskComment | null
  pending: boolean
  error: string
  onCancelReply: () => void
  onSubmit: (input: { body: string; mentionedUserIds: string[] }) => void
}) {
  const [draft, setDraft] = useState('')
  const [mentionStart, setMentionStart] = useState<number | null>(null)
  const [selectedMentions, setSelectedMentions] = useState<Mention[]>([])
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const mentionListId = `task-comment-mentions-${taskId}`
  const mentionQuery = mentionStart === null ? null : draft.slice(mentionStart + 1)
  const duplicateLabels = useMemo(() => {
    const counts = new Map<string, number>()
    context.people.forEach((person) => counts.set(person.label, (counts.get(person.label) ?? 0) + 1))
    return counts
  }, [context.people])
  const choices = mentionQuery === null ? [] : context.people.filter((person) => person.label.toLocaleLowerCase().includes(mentionQuery.trim().toLocaleLowerCase()))

  const focusComposer = () => requestAnimationFrame(() => textareaRef.current?.focus())
  const openMentionPicker = () => {
    const prefix = draft && !draft.endsWith(' ') && !draft.endsWith('\n') ? ' ' : ''
    const next = `${draft}${prefix}@`
    setDraft(next)
    setMentionStart(next.length - 1)
    focusComposer()
  }
  const chooseMention = (mention: Mention) => {
    if (mentionStart === null) return
    setDraft(`${draft.slice(0, mentionStart)}@${mention.label} `)
    setSelectedMentions((current) => current.some((item) => item.id === mention.id) ? current : [...current, mention])
    setMentionStart(null)
    focusComposer()
  }
  const submit = () => {
    const body = draft.trim()
    if (!body || pending) return
    onSubmit({ body, mentionedUserIds: mentionedUserIdsInBody(body, selectedMentions) })
  }

  return (
    <div className="relative shrink-0 border-t border-[var(--border-subtle)] bg-[var(--bg)] p-3">
      {mentionQuery !== null && (
        <div id={mentionListId} role="listbox" aria-label="Mention an active task collaborator" className="absolute bottom-[116px] left-3 z-20 max-h-64 w-[min(19rem,calc(100vw-1.5rem))] overflow-y-auto rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-md)]">
          <p className="border-b border-[var(--border-subtle)] px-3 py-2 text-xs text-[var(--text-muted)]">Active task collaborators</p>
          {choices.length ? choices.map((person) => (
            <button
              type="button"
              role="option"
              aria-selected={selectedMentions.some((mention) => mention.id === person.id)}
              key={person.id}
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => chooseMention({ id: person.id, label: person.label })}
              className="flex min-h-11 w-full items-center gap-2 rounded-[var(--radius-sm)] px-3 text-left outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
            >
              <Avatar name={person.label} size="xs" />
              <span className="min-w-0 text-sm font-medium"><span className="block truncate">{person.label}</span>{(duplicateLabels.get(person.label) ?? 0) > 1 && <span className="block font-mono text-xs text-[var(--text-muted)]">Member {person.id.slice(0, 8)}</span>}</span>
            </button>
          )) : <p className="px-3 py-4 text-sm text-[var(--text-muted)]">No active members found</p>}
        </div>
      )}
      <div className="mx-auto max-w-3xl overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] focus-within:ring-2 focus-within:ring-[var(--accent-ring)]">
        {replyTo && (
          <div className="flex items-start gap-2 border-b border-[var(--border-subtle)] px-3 py-2">
            <div className="min-w-0 flex-1"><p className="text-xs font-medium">Replying to {personLabel(context, replyTo.author_user_id)}</p><p className="truncate text-xs text-[var(--text-muted)]">{replyTo.body}</p></div>
            <Button variant="ghost" size="icon" className="-my-1 -mr-2" aria-label="Cancel reply" onClick={onCancelReply}><X className="size-4" aria-hidden="true" /></Button>
          </div>
        )}
        <Label htmlFor={`task-comments-message-${taskId}`} className="sr-only">Write a task comment</Label>
        <textarea
          ref={textareaRef}
          id={`task-comments-message-${taskId}`}
          value={draft}
          maxLength={20000}
          onChange={(event) => {
            const next = event.target.value
            setDraft(next)
            const at = next.lastIndexOf('@')
            const suffix = at >= 0 ? next.slice(at + 1) : ''
            setMentionStart(at >= 0 && !suffix.includes('\n') && suffix.length <= 80 ? at : null)
          }}
          onKeyDown={(event) => {
            if (event.key === 'Escape' && mentionStart !== null) {
              event.preventDefault()
              setMentionStart(null)
            } else if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
              event.preventDefault()
              submit()
            }
          }}
          role="combobox"
          aria-autocomplete="list"
          aria-haspopup="listbox"
          aria-expanded={mentionQuery !== null}
          aria-controls={mentionQuery !== null ? mentionListId : undefined}
          aria-describedby={error ? `task-comment-error-${taskId}` : undefined}
          placeholder="Write a comment… Type @ to mention someone"
          className="min-h-16 w-full resize-none bg-transparent px-3 pt-3 text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-muted)]"
        />
        {error && <p id={`task-comment-error-${taskId}`} role="alert" className="px-3 pb-2 text-xs text-[var(--danger)]">{error}</p>}
        <div className="flex items-center gap-1 border-t border-[var(--border-subtle)] px-2 py-1.5">
          <Button variant="ghost" size="sm" onClick={openMentionPicker} disabled={pending}><AtSign className="size-4" aria-hidden="true" />Mention</Button>
          <span className="hidden text-xs text-[var(--text-muted)] sm:inline">Comments do not change task status.</span>
          <Button size="sm" className="ml-auto" onClick={submit} loading={pending} disabled={!draft.trim()}><Send className="size-4" aria-hidden="true" />Send</Button>
        </div>
      </div>
    </div>
  )
}

function ReadOnlyFooter({ suspended }: { suspended: boolean }) {
  return (
    <div className={cn('shrink-0 border-t border-[var(--border-subtle)] p-3 text-sm', suspended ? 'bg-[var(--warning-muted)]' : 'bg-[var(--bg)]')}>
      <div className="mx-auto flex max-w-3xl items-start gap-2">
        <LockKeyhole className={cn('mt-0.5 size-4 shrink-0', suspended ? 'text-[var(--warning)]' : 'text-[var(--text-muted)]')} aria-hidden="true" />
        <p className="text-[var(--text-secondary)]">{suspended ? 'Comments are preserved but read-only while this task is suspended.' : 'Your Viewer role can read this conversation but cannot post or reply.'}</p>
      </div>
    </div>
  )
}

export function TaskCommentsPanel({
  task,
  context,
  active,
  initialLoaded,
  initialThread,
  initialComments,
  initialReaderError,
  onUnreadCountChange,
}: {
  task: TaskDetail
  context: TaskWorkspaceContext
  active: boolean
  initialLoaded: boolean
  initialThread: TaskCommentThread | null
  initialComments: TaskComment[]
  initialReaderError: boolean
  onUnreadCountChange: (count: number) => void
}) {
  const [thread, setThread] = useState(initialThread)
  const [comments, setComments] = useState(initialComments)
  const [readState, setReadState] = useState<CommentsReadState>(initialReaderError ? 'error' : initialLoaded ? 'ready' : 'idle')
  const [replyTo, setReplyTo] = useState<TaskComment | null>(null)
  const [postError, setPostError] = useState('')
  const [isPosting, startPosting] = useTransition()
  const postAttemptRef = useRef<{ fingerprint: string; key: string } | null>(null)
  const initialLoadRequestedRef = useRef(false)
  const scrollerRef = useRef<HTMLDivElement>(null)
  const canComment = context.canManage && task.status !== 'suspended'

  const loadComments = useCallback(async () => {
    setReadState('loading')
    try {
      const snapshot = await readCommentSnapshot(task.task_id)
      setThread(snapshot.thread)
      setComments(snapshot.comments)
      setReadState('ready')
      onUnreadCountChange(snapshot.thread?.unread_count ?? 0)
      return true
    } catch {
      setReadState('error')
      return false
    }
  }, [onUnreadCountChange, task.task_id])

  useEffect(() => {
    onUnreadCountChange(initialThread?.unread_count ?? 0)
  }, [initialThread?.unread_count, onUnreadCountChange])

  useEffect(() => {
    if (!active || readState !== 'idle' || initialLoadRequestedRef.current) return
    initialLoadRequestedRef.current = true
    void readCommentSnapshot(task.task_id).then((snapshot) => {
      setThread(snapshot.thread)
      setComments(snapshot.comments)
      setReadState('ready')
      onUnreadCountChange(snapshot.thread?.unread_count ?? 0)
    }).catch(() => setReadState('error'))
  }, [active, onUnreadCountChange, readState, task.task_id])

  const submit = (input: { body: string; mentionedUserIds: string[] }) => {
    if (!canComment || isPosting) return
    const fingerprint = JSON.stringify([task.task_id, input.body, replyTo?.comment_id ?? null, input.mentionedUserIds])
    if (postAttemptRef.current?.fingerprint !== fingerprint) {
      postAttemptRef.current = { fingerprint, key: crypto.randomUUID() }
    }
    const attempt = postAttemptRef.current
    if (!attempt) return
    setPostError('')
    startPosting(async () => {
      const result = await postTaskComment({
        taskId: task.task_id,
        body: input.body,
        replyToCommentId: replyTo?.comment_id,
        mentionedUserIds: input.mentionedUserIds,
        idempotencyKey: attempt.key,
      })
      if (result.error) {
        setPostError(result.error)
        toast.error(result.error)
        return
      }
      postAttemptRef.current = null
      setReplyTo(null)
      const loaded = await loadComments()
      if (loaded) requestAnimationFrame(() => { if (scrollerRef.current) scrollerRef.current.scrollTop = scrollerRef.current.scrollHeight })
      toast.success('Comment sent')
    })
  }

  return (
    <div id="task-comments-panel" role="tabpanel" aria-labelledby="task-comments-tab" hidden={!active} className={cn('min-h-0 flex-1 flex-col', active && 'flex')}>
      <div ref={scrollerRef} className="min-h-0 flex-1 overflow-y-auto overscroll-contain" tabIndex={0}>
        {readState === 'loading' || readState === 'idle'
          ? <CommentsLoading />
          : readState === 'error'
            ? <CommentsError onRetry={() => void loadComments()} />
            : <CommentFeed comments={comments} thread={thread} context={context} canReply={canComment} onReply={(comment) => { setReplyTo(comment); requestAnimationFrame(() => document.getElementById(`task-comments-message-${task.task_id}`)?.focus()) }} />}
      </div>
      {readState === 'ready' && (canComment
        ? <Composer key={`${task.task_id}-${comments.length}`} taskId={task.task_id} context={context} replyTo={replyTo} pending={isPosting} error={postError} onCancelReply={() => setReplyTo(null)} onSubmit={submit} />
        : <ReadOnlyFooter suspended={task.status === 'suspended'} />)}
    </div>
  )
}
