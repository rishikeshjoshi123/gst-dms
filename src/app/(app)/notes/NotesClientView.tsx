'use client'

import { useState, useMemo, useTransition } from 'react'
import { toast } from 'sonner'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import {
  Search, Pin, Trash2, CheckCircle2, Circle, FileText,
  Check, Edit2, MessageSquarePlus, CornerDownRight, ExternalLink,
  StickyNote, Filter, X, ChevronLeft
} from 'lucide-react'
import { updateNote, deleteNote, createNote } from '@/lib/actions/notes'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { cn } from '@/lib/utils'
import { formatDistanceToNow } from 'date-fns'

const TEMPLATE_META = {
  general: {
    label: 'General',
    pillClass: 'bg-[var(--surface-hover)] text-[var(--text-secondary)]',
    borderClass: 'border-l-[var(--border-strong)]',
  },
  hearing_note: {
    label: 'Hearing Note',
    pillClass: 'bg-[var(--accent-muted)] text-[var(--primary)]',
    borderClass: 'border-l-[var(--primary)]',
  },
  client_instruction: {
    label: 'Client Instruction',
    pillClass: 'bg-[var(--success-muted)] text-[var(--success)]',
    borderClass: 'border-l-[var(--success)]',
  },
  research_note: {
    label: 'Research Note',
    pillClass: 'bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] text-[var(--primary)]',
    borderClass: 'border-l-[var(--primary)]',
  },
}

function getInitials(email: string) {
  const name = email.split('@')[0]
  return name.slice(0, 2).toUpperCase()
}

export function NotesClientView({
  initialNotes,
  matters,
  documents,
  users,
}: {
  initialNotes: any[]
  matters: any[]
  documents: any[]
  users: any[]
}) {
  const [notes, setNotes] = useState(initialNotes)
  const [searchQuery, setSearchQuery] = useState('')
  const [filterMatter, setFilterMatter] = useState('')
  const [filterType, setFilterType] = useState('')
  const [filterActionItems, setFilterActionItems] = useState('all')
  const [editingNoteId, setEditingNoteId] = useState<string | null>(null)
  const [editContent, setEditContent] = useState('')
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null)
  const [replyContent, setReplyContent] = useState('')
  const [isPending, startTransition] = useTransition()

  const allParentNotes = useMemo(() => notes.filter(n => !n.parent_note_id), [notes])
  const childNotesByParent = useMemo(() => {
    const map = new Map<string, any[]>()
    notes.filter(n => !!n.parent_note_id).forEach(n => {
      if (!map.has(n.parent_note_id)) map.set(n.parent_note_id, [])
      map.get(n.parent_note_id)!.push(n)
    })
    for (const [, replies] of map.entries()) {
      replies.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
    }
    return map
  }, [notes])

  const filteredThreads = useMemo(() => {
    return allParentNotes.filter(note => {
      if (searchQuery && !note.content.toLowerCase().includes(searchQuery.toLowerCase())) return false
      if (filterMatter && note.matter_id !== filterMatter) return false
      if (filterType && note.template_type !== filterType) return false
      if (filterActionItems === 'notes_only' && note.is_action_item) return false
      if (filterActionItems === 'pending_tasks' && (!note.is_action_item || note.action_item_resolved)) return false
      if (filterActionItems === 'resolved_tasks' && (!note.is_action_item || !note.action_item_resolved)) return false
      return true
    })
  }, [allParentNotes, searchQuery, filterMatter, filterType, filterActionItems])

  const pinnedThreads = filteredThreads.filter(n => n.is_pinned)
  const unpinnedThreads = filteredThreads.filter(n => !n.is_pinned)

  const handleTogglePin = async (note: any) => {
    const newPinned = !note.is_pinned
    const res = await updateNote(note.id, { is_pinned: newPinned })
    if (res.error) { toast.error(res.error); return }
    setNotes(prev => {
      const updated = prev.map(n => n.id === note.id ? { ...n, is_pinned: newPinned } : n)
      return updated.sort((a, b) => {
        if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      })
    })
    toast.success(newPinned ? 'Note pinned' : 'Note unpinned')
  }

  const handleToggleResolve = async (note: any) => {
    const newResolved = !note.action_item_resolved
    const res = await updateNote(note.id, { action_item_resolved: newResolved })
    if (res.error) { toast.error(res.error); return }
    setNotes(prev => prev.map(n => n.id === note.id ? { ...n, action_item_resolved: newResolved } : n))
    toast.success(newResolved ? 'Task resolved' : 'Task reopened')
  }

  const [pendingDeleteNoteId, setPendingDeleteNoteId] = useState<string | null>(null)

  const handleDeleteNote = async () => {
    if (!pendingDeleteNoteId) return
    const noteId = pendingDeleteNoteId
    const res = await deleteNote(noteId)
    setPendingDeleteNoteId(null)
    if (res.error) { toast.error(res.error); return }
    setNotes(prev => prev.filter(n => n.id !== noteId))
    if (selectedThreadId === noteId) setSelectedThreadId(null)
    toast.success('Note deleted')
  }

  const startEditing = (note: any) => { setEditingNoteId(note.id); setEditContent(note.content) }

  const handleSaveEdit = async (noteId: string) => {
    if (!editContent.trim()) return
    const res = await updateNote(noteId, { content: editContent })
    if (res.error) { toast.error(res.error); return }
    setNotes(prev => prev.map(n => n.id === noteId ? { ...n, content: editContent } : n))
    setEditingNoteId(null)
    toast.success('Note updated')
  }

  const handleReply = (parentNote: any) => {
    if (!replyContent.trim()) return
    startTransition(async () => {
      const res = await createNote({
        matterId: parentNote.matter_id,
        documentId: parentNote.document_id,
        content: replyContent,
        templateType: 'general',
        isActionItem: false,
        parentNoteId: parentNote.id,
      })
      if (res.error) { toast.error(res.error); return }
      setNotes(prev => [res.note, ...prev])
      setReplyContent('')
      toast.success('Reply added')
    })
  }

  const selectedThread = useMemo(() => notes.find(n => n.id === selectedThreadId), [notes, selectedThreadId])
  const selectedThreadReplies = useMemo(() =>
    selectedThreadId ? (childNotesByParent.get(selectedThreadId) || []) : [],
    [selectedThreadId, childNotesByParent]
  )

  function ThreadCard({ note }: { note: any }) {
    const isSelected = selectedThreadId === note.id
    const replyCount = (childNotesByParent.get(note.id) || []).length
    const meta = TEMPLATE_META[note.template_type as keyof typeof TEMPLATE_META] ?? TEMPLATE_META.general
    const initials = getInitials(note.author?.email || 'U')

    return (
      <div
        onClick={() => setSelectedThreadId(note.id)}
        className={cn(
          'flex flex-col p-3.5 rounded-[var(--radius-md)] cursor-pointer transition-all duration-200 border group',
          note.is_pinned && 'border-l-4',
          note.is_pinned ? meta.borderClass : '',
          isSelected
            ? 'bg-[var(--surface)] border-[var(--primary)] shadow-md shadow-blue-500/10'
            : 'bg-[var(--surface)] border-[var(--border)] hover:border-[var(--border-strong)] hover:shadow-sm'
        )}
      >
        <div className="flex items-center justify-between gap-2 mb-2">
          <div className="flex items-center gap-1.5 flex-wrap">
            {note.is_pinned && <Pin size={10} className="text-[var(--warning)] fill-current shrink-0" />}
            <span className={cn(
              'text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-[var(--radius-sm)]',
              meta.pillClass
            )}>
              {meta.label}
            </span>
            {note.is_action_item && (
              <span className={cn(
                'text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-[var(--radius-sm)]',
                note.action_item_resolved
                  ? 'bg-[var(--success-muted)] text-[var(--success)]'
                  : 'bg-[var(--warning-muted)] text-[var(--warning)]'
              )}>
                {note.action_item_resolved ? '✓ Done' : 'Task'}
              </span>
            )}
          </div>
          <span className="text-[10px] text-[var(--text-muted)] shrink-0">
            {formatDistanceToNow(new Date(note.created_at), { addSuffix: true })}
          </span>
        </div>

        <p className="text-sm text-[var(--text-primary)] line-clamp-3 mb-2.5 leading-relaxed">
          {note.content}
        </p>

        <div className="flex items-center justify-between mt-auto pt-2 border-t border-[var(--border)]">
          <div className="flex items-center gap-2">
            <div className={cn(
              'w-5 h-5 rounded-[var(--radius-sm)] flex items-center justify-center text-[9px] font-bold shrink-0',
              meta.pillClass
            )}>
              {initials}
            </div>
            <span className="text-[10px] text-[var(--text-muted)] truncate max-w-[100px]">
              {note.author?.email?.split('@')[0] || 'Unknown'}
            </span>
          </div>
          {replyCount > 0 && (
            <div className="flex items-center gap-1 text-[var(--text-muted)] bg-[var(--surface-hover)] border border-[var(--border)] px-1.5 py-0.5 rounded-[var(--radius-sm)]">
              <MessageSquarePlus size={10} />
              <span className="text-[10px] font-semibold">{replyCount}</span>
            </div>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="flex flex-col flex-1 overflow-hidden animate-fade-in">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Notes Hub' }]} />

      {/* Filter & search bar */}
      <div className="flex flex-wrap items-center gap-2.5 pb-4 shrink-0">
        {/* Search */}
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" size={14} />
          <input
            type="text"
            placeholder="Search notes..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-2 text-sm bg-[var(--surface)] border border-[var(--border-strong)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)] rounded-[var(--radius-md)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] transition-all"
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)] hover:text-[var(--text-primary)]">
              <X size={12} />
            </button>
          )}
        </div>

        <div className="flex flex-col sm:flex-row items-stretch sm:items-center w-full sm:w-auto gap-2 sm:gap-1 p-2 sm:p-1 bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)]">
          <div className="hidden sm:block">
            <Filter size={12} className="text-[var(--text-muted)] mx-1.5" />
          </div>
          {/* Matter filter */}
          <select
            value={filterMatter}
            onChange={(e) => setFilterMatter(e.target.value)}
            className="px-2 py-1.5 text-xs bg-transparent text-[var(--text-primary)] outline-none cursor-pointer"
          >
            <option value="">All Matters</option>
            {matters.map(m => <option key={m.id} value={m.id}>{m.title}</option>)}
          </select>

          <div className="hidden sm:block w-px h-4 bg-[var(--border)]" />

          {/* Type filter */}
          <select
            value={filterType}
            onChange={(e) => setFilterType(e.target.value)}
            className="px-2 py-1.5 text-xs bg-transparent text-[var(--text-primary)] outline-none cursor-pointer"
          >
            <option value="">All Types</option>
            {Object.entries(TEMPLATE_META).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>

          <div className="hidden sm:block w-px h-4 bg-[var(--border)]" />

          {/* Action item filter */}
          <select
            value={filterActionItems}
            onChange={(e) => setFilterActionItems(e.target.value)}
            className="px-2 py-1.5 text-xs bg-transparent text-[var(--text-primary)] outline-none cursor-pointer"
          >
            <option value="all">All Notes</option>
            <option value="notes_only">Notes Only</option>
            <option value="pending_tasks">Pending Tasks</option>
            <option value="resolved_tasks">Resolved Tasks</option>
          </select>
        </div>
      </div>

      {/* Split Pane */}
      <div className="flex flex-1 min-h-0 overflow-hidden gap-4 relative">

        {/* Left Pane: Thread List */}
        <div className={cn(
          "w-full md:w-[320px] shrink-0 flex flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)]",
          selectedThreadId ? "hidden md:flex" : "flex"
        )}>
          {/* Header */}
          <div className="px-4 py-3 border-b border-[var(--border)] bg-[var(--surface)] shrink-0 flex items-center justify-between">
            <h2 className="text-xs font-bold text-[var(--text-primary)] uppercase tracking-wider">
              Conversations
            </h2>
            <span className="text-[10px] font-semibold bg-[var(--surface-hover)] border border-[var(--border)] px-2 py-0.5 rounded-[var(--radius-sm)] text-[var(--text-muted)]">
              {filteredThreads.length}
            </span>
          </div>

          <div className="flex-1 overflow-y-auto custom-scrollbar p-3 flex flex-col gap-2">
            {filteredThreads.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 gap-3">
                <div className="w-12 h-12 rounded-[var(--radius-md)] bg-[var(--surface-hover)] border border-[var(--border)] flex items-center justify-center">
                  <StickyNote size={22} className="text-[var(--text-muted)]" />
                </div>
                <p className="text-xs text-[var(--text-muted)] text-center">No notes found</p>
              </div>
            ) : (
              <>
                {pinnedThreads.length > 0 && (
                  <>
                    <div className="flex items-center gap-2 px-1 mb-1">
                      <Pin size={10} className="text-[var(--warning)] fill-current" />
                      <span className="text-[9px] font-bold uppercase tracking-wider text-[var(--text-muted)]">Pinned</span>
                    </div>
                    {pinnedThreads.map(note => <ThreadCard key={note.id} note={note} />)}
                    {unpinnedThreads.length > 0 && (
                      <div className="my-1 flex items-center gap-2">
                        <div className="flex-1 h-px bg-[var(--border)]" />
                        <span className="text-[9px] font-bold uppercase tracking-wider text-[var(--text-muted)]">All Notes</span>
                        <div className="flex-1 h-px bg-[var(--border)]" />
                      </div>
                    )}
                  </>
                )}
                {unpinnedThreads.map(note => <ThreadCard key={note.id} note={note} />)}
              </>
            )}
          </div>
        </div>

        {/* Right Pane: Thread Detail */}
        <div className={cn(
          "flex-1 flex flex-col rounded-[var(--radius-md)] border border-[var(--border)] overflow-hidden bg-[var(--surface)]",
          !selectedThreadId ? "hidden md:flex" : "flex"
        )}>
          {!selectedThread ? (
            <div className="flex-1 flex flex-col items-center justify-center gap-4 text-[var(--text-muted)]">
              <div className="w-16 h-16 rounded-[var(--radius-lg)] bg-[var(--surface-hover)] border border-[var(--border)] flex items-center justify-center">
                <FileText size={28} className="text-[var(--text-muted)]" />
              </div>
              <div className="text-center">
                <p className="font-semibold text-[var(--text-primary)]">Select a conversation</p>
                <p className="text-sm text-[var(--text-muted)] mt-1">Click any note from the list to view its thread</p>
              </div>
            </div>
          ) : (
            <>
              {/* Thread Header */}
              <div className="px-5 py-3.5 border-b border-[var(--border)] bg-[var(--surface)] flex items-center justify-between shrink-0">
                <div className="flex items-center gap-3 min-w-0">
                  <button
                    type="button"
                    onClick={() => setSelectedThreadId(null)}
                    className="md:hidden p-1.5 -ml-1.5 rounded-[var(--radius-sm)] text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)]"
                    aria-label="Back to conversations"
                  >
                    <ChevronLeft size={20} />
                  </button>
                  <div className="flex flex-col gap-0.5 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                    <span className={cn(
                      'text-[9px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-[var(--radius-sm)]',
                      (TEMPLATE_META[selectedThread.template_type as keyof typeof TEMPLATE_META] ?? TEMPLATE_META.general).pillClass
                    )}>
                      {(TEMPLATE_META[selectedThread.template_type as keyof typeof TEMPLATE_META] ?? TEMPLATE_META.general).label}
                    </span>
                    {selectedThread.matters && (
                      <span className="text-xs text-[var(--text-muted)] flex items-center gap-1">
                        <FileText size={11} /> {selectedThread.matters.title}
                      </span>
                    )}
                    {selectedThread.documents && (
                      <a
                        href={`/matters/${selectedThread.matter_id}/documents/${selectedThread.document_id}`}
                        className="flex items-center gap-1 text-xs text-[var(--primary)] hover:underline font-mono"
                      >
                        <ExternalLink size={11} /> {selectedThread.documents.reference_number || 'Doc'}
                      </a>
                    )}
                  </div>
                </div>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => handleTogglePin(selectedThread)}
                    className={cn(
                      'p-2 rounded-lg border transition-all text-sm',
                      selectedThread.is_pinned
                        ? 'border-[var(--warning)] bg-[var(--warning-muted)] text-[var(--warning)]'
                        : 'border-[var(--border)] text-[var(--text-muted)] hover:bg-[var(--surface-hover)]'
                    )}
                    title="Pin Thread"
                  >
                    <Pin size={14} className={selectedThread.is_pinned ? 'fill-current' : ''} />
                  </button>
                  <button
                    onClick={() => setPendingDeleteNoteId(selectedThread.id)}
                    className="p-2 rounded-[var(--radius-sm)] border border-[var(--border)] text-[var(--text-muted)] hover:border-[var(--danger)] hover:bg-[var(--danger-muted)] hover:text-[var(--danger)] transition-all"
                    title="Delete Thread"
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              </div>

              {/* Thread Messages */}
              <div className="flex-1 overflow-y-auto custom-scrollbar p-5 flex flex-col gap-5 bg-[var(--bg)]">
                {/* Original Note */}
                <div className="flex gap-3">
                  <div className={cn(
                    'w-9 h-9 rounded-[var(--radius-md)] flex items-center justify-center text-sm font-bold shrink-0 mt-0.5',
                    (TEMPLATE_META[selectedThread.template_type as keyof typeof TEMPLATE_META] ?? TEMPLATE_META.general).pillClass
                  )}>
                    {getInitials(selectedThread.author?.email || 'U')}
                  </div>
                  <div className="flex-1">
                    <div className="flex items-baseline gap-2 mb-1.5">
                      <span className="font-semibold text-sm text-[var(--text-primary)]">
                        {selectedThread.author?.email?.split('@')[0] || 'Unknown'}
                      </span>
                      <span className="text-[11px] text-[var(--text-muted)]">
                        {formatDistanceToNow(new Date(selectedThread.created_at), { addSuffix: true })}
                      </span>
                    </div>

                    {selectedThread.quote && (
                      <div className="mb-2.5 p-3 bg-[var(--warning-muted)] border-l-4 border-[var(--warning)] rounded-r-xl">
                        <span className="text-[9px] font-bold uppercase tracking-wider text-[var(--warning)]">
                          Quote · Page {selectedThread.page_number}
                        </span>
                        <p className="text-sm italic text-[var(--text-secondary)] mt-1 leading-relaxed">
                          &ldquo;{selectedThread.quote}&rdquo;
                        </p>
                      </div>
                    )}

                    {editingNoteId === selectedThread.id ? (
                      <div className="flex flex-col gap-2">
                        <textarea
                          value={editContent}
                          onChange={(e) => setEditContent(e.target.value)}
                          className="w-full min-h-[100px] p-3 text-sm bg-[var(--surface)] border border-[var(--border-strong)] text-[var(--text-primary)] rounded-[var(--radius-md)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] resize-none"
                        />
                        <div className="flex gap-2">
                          <button onClick={() => handleSaveEdit(selectedThread.id)} className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium bg-[var(--primary)] text-[var(--on-accent)] hover:bg-[var(--primary-hover)]">
                            <Check size={12} /> Save
                          </button>
                          <button onClick={() => setEditingNoteId(null)} className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]">
                            <X size={12} /> Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div className="relative group">
                        <div className="bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)] rounded-tl-sm p-4 shadow-sm">
                          <p className="text-sm text-[var(--text-primary)] whitespace-pre-wrap leading-relaxed">
                            {selectedThread.content}
                          </p>
                        </div>
                        <button
                          onClick={() => startEditing(selectedThread)}
                          className="absolute top-2 right-2 p-1.5 text-[var(--text-muted)] hover:text-[var(--primary)] opacity-0 group-hover:opacity-100 transition-opacity bg-[var(--surface)] rounded-lg shadow-sm border border-[var(--border)]"
                        >
                          <Edit2 size={11} />
                        </button>
                      </div>
                    )}

                    {/* Action item */}
                    {selectedThread.is_action_item && (
                      <div className={cn(
                        'mt-3 p-3 rounded-[var(--radius-md)] border flex flex-col gap-2',
                        selectedThread.action_item_resolved
                          ? 'bg-[var(--success-muted)] border-[color-mix(in_srgb,var(--success)_20%,transparent)]'
                          : 'bg-[var(--warning-muted)] border-[color-mix(in_srgb,var(--warning)_20%,transparent)]'
                      )}>
                        <div className="flex items-center justify-between">
                          <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-secondary)]">Action Item</span>
                          <button
                            onClick={() => handleToggleResolve(selectedThread)}
                            className={cn(
                              'flex items-center gap-1.5 text-xs font-medium px-2.5 py-1 rounded-[var(--radius-sm)] transition-colors',
                              selectedThread.action_item_resolved
                                ? 'text-[var(--success)] bg-[var(--success-muted)]'
                                : 'text-[var(--warning)] bg-[var(--warning-muted)]'
                            )}
                          >
                            {selectedThread.action_item_resolved
                              ? <><CheckCircle2 size={13} /> Resolved</>
                              : <><Circle size={13} /> Mark Resolved</>
                            }
                          </button>
                        </div>
                        {(selectedThread.action_item_assignee || selectedThread.action_item_due_date) && (
                          <div className="flex gap-4 text-xs text-[var(--text-muted)]">
                            {selectedThread.action_item_assignee && <span>Assignee: <strong className="text-[var(--text-primary)]">{selectedThread.action_item_assignee}</strong></span>}
                            {selectedThread.action_item_due_date && <span>Due: <strong className="text-[var(--text-primary)]">{new Date(selectedThread.action_item_due_date).toLocaleDateString()}</strong></span>}
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                </div>

                {/* Replies */}
                {selectedThreadReplies.map(reply => (
                  <div key={reply.id} className="flex gap-3 ml-8 relative">
                    <div className="absolute -left-5 top-5 bottom-0 w-px bg-[var(--border)]" />
                    <CornerDownRight size={14} className="absolute -left-5 top-4 text-[var(--border-strong)]" />

                    <div className="w-8 h-8 rounded-[var(--radius-md)] bg-[var(--surface-hover)] border border-[var(--border)] flex items-center justify-center text-[var(--text-secondary)] font-bold shrink-0 mt-0.5 text-xs">
                      {getInitials(reply.author?.email || 'U')}
                    </div>
                    <div className="flex-1">
                      <div className="flex items-baseline gap-2 mb-1.5">
                        <span className="font-semibold text-sm text-[var(--text-primary)]">
                          {reply.author?.email?.split('@')[0] || 'Unknown'}
                        </span>
                        <span className="text-[11px] text-[var(--text-muted)]">
                          {formatDistanceToNow(new Date(reply.created_at), { addSuffix: true })}
                        </span>
                      </div>
                      {editingNoteId === reply.id ? (
                        <div className="flex flex-col gap-2">
                          <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full min-h-[80px] p-3 text-sm bg-[var(--surface)] border border-[var(--border-strong)] text-[var(--text-primary)] rounded-[var(--radius-md)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] resize-none"
                          />
                          <div className="flex gap-2">
                            <button onClick={() => handleSaveEdit(reply.id)} className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium bg-[var(--primary)] text-[var(--on-accent)] hover:bg-[var(--primary-hover)]">
                              <Check size={12} /> Save
                            </button>
                            <button onClick={() => setEditingNoteId(null)} className="flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-medium border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]">
                              <X size={12} /> Cancel
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="relative group">
                          <div className="bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)] rounded-tl-sm p-3 shadow-sm">
                            <p className="text-sm text-[var(--text-primary)] whitespace-pre-wrap leading-relaxed">
                              {reply.content}
                            </p>
                          </div>
                          <div className="absolute top-2 right-2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                            <button onClick={() => startEditing(reply)} className="p-1.5 text-[var(--text-muted)] hover:text-[var(--primary)] bg-[var(--surface)] rounded-lg shadow-sm border border-[var(--border)]">
                              <Edit2 size={11} />
                            </button>
                            <button onClick={() => setPendingDeleteNoteId(reply.id)} className="p-1.5 text-[var(--text-muted)] hover:text-[var(--danger)] bg-[var(--surface)] rounded-lg shadow-sm border border-[var(--border)]">
                              <Trash2 size={11} />
                            </button>
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              {/* Reply Box */}
              <div className="p-4 border-t border-[var(--border)] bg-[var(--surface)] shrink-0">
                <div className="flex items-end gap-3">
                  <div className="flex-1">
                    <textarea
                      value={replyContent}
                      onChange={e => setReplyContent(e.target.value)}
                      placeholder="Type a reply to this thread..."
                      className="w-full min-h-[48px] max-h-[120px] p-3 text-sm bg-[var(--bg)] border border-[var(--border-strong)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)] rounded-[var(--radius-md)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] resize-y transition-all"
                    />
                  </div>
                  <button
                    onClick={() => handleReply(selectedThread)}
                    disabled={isPending || !replyContent.trim()}
                    className="mb-1 px-4 py-2.5 rounded-[var(--radius-md)] text-sm font-semibold bg-[var(--primary)] text-[var(--on-accent)] hover:bg-[var(--primary-hover)] transition-opacity disabled:opacity-40 disabled:cursor-not-allowed shadow-sm"
                  >
                    Reply
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      <ConfirmDialog
        isOpen={!!pendingDeleteNoteId}
        onClose={() => setPendingDeleteNoteId(null)}
        onConfirm={handleDeleteNote}
        title="Delete Note?"
        description="Are you sure you want to delete this note? This action cannot be undone."
        confirmText="Delete Note"
        variant="destructive"
      />
    </div>
  )
}
