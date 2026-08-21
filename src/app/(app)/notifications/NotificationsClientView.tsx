'use client'

import { useState, useTransition } from 'react'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { markNotificationRead, markAllNotificationsRead } from '@/lib/actions/notifications'
import { toast } from 'sonner'
import { formatDistanceToNow } from 'date-fns'
import {
  Bell, Check, CheckCheck, FileText, Link2, Calendar,
  AlertTriangle, Sparkles, X, User, Zap, FolderOpen, BellOff
} from 'lucide-react'
import { cn } from '@/lib/utils'
import Link from 'next/link'

const TYPE_CONFIG: Record<string, {
  label: string
  icon: React.FC<any>
  pillBg: string
  iconColor: string
}> = {
  document_ready: {
    label: 'Document Ready',
    icon: FileText,
    pillBg: 'bg-[var(--success-muted)] text-[var(--success)]',
    iconColor: 'text-[var(--success)]',
  },
  chain_suggestion: {
    label: 'Link Suggestion',
    icon: Link2,
    pillBg: 'bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] text-[var(--primary)]',
    iconColor: 'text-[var(--primary)]',
  },
  deadline_approaching: {
    label: 'Deadline',
    icon: Calendar,
    pillBg: 'bg-[var(--warning-muted)] text-[var(--warning)]',
    iconColor: 'text-[var(--warning)]',
  },
  processing_failed: {
    label: 'Processing Failed',
    icon: AlertTriangle,
    pillBg: 'bg-[var(--danger-muted)] text-[var(--danger)]',
    iconColor: 'text-[var(--danger)]',
  },
  org_invite: {
    label: 'Invitation',
    icon: User,
    pillBg: 'bg-[var(--accent-muted)] text-[var(--primary)]',
    iconColor: 'text-[var(--primary)]',
  },
  mention: {
    label: 'Mention',
    icon: Zap,
    pillBg: 'bg-[var(--accent-muted)] text-[var(--accent)]',
    iconColor: 'text-[var(--accent)]',
  },
  staged_doc_ready: {
    label: 'Staged Document',
    icon: FolderOpen,
    pillBg: 'bg-[var(--accent-muted)] text-[var(--primary)]',
    iconColor: 'text-[var(--primary)]',
  },
  wiki_ai_suggestion: {
    label: 'Case Summary',
    icon: Sparkles,
    pillBg: 'bg-[var(--surface-hover)] text-[var(--text-secondary)]',
    iconColor: 'text-[var(--text-secondary)]',
  },
}

const DEFAULT_CONFIG = TYPE_CONFIG.document_ready

type Tab = 'all' | 'unread' | 'system' | 'mentions'

export function NotificationsClientView({ initialNotifications }: { initialNotifications: any[] }) {
  const [notifications, setNotifications] = useState(initialNotifications)
  const [activeTab, setActiveTab] = useState<Tab>('all')
  const [isPending, startTransition] = useTransition()

  const unreadCount = notifications.filter(n => !n.is_read).length

  const filtered = notifications.filter(n => {
    if (activeTab === 'unread') return !n.is_read
    if (activeTab === 'system') return ['document_ready', 'chain_suggestion', 'processing_failed', 'staged_doc_ready', 'wiki_ai_suggestion'].includes(n.type)
    if (activeTab === 'mentions') return n.type === 'mention'
    return true
  })

  function handleMarkRead(id: string) {
    startTransition(async () => {
      const res = await markNotificationRead(id)
      if (res.error) { toast.error(res.error); return }
      setNotifications(prev => prev.map(n => n.id === id ? { ...n, is_read: true } : n))
    })
  }

  function handleMarkAllRead() {
    startTransition(async () => {
      const res = await markAllNotificationsRead()
      if (res.error) { toast.error(res.error); return }
      setNotifications(prev => prev.map(n => ({ ...n, is_read: true })))
      toast.success('All notifications marked as read')
    })
  }

  const getEntityHref = (n: any): string | null => {
    if (!n.entity_id) return null
    if (n.entity_type === 'document') return `/matters` // ideally /matters/:id
    if (n.entity_type === 'matter') return `/matters/${n.entity_id}`
    if (n.entity_type === 'case_note') return `/notes`
    if (n.entity_type === 'staged_document') return `/inbox`
    return null
  }

  const tabs: { key: Tab; label: string; count?: number }[] = [
    { key: 'all', label: 'All', count: notifications.length },
    { key: 'unread', label: 'Unread', count: unreadCount },
    { key: 'system', label: 'System' },
    { key: 'mentions', label: 'Mentions' },
  ]

  return (
    <div className="flex flex-col flex-1 overflow-hidden animate-fade-in">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Notifications' }]} />

      {/* Header */}
      <div className="shrink-0 px-1 pb-4">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h1 className="text-2xl font-bold text-[var(--text-primary)] tracking-tight">Notifications</h1>
            <p className="text-sm text-[var(--text-muted)] mt-0.5">
              {unreadCount > 0 ? `${unreadCount} unread notification${unreadCount !== 1 ? 's' : ''}` : 'All caught up'}
            </p>
          </div>
          {unreadCount > 0 && (
            <button
              onClick={handleMarkAllRead}
              disabled={isPending}
              className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium text-[var(--primary)] hover:bg-[var(--surface-hover)] transition-colors border border-[var(--border)]"
            >
              <CheckCheck size={15} />
              Mark all read
            </button>
          )}
        </div>

        {/* Tab strip */}
        <div className="flex items-center gap-1 p-1 bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)] w-fit">
          {tabs.map(tab => (
            <button
              key={tab.key}
              onClick={() => setActiveTab(tab.key)}
              className={cn(
                'flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-all duration-200',
                activeTab === tab.key
                  ? 'bg-[var(--surface-hover)] shadow-sm'
                  : 'text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)]'
              )}
            >
              {tab.label}
              {tab.count !== undefined && tab.count > 0 && (
                <span className={cn(
                  'text-[10px] font-bold px-1.5 py-0 rounded-full',
                  activeTab === tab.key ? 'bg-[var(--border)] text-[var(--text-primary)]' : 'bg-[var(--border)] text-[var(--text-muted)]'
                )}>
                  {tab.count}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Feed */}
      <div className="flex-1 overflow-y-auto custom-scrollbar space-y-2 pr-1">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 gap-3">
            <div className="w-16 h-16 rounded-[var(--radius-lg)] bg-[var(--surface-hover)] border border-[var(--border)] flex items-center justify-center">
              <BellOff size={28} className="text-[var(--text-muted)]" />
            </div>
            <div className="text-center">
              <p className="font-semibold text-[var(--text-primary)] text-lg">You're all caught up!</p>
              <p className="text-sm text-[var(--text-muted)] mt-1">No notifications in this category.</p>
            </div>
          </div>
        ) : (
          filtered.map((n, i) => {
            const cfg = TYPE_CONFIG[n.type as keyof typeof TYPE_CONFIG] ?? DEFAULT_CONFIG
            const Icon = cfg.icon
            const href = getEntityHref(n)

            return (
              <div
                key={n.id}
                style={{ animationDelay: `${i * 30}ms` }}
                className={cn(
                  'group relative flex gap-4 p-4 rounded-[var(--radius-md)] border transition-all duration-200 animate-fade-in',
                  n.is_read
                    ? 'bg-[var(--surface)] border-[var(--border)] hover:border-[var(--border-strong)]'
                    : 'bg-[var(--surface)] border-[var(--border)] border-l-4 shadow-sm',
                  !n.is_read && `border-l-[var(--primary)]`
                )}
              >
                {/* Unread accent line */}
                {!n.is_read && (
                  <div className="absolute left-0 top-0 bottom-0 w-1 rounded-l-[var(--radius-md)] bg-[var(--primary)]" />
                )}

                {/* Icon */}
                <div className={cn(
                  'shrink-0 w-10 h-10 rounded-[var(--radius-md)] flex items-center justify-center',
                  cfg.pillBg
                )}>
                  <Icon size={18} className={cfg.iconColor} />
                </div>

                {/* Content */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <span className={cn(
                          'text-[10px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded-[var(--radius-sm)]',
                          cfg.pillBg
                        )}>
                          {cfg.label}
                        </span>
                        {!n.is_read && (
                          <span className={cn('w-2 h-2 rounded-[var(--radius-sm)] shrink-0 bg-[var(--primary)]')} />
                        )}
                      </div>
                      <p className={cn(
                        'text-sm font-semibold leading-snug',
                        n.is_read ? 'text-[var(--text-secondary)]' : 'text-[var(--text-primary)]'
                      )}>
                        {n.title}
                      </p>
                      {n.body && (
                        <p className="text-xs text-[var(--text-muted)] mt-0.5 line-clamp-2">{n.body}</p>
                      )}
                    </div>

                    <div className="flex items-center gap-1 shrink-0">
                      <span className="text-[11px] text-[var(--text-muted)] whitespace-nowrap">
                        {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
                      </span>
                    </div>
                  </div>

                  <div className="flex items-center gap-2 mt-2">
                    {href && (
                      <Link
                        href={href}
                        onClick={() => !n.is_read && handleMarkRead(n.id)}
                        className="text-xs font-medium text-[var(--primary)] hover:underline"
                      >
                        View →
                      </Link>
                    )}
                    {!n.is_read && (
                      <button
                        onClick={() => handleMarkRead(n.id)}
                        disabled={isPending}
                        className="flex items-center gap-1 text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors opacity-0 group-hover:opacity-100"
                      >
                        <Check size={12} />
                        Mark read
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
