'use client'

import { useState, useMemo, useTransition } from 'react'
import { toast } from 'sonner'
import { Plus, Search, Pin, Trash2, CheckCircle2, Circle, Calendar, User, FileText, Check, X, Edit2, AlertCircle, MessageSquarePlus, CornerDownRight, ExternalLink } from 'lucide-react'
import { createNote, updateNote, deleteNote } from '@/lib/actions/notes'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import { Badge } from '@/components/ui/badge'

const TEMPLATE_LABELS = {
  general: 'General',
  hearing_note: 'Hearing Note',
  client_instruction: 'Client Instruction',
  research_note: 'Research Note',
}

const TEMPLATE_COLORS = {
  general: 'bg-[var(--surface-hover)] text-[var(--text-primary)] border-[var(--border)]',
  hearing_note: 'bg-blue-50 dark:bg-blue-900/20 text-blue-800 dark:text-blue-300 border-blue-200 dark:border-blue-800',
  client_instruction: 'bg-emerald-50 dark:bg-emerald-900/20 text-emerald-800 dark:text-emerald-300 border-emerald-200 dark:border-emerald-800',
  research_note: 'bg-purple-50 dark:bg-purple-900/20 text-purple-800 dark:text-purple-300 border-purple-200 dark:border-purple-800',
}

export function MatterNotesTab({
  matterId,
  initialNotes,
  documents,
  users,
}: {
  matterId: string
  initialNotes: any[]
  documents: any[]
  users: any[]
}) {
  const [notes, setNotes] = useState(initialNotes)
  const [searchQuery, setSearchQuery] = useState('')
  const [filterType, setFilterType] = useState('')
  const [filterActionItems, setFilterActionItems] = useState('all') 

  const [isCreateOpen, setIsCreateOpen] = useState(false)
  const [isPending, startTransition] = useTransition()

  // Form State
  const [formDoc, setFormDoc] = useState('')
  const [formType, setFormType] = useState<'hearing_note' | 'client_instruction' | 'research_note' | 'general'>('general')
  const [formContent, setFormContent] = useState('')
  const [formIsAction, setFormIsAction] = useState(false)
  const [formAssignee, setFormAssignee] = useState('')
  const [formDueDate, setFormDueDate] = useState('')

  // Edit/Reply State
  const [editingNoteId, setEditingNoteId] = useState<string | null>(null)
  const [editContent, setEditContent] = useState('')
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null)
  const [replyContent, setReplyContent] = useState('')

  const allParentNotes = useMemo(() => notes.filter(n => !n.parent_note_id), [notes])
  const childNotesByParent = useMemo(() => {
    const map = new Map<string, any[]>()
    notes.filter(n => !!n.parent_note_id).forEach(n => {
      if (!map.has(n.parent_note_id)) map.set(n.parent_note_id, [])
      map.get(n.parent_note_id)!.push(n)
    })
    for (const [key, replies] of map.entries()) {
      replies.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
    }
    return map
  }, [notes])

  const filteredThreads = useMemo(() => {
    return allParentNotes.filter(note => {
      if (searchQuery && !note.content.toLowerCase().includes(searchQuery.toLowerCase())) return false
      if (filterType && note.template_type !== filterType) return false
      if (filterActionItems === 'pending_tasks' && (!note.is_action_item || note.action_item_resolved)) return false
      if (filterActionItems === 'resolved_tasks' && (!note.is_action_item || !note.action_item_resolved)) return false
      return true
    })
  }, [allParentNotes, searchQuery, filterType, filterActionItems])

  const handleCreateNote = () => {
    if (!formContent.trim()) {
      toast.error('Note content cannot be empty')
      return
    }

    startTransition(async () => {
      const res = await createNote({
        matterId,
        documentId: formDoc || null,
        content: formContent,
        templateType: formType,
        isActionItem: formIsAction,
        actionItemAssignee: formAssignee || null,
        actionItemDueDate: formDueDate || null,
      })

      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Note created successfully')
        setNotes(prev => [res.note, ...prev])
        setIsCreateOpen(false)
        setSelectedThreadId(res.note?.id || null)
        resetForm()
      }
    })
  }

  const resetForm = () => {
    setFormDoc('')
    setFormType('general')
    setFormContent('')
    setFormIsAction(false)
    setFormAssignee('')
    setFormDueDate('')
  }

  const handleTogglePin = async (note: any) => {
    const newPinned = !note.is_pinned
    const res = await updateNote(note.id, { is_pinned: newPinned })
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.map(n => n.id === note.id ? { ...n, is_pinned: newPinned } : n))
      toast.success(newPinned ? 'Note pinned' : 'Note unpinned')
    }
  }

  const handleToggleResolve = async (note: any) => {
    const newResolved = !note.action_item_resolved
    const res = await updateNote(note.id, { action_item_resolved: newResolved })
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.map(n => n.id === note.id ? { ...n, action_item_resolved: newResolved } : n))
      toast.success(newResolved ? 'Task resolved' : 'Task reopened')
    }
  }

  const [pendingDeleteNoteId, setPendingDeleteNoteId] = useState<string | null>(null)

  const handleDeleteNote = async () => {
    if (!pendingDeleteNoteId) return
    const noteId = pendingDeleteNoteId
    const res = await deleteNote(noteId)
    setPendingDeleteNoteId(null)
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.filter(n => n.id !== noteId))
      if (selectedThreadId === noteId) setSelectedThreadId(null)
      toast.success('Note deleted')
    }
  }

  const startEditing = (note: any) => {
    setEditingNoteId(note.id)
    setEditContent(note.content)
  }

  const handleSaveEdit = async (noteId: string) => {
    if (!editContent.trim()) return
    const res = await updateNote(noteId, { content: editContent })
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.map(n => n.id === noteId ? { ...n, content: editContent } : n))
      setEditingNoteId(null)
      toast.success('Note updated')
    }
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
        parentNoteId: parentNote.id
      })
      if (res.error) {
        toast.error(res.error)
      } else {
        setNotes(prev => [res.note, ...prev])
        setReplyContent('')
        toast.success('Reply added')
      }
    })
  }

  const selectedThread = useMemo(() => notes.find(n => n.id === selectedThreadId), [notes, selectedThreadId])
  const selectedThreadReplies = useMemo(() => selectedThreadId ? (childNotesByParent.get(selectedThreadId) || []) : [], [selectedThreadId, childNotesByParent])

  return (
      <div className="flex flex-col h-[700px] border border-[var(--border-strong)] rounded-xl overflow-hidden mt-4 bg-[var(--surface)] shadow-sm animate-fade-in">
      {/* Header & Controls */}
      <div className="flex flex-col sm:flex-row items-center justify-between gap-4 p-4 border-b border-[var(--border-strong)] bg-[var(--bg)]">
        <div className="flex flex-wrap items-center gap-3 w-full sm:w-auto">
          <div className="relative w-full sm:w-60">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" size={14} />
            <input
              type="text"
              placeholder="Search notes..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-8 pr-3 py-1.5 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-md focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
            />
          </div>
          <select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="p-1.5 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-md focus:outline-none focus:ring-1 focus:ring-[var(--primary)]">
            <option value="">All Types</option>
            {Object.entries(TEMPLATE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <select value={filterActionItems} onChange={(e) => setFilterActionItems(e.target.value)} className="p-1.5 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-md focus:outline-none focus:ring-1 focus:ring-[var(--primary)]">
            <option value="all">All Notes & Tasks</option>
            <option value="pending_tasks">Pending Tasks</option>
            <option value="resolved_tasks">Completed Tasks</option>
          </select>
        </div>
        <Button onClick={() => setIsCreateOpen(true)} size="sm" className="bg-[--primary] hover:bg-[--primary-hover] text-white shadow-sm shrink-0">
          <Plus size={14} className="mr-1.5" /> New Note Thread
        </Button>
      </div>

      {/* Split Pane */}
      <div className="flex flex-1 min-h-0 bg-[var(--surface)]">
        
        {/* Left Pane: Thread List */}
        <div className="w-1/3 min-w-[320px] border-r border-[var(--border-strong)] flex flex-col bg-[var(--bg)]">
          <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-3">
            {filteredThreads.length === 0 ? (
              <div className="py-10 text-center text-[--text-muted] flex flex-col items-center">
                <AlertCircle size={24} className="mb-2 opacity-50" />
                <p className="text-sm">No notes found.</p>
              </div>
            ) : (
              filteredThreads.map((note: any) => {
                const isSelected = selectedThreadId === note.id
                const replyCount = (childNotesByParent.get(note.id) || []).length
                return (
                  <div
                    key={note.id}
                    onClick={() => setSelectedThreadId(note.id)}
                    className={`flex flex-col p-4 border rounded-lg cursor-pointer transition-all ${
                      isSelected 
                        ? 'bg-[var(--primary)]/5 border-[var(--primary)] ring-1 ring-[var(--primary)]/20 shadow-sm' 
                        : 'bg-[var(--surface)] border-[var(--border)] hover:border-[var(--border-strong)]'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2 mb-2">
                      <div className="flex items-center gap-2">
                        {note.is_pinned && <Pin size={12} className="text-amber-500 fill-current" />}
                        <Badge variant="muted" className={`${TEMPLATE_COLORS[note.template_type as keyof typeof TEMPLATE_COLORS]} text-[9px] uppercase font-bold tracking-wider px-1.5 py-0 border`}>
                          {TEMPLATE_LABELS[note.template_type as keyof typeof TEMPLATE_LABELS]}
                        </Badge>
                      </div>
                      <span className="text-[10px] text-[--text-muted]">{new Date(note.created_at).toLocaleDateString()}</span>
                    </div>
                    <p className="text-sm text-[var(--text-primary)] line-clamp-2 mb-2">{note.content}</p>
                    
                    <div className="flex items-center justify-between mt-auto pt-2 border-t border-[var(--border)] text-xs">
                      <span className="text-[var(--text-muted)] truncate">{note.author?.email || 'Unknown'}</span>
                      {replyCount > 0 && (
                        <div className="flex items-center gap-1 text-[var(--text-secondary)] font-medium bg-[var(--surface-hover)] px-2 py-0.5 rounded-full shrink-0 border border-[var(--border)]">
                          <MessageSquarePlus size={12} />
                          {replyCount}
                        </div>
                      )}
                    </div>
                  </div>
                )
              })
            )}
          </div>
        </div>

        {/* Right Pane: Thread Detail */}
        <div className="flex-1 flex flex-col bg-[var(--surface)] overflow-hidden relative">
          {!selectedThread ? (
            <div className="flex-1 flex flex-col items-center justify-center text-[var(--text-muted)]">
              <FileText size={48} className="text-[var(--border-strong)] mb-4" />
              <p className="text-lg font-medium text-[var(--text-secondary)]">Select a note thread</p>
            </div>
          ) : (
            <>
              {/* Thread Context */}
              <div className="p-3 border-b border-[var(--border)] bg-[var(--bg)] flex items-center justify-between shrink-0">
                <div className="flex flex-col gap-0.5">
                  <h3 className="text-sm font-bold text-[var(--text-primary)]">Thread</h3>
                  {selectedThread.documents && (
                    <a href={`/matters/${selectedThread.matter_id}/documents/${selectedThread.document_id}`} className="flex items-center gap-1 text-[11px] text-[--primary] hover:underline font-mono">
                      <ExternalLink size={10} /> {selectedThread.documents.reference_number || 'Document'}
                    </a>
                  )}
                </div>
                <div className="flex items-center gap-1">
                  <button onClick={() => handleTogglePin(selectedThread)} className={`p-1.5 rounded transition-colors ${selectedThread.is_pinned ? 'text-amber-600' : 'text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]'}`} title="Pin Thread">
                    <Pin size={14} className={selectedThread.is_pinned ? 'fill-current' : ''} />
                  </button>
                  <button onClick={() => setPendingDeleteNoteId(selectedThread.id)} className="p-1.5 rounded text-[var(--text-secondary)] hover:text-red-600 hover:bg-red-500/10 transition-colors" title="Delete Thread">
                    <Trash2 size={14} />
                  </button>
                </div>
              </div>

              {/* Messages */}
              <div className="flex-1 overflow-y-auto p-5 flex flex-col gap-6">
                {/* Original Note */}
                <div className="flex flex-col gap-2">
                  {selectedThread.quote && (
                    <div className="ml-4 p-3 bg-amber-500/10 border-l-4 border-amber-500 rounded-r-lg shadow-sm">
                      <div className="flex items-center justify-between mb-1">
                         <span className="text-[10px] font-bold uppercase tracking-wider text-amber-600">Quote from Page {selectedThread.page_number}</span>
                         <a href={`/matters/${selectedThread.matter_id}/documents/${selectedThread.document_id}#page=${selectedThread.page_number}`} className="text-amber-500 hover:text-amber-400"><ExternalLink size={12} /></a>
                      </div>
                      <p className="text-sm italic text-amber-500/90 leading-relaxed">"{selectedThread.quote}"</p>
                    </div>
                  )}

                  <div className="flex gap-3">
                    <div className="w-8 h-8 rounded-full bg-[--primary]/10 flex items-center justify-center text-[--primary] font-bold shrink-0 mt-1 text-sm">
                      {selectedThread.author?.email?.[0].toUpperCase() || 'U'}
                    </div>
                    <div className="flex-1 flex flex-col">
                      <div className="flex items-baseline gap-2 mb-1">
                        <span className="font-semibold text-[var(--text-primary)] text-[13px]">{selectedThread.author?.email || 'Unknown User'}</span>
                        <span className="text-[11px] text-[var(--text-muted)]">{new Date(selectedThread.created_at).toLocaleString()}</span>
                      </div>
                      
                      {editingNoteId === selectedThread.id ? (
                        <div className="flex flex-col gap-2 mt-1">
                           <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full min-h-[100px] p-2 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border)] rounded focus:outline-none focus:ring-1 focus:ring-[var(--primary)] resize-none"
                          />
                          <div className="flex gap-2">
                             <Button size="sm" onClick={() => handleSaveEdit(selectedThread.id)}>Save</Button>
                             <Button size="sm" variant="outline" onClick={() => setEditingNoteId(null)}>Cancel</Button>
                          </div>
                        </div>
                      ) : (
                        <div className="bg-[var(--surface)] border border-[var(--border)] rounded-2xl rounded-tl-sm p-3.5 shadow-sm relative group">
                          <p className="text-[13px] text-[var(--text-primary)] whitespace-pre-wrap leading-relaxed">{selectedThread.content}</p>
                          <button onClick={() => startEditing(selectedThread)} className="absolute top-1.5 right-1.5 p-1 text-[var(--text-muted)] hover:text-[var(--primary)] opacity-0 group-hover:opacity-100 transition-opacity bg-[var(--bg)] rounded-md shadow-sm border border-[var(--border)]"><Edit2 size={12} /></button>
                        </div>
                      )}

                      {/* Action item block */}
                      {selectedThread.is_action_item && (
                        <div className={`mt-2.5 p-2.5 rounded-lg border flex flex-col gap-2 ${selectedThread.action_item_resolved ? 'bg-slate-100/10 border-slate-500/20' : 'bg-amber-500/10 border-amber-500/30'}`}>
                           <div className="flex items-center justify-between">
                              <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-secondary)]">Action Item</span>
                              <button onClick={() => handleToggleResolve(selectedThread)} className={`flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded transition-colors ${selectedThread.action_item_resolved ? 'text-emerald-500 bg-emerald-500/10' : 'text-amber-500 bg-amber-500/10'}`}>
                                {selectedThread.action_item_resolved ? <><CheckCircle2 size={12}/> Resolved</> : <><Circle size={12} /> Mark Resolved</>}
                              </button>
                           </div>
                           <div className="flex gap-4 text-[11px]">
                              {selectedThread.action_item_assignee && <span>Assignee: <strong>{selectedThread.action_item_assignee}</strong></span>}
                              {selectedThread.action_item_due_date && <span>Due: <strong>{new Date(selectedThread.action_item_due_date).toLocaleDateString()}</strong></span>}
                           </div>
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* Replies */}
                {selectedThreadReplies.map(reply => (
                  <div key={reply.id} className="flex gap-3 ml-6 relative">
                    <div className="absolute -left-4 top-4 bottom-0 w-px bg-[var(--border-strong)]" />
                    <CornerDownRight size={14} className="absolute -left-4 top-4 text-[var(--border-strong)]" />

                    <div className="w-7 h-7 rounded-full bg-[var(--bg)] border border-[var(--border)] flex items-center justify-center text-[var(--text-muted)] font-bold shrink-0 mt-1 text-xs">
                      {reply.author?.email?.[0].toUpperCase() || 'U'}
                    </div>
                    <div className="flex-1 flex flex-col">
                      <div className="flex items-baseline gap-2 mb-1">
                        <span className="font-semibold text-[var(--text-primary)] text-[13px]">{reply.author?.email || 'Unknown User'}</span>
                        <span className="text-[11px] text-[var(--text-muted)]">{new Date(reply.created_at).toLocaleString()}</span>
                      </div>
                      
                      {editingNoteId === reply.id ? (
                        <div className="flex flex-col gap-2 mt-1">
                           <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full min-h-[80px] p-2 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border)] rounded focus:outline-none focus:ring-1 focus:ring-[var(--primary)] resize-none"
                          />
                          <div className="flex gap-2">
                             <Button size="sm" onClick={() => handleSaveEdit(reply.id)}>Save</Button>
                             <Button size="sm" variant="outline" onClick={() => setEditingNoteId(null)}>Cancel</Button>
                          </div>
                        </div>
                      ) : (
                        <div className="bg-[var(--surface)] border border-[var(--border)] rounded-2xl rounded-tl-sm p-3.5 shadow-sm relative group">
                          <p className="text-[13px] text-[var(--text-primary)] whitespace-pre-wrap leading-relaxed">{reply.content}</p>
                          <div className="absolute top-1.5 right-1.5 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                            <button onClick={() => startEditing(reply)} className="p-1 text-[var(--text-muted)] hover:text-[var(--primary)] bg-[var(--bg)] rounded-md shadow-sm border border-[var(--border)]"><Edit2 size={12} /></button>
                            <button onClick={() => setPendingDeleteNoteId(reply.id)} className="p-1 text-[var(--text-muted)] hover:text-red-500 bg-[var(--bg)] rounded-md shadow-sm border border-[var(--border)]"><Trash2 size={12} /></button>
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              {/* Reply Box */}
              <div className="p-3 border-t border-[var(--border)] bg-[var(--bg)] shrink-0">
                <div className="flex items-end gap-2 max-w-4xl mx-auto">
                  <div className="flex-1">
                    <textarea
                      value={replyContent}
                      onChange={e => setReplyContent(e.target.value)}
                      placeholder="Reply to this thread..."
                      className="w-full min-h-[40px] max-h-[120px] p-2.5 text-sm bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-lg focus:outline-none focus:ring-1 focus:ring-[var(--primary)] resize-y"
                    />
                  </div>
                  <Button onClick={() => handleReply(selectedThread)} disabled={isPending || !replyContent.trim()} className="mb-0.5">
                    Reply
                  </Button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>

      {/* Create Modal */}
      <Dialog open={isCreateOpen} onOpenChange={setIsCreateOpen}>
        <DialogContent className="bg-[var(--surface)] border border-[var(--border)] text-[var(--text-primary)] rounded-lg shadow-xl max-w-lg p-6">
          <DialogHeader>
            <DialogTitle className="text-[18px] font-semibold text-[var(--text-primary)]">Create Case Note Thread</DialogTitle>
            <DialogDescription className="text-[14px] text-[var(--text-secondary)]">
              Add a new note or action item scoped to this Matter.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-4 mt-2">
            {/* Document Select */}
            <div className="flex flex-col gap-1.5">
              <label className="text-[12px] font-medium uppercase tracking-wider text-[var(--text-muted)]">
                Attach to Document (Optional)
              </label>
              <select
                value={formDoc}
                onChange={(e) => setFormDoc(e.target.value)}
                className="w-full p-2 bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-lg text-sm focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
              >
                <option value="">-- No Document --</option>
                {documents.map(d => (
                  <option key={d.id} value={d.id}>
                    {d.reference_number || d.storage_path.split('/').pop()}
                  </option>
                ))}
              </select>
            </div>

            {/* Template type */}
            <div className="flex flex-col gap-1.5">
              <label className="text-[12px] font-medium uppercase tracking-wider text-[var(--text-muted)]">
                Note Type
              </label>
              <select
                value={formType}
                onChange={(e) => setFormType(e.target.value as any)}
                className="w-full p-2 bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-lg text-sm focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
              >
                {Object.entries(TEMPLATE_LABELS).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </div>

            {/* Note Content */}
            <div className="flex flex-col gap-1.5">
              <label className="text-[12px] font-medium uppercase tracking-wider text-[var(--text-muted)]">
                Note Content <span className="text-red-500">*</span>
              </label>
              <textarea
                value={formContent}
                onChange={(e) => setFormContent(e.target.value)}
                placeholder="Write note or legal analysis here..."
                className="w-full min-h-[120px] p-3 bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded-lg text-sm focus:outline-none focus:ring-1 focus:ring-[var(--primary)] resize-y"
              />
            </div>

            {/* Is Action Item */}
            <div className="flex items-center gap-2 py-1">
              <input
                type="checkbox"
                id="is-action-item"
                checked={formIsAction}
                onChange={(e) => setFormIsAction(e.target.checked)}
                className="h-4 w-4 rounded border-[var(--border-strong)] text-[var(--primary)] focus:ring-[var(--primary)]"
              />
              <label htmlFor="is-action-item" className="text-sm font-semibold text-[var(--text-primary)]">
                Mark as Action Item (Task)
              </label>
            </div>

            {/* Action Item Assignee & Due Date */}
            {formIsAction && (
              <div className="grid grid-cols-2 gap-4 p-3 bg-[var(--bg)] border border-[var(--border)] rounded-lg animate-fade-in">
                <div className="flex flex-col gap-1.5">
                  <label className="text-[11px] font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                    Assignee
                  </label>
                  <select
                    value={formAssignee}
                    onChange={(e) => setFormAssignee(e.target.value)}
                    className="p-1.5 bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded text-xs focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
                  >
                    <option value="">Unassigned</option>
                    {users.map(u => (
                      <option key={u.id} value={u.email}>{u.email}</option>
                    ))}
                  </select>
                </div>
                <div className="flex flex-col gap-1.5">
                  <label className="text-[11px] font-semibold uppercase tracking-wider text-[var(--text-muted)]">
                    Due Date
                  </label>
                  <input
                    type="date"
                    value={formDueDate}
                    onChange={(e) => setFormDueDate(e.target.value)}
                    className="p-1.5 bg-[var(--surface)] text-[var(--text-primary)] border border-[var(--border-strong)] rounded text-xs focus:outline-none focus:ring-1 focus:ring-[var(--primary)]"
                  />
                </div>
              </div>
            )}
          </div>

          <div className="flex items-center justify-end gap-3 mt-6 pt-4 border-t border-[var(--border)]">
            <Button variant="outline" onClick={() => setIsCreateOpen(false)} disabled={isPending}>
              Cancel
            </Button>
            <Button onClick={handleCreateNote} disabled={isPending} className="bg-[--primary] hover:bg-[--primary-hover] text-white shadow-sm">
              {isPending ? 'Saving...' : 'Create Thread'}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

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
