'use client'

import { useState, useMemo, useTransition } from 'react'
import { toast } from 'sonner'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { Button } from '@/components/ui/button'
import { Search, Pin, Trash2, CheckCircle2, Circle, Calendar, User, FileText, Check, X, Edit2, AlertCircle, MessageSquarePlus, CornerDownRight, ExternalLink } from 'lucide-react'
import { updateNote, deleteNote, createNote } from '@/lib/actions/notes'
import { Badge } from '@/components/ui/badge'

const TEMPLATE_LABELS = {
  general: 'General',
  hearing_note: 'Hearing Note',
  client_instruction: 'Client Instruction',
  research_note: 'Research Note',
}

const TEMPLATE_COLORS = {
  general: 'bg-slate-100 text-slate-800 border-slate-200',
  hearing_note: 'bg-blue-50 text-blue-800 border-blue-200',
  client_instruction: 'bg-emerald-50 text-emerald-800 border-emerald-200',
  research_note: 'bg-purple-50 text-purple-800 border-purple-200',
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

  // Filter notes locally (only parent notes are filtered for the list, children are always kept for the thread)
  const allParentNotes = useMemo(() => notes.filter(n => !n.parent_note_id), [notes])
  const childNotesByParent = useMemo(() => {
    const map = new Map<string, any[]>()
    notes.filter(n => !!n.parent_note_id).forEach(n => {
      if (!map.has(n.parent_note_id)) map.set(n.parent_note_id, [])
      map.get(n.parent_note_id)!.push(n)
    })
    // Sort replies by oldest first
    for (const [key, replies] of map.entries()) {
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

  const handleTogglePin = async (note: any) => {
    const newPinned = !note.is_pinned
    const res = await updateNote(note.id, { is_pinned: newPinned })
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => {
        const updated = prev.map(n => n.id === note.id ? { ...n, is_pinned: newPinned } : n)
        return updated.sort((a, b) => {
          if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1
          return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        })
      })
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

  const handleDeleteNote = async (noteId: string) => {
    if (!confirm('Are you sure you want to delete this note?')) return
    const res = await deleteNote(noteId)
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
    <div className="flex flex-col flex-1 overflow-hidden max-w-7xl animate-fade-in">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Notes Hub' }]} />

      {/* Filter and Search Bar - Fixed at top */}
      <div className="flex flex-col md:flex-row gap-4 p-4 shrink-0 bg-white shadow-sm z-10 border-b border-[--border-subtle]">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-[#A8A29E]" size={16} />
          <input
            type="text"
            placeholder="Search notes content..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-4 py-2 text-sm bg-white border border-[--border-strong] rounded-lg focus:outline-none focus:ring-2 focus:ring-[--primary]"
          />
        </div>
        <select value={filterMatter} onChange={(e) => setFilterMatter(e.target.value)} className="px-3 py-2 text-sm bg-white border border-[--border-strong] rounded-lg outline-none">
          <option value="">All Matters</option>
          {matters.map(m => <option key={m.id} value={m.id}>{m.title}</option>)}
        </select>
        <select value={filterType} onChange={(e) => setFilterType(e.target.value)} className="px-3 py-2 text-sm bg-white border border-[--border-strong] rounded-lg outline-none">
          <option value="">All Template Types</option>
          {Object.entries(TEMPLATE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select value={filterActionItems} onChange={(e) => setFilterActionItems(e.target.value)} className="px-3 py-2 text-sm bg-white border border-[--border-strong] rounded-lg outline-none">
          <option value="all">All Notes & Tasks</option>
          <option value="notes_only">General Notes Only</option>
          <option value="pending_tasks">Pending Tasks</option>
          <option value="resolved_tasks">Completed Tasks</option>
        </select>
      </div>

      {/* Split Pane */}
      <div className="flex flex-1 min-h-0 overflow-hidden bg-[--bg-surface]">
        
        {/* Left Pane: Thread List */}
        <div className="w-1/3 min-w-[350px] border-r border-[--border-subtle] flex flex-col bg-slate-50/50">
          <div className="p-4 border-b border-[--border-subtle] bg-white shrink-0">
            <h2 className="text-sm font-semibold text-[--text-primary] uppercase tracking-wider">Conversations ({filteredThreads.length})</h2>
          </div>
          <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-3">
            {filteredThreads.length === 0 ? (
              <div className="py-10 text-center text-[--text-muted]">No threads found.</div>
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
                        ? 'bg-[--primary]/5 border-[--primary] ring-1 ring-[--primary]/20 shadow-sm' 
                        : 'bg-white border-[--border-subtle] hover:border-[--border-strong]'
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
                    <p className="text-sm text-[--text-primary] line-clamp-3 mb-2">{note.content}</p>
                    
                    <div className="flex items-center justify-between mt-auto pt-2 border-t border-[--border-subtle] text-xs">
                      <span className="text-[--text-muted]">{note.author?.email || 'Unknown'}</span>
                      {replyCount > 0 && (
                        <div className="flex items-center gap-1 text-[--text-secondary] font-medium bg-slate-100 px-2 py-0.5 rounded-full">
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
        <div className="flex-1 flex flex-col bg-white">
          {!selectedThread ? (
            <div className="flex-1 flex flex-col items-center justify-center text-[--text-muted]">
              <FileText size={48} className="text-[--border-strong] mb-4" />
              <p className="text-lg font-medium text-[--text-secondary]">Select a conversation to view details</p>
            </div>
          ) : (
            <>
              {/* Thread Header Context */}
              <div className="p-4 border-b border-[--border-subtle] bg-slate-50 flex items-center justify-between shrink-0">
                <div className="flex flex-col gap-1">
                  <h3 className="text-sm font-bold text-[--text-primary]">Thread Details</h3>
                  <div className="flex items-center gap-3 text-xs text-[--text-secondary]">
                    {selectedThread.matters && (
                      <span className="flex items-center gap-1">
                        <FileText size={12} /> {selectedThread.matters.title}
                      </span>
                    )}
                    {selectedThread.documents && (
                      <a href={`/matters/${selectedThread.matter_id}/documents/${selectedThread.document_id}`} className="flex items-center gap-1 text-[--primary] hover:underline font-mono">
                        <ExternalLink size={12} /> {selectedThread.documents.reference_number || 'Doc'}
                      </a>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <button onClick={() => handleTogglePin(selectedThread)} className={`p-2 rounded border transition-colors ${selectedThread.is_pinned ? 'border-amber-200 bg-amber-50 text-amber-600' : 'border-[--border-strong] text-[--text-secondary] hover:bg-slate-100'}`} title="Pin Thread">
                    <Pin size={14} className={selectedThread.is_pinned ? 'fill-current' : ''} />
                  </button>
                  <button onClick={() => handleDeleteNote(selectedThread.id)} className="p-2 rounded border border-[--border-strong] text-[--text-secondary] hover:border-red-200 hover:bg-red-50 hover:text-red-600 transition-colors" title="Delete Thread">
                    <Trash2 size={14} />
                  </button>
                </div>
              </div>

              {/* Thread Messages */}
              <div className="flex-1 overflow-y-auto p-6 flex flex-col gap-6">
                {/* Original Note */}
                <div className="flex flex-col gap-3">
                  {selectedThread.quote && (
                    <div className="ml-4 p-3 bg-yellow-50 border-l-4 border-amber-400 rounded-r-lg shadow-sm">
                      <div className="flex items-center justify-between mb-1">
                         <span className="text-[10px] font-bold uppercase tracking-wider text-amber-800">Quote from Page {selectedThread.page_number}</span>
                         <a href={`/matters/${selectedThread.matter_id}/documents/${selectedThread.document_id}#page=${selectedThread.page_number}`} className="text-amber-600 hover:text-amber-800"><ExternalLink size={12} /></a>
                      </div>
                      <p className="text-sm italic text-amber-900 leading-relaxed">"{selectedThread.quote}"</p>
                    </div>
                  )}

                  <div className="flex gap-4">
                    <div className="w-8 h-8 rounded-full bg-[--primary]/10 flex items-center justify-center text-[--primary] font-bold shrink-0 mt-1">
                      {selectedThread.author?.email?.[0].toUpperCase() || 'U'}
                    </div>
                    <div className="flex-1 flex flex-col">
                      <div className="flex items-baseline gap-2 mb-1">
                        <span className="font-semibold text-[--text-primary] text-sm">{selectedThread.author?.email || 'Unknown User'}</span>
                        <span className="text-xs text-[--text-muted]">{new Date(selectedThread.created_at).toLocaleString()}</span>
                      </div>
                      
                      {editingNoteId === selectedThread.id ? (
                        <div className="flex flex-col gap-2 mt-1">
                           <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full min-h-[100px] p-3 text-sm bg-white border border-[--border-strong] rounded focus:outline-none focus:ring-1 focus:ring-[--primary] resize-none"
                          />
                          <div className="flex gap-2">
                             <Button size="sm" onClick={() => handleSaveEdit(selectedThread.id)}>Save</Button>
                             <Button size="sm" variant="outline" onClick={() => setEditingNoteId(null)}>Cancel</Button>
                          </div>
                        </div>
                      ) : (
                        <div className="bg-white border border-[--border-subtle] rounded-2xl rounded-tl-sm p-4 shadow-sm relative group">
                          <p className="text-sm text-[--text-primary] whitespace-pre-wrap leading-relaxed">{selectedThread.content}</p>
                          <button onClick={() => startEditing(selectedThread)} className="absolute top-2 right-2 p-1.5 text-[--text-muted] hover:text-[--primary] opacity-0 group-hover:opacity-100 transition-opacity bg-white rounded-md shadow-sm border border-[--border-subtle]"><Edit2 size={12} /></button>
                        </div>
                      )}

                      {/* Action item block */}
                      {selectedThread.is_action_item && (
                        <div className={`mt-3 p-3 rounded-lg border flex flex-col gap-2 ${selectedThread.action_item_resolved ? 'bg-slate-50 border-slate-200' : 'bg-amber-50/50 border-amber-200'}`}>
                           <div className="flex items-center justify-between">
                              <span className="text-xs font-bold uppercase tracking-wider text-[--text-secondary]">Action Item</span>
                              <button onClick={() => handleToggleResolve(selectedThread)} className={`flex items-center gap-1.5 text-xs font-medium px-2 py-1 rounded transition-colors ${selectedThread.action_item_resolved ? 'text-emerald-700 bg-emerald-100' : 'text-amber-700 bg-amber-100'}`}>
                                {selectedThread.action_item_resolved ? <><CheckCircle2 size={14}/> Resolved</> : <><Circle size={14} /> Mark Resolved</>}
                              </button>
                           </div>
                           <div className="flex gap-4 text-xs">
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
                  <div key={reply.id} className="flex gap-4 ml-8 relative">
                    {/* Reply thread line */}
                    <div className="absolute -left-6 top-5 bottom-0 w-px bg-[--border-subtle]" />
                    <CornerDownRight size={16} className="absolute -left-6 top-4 text-[--border-strong]" />

                    <div className="w-8 h-8 rounded-full bg-slate-100 border border-slate-200 flex items-center justify-center text-slate-600 font-bold shrink-0 mt-1 text-xs">
                      {reply.author?.email?.[0].toUpperCase() || 'U'}
                    </div>
                    <div className="flex-1 flex flex-col">
                      <div className="flex items-baseline gap-2 mb-1">
                        <span className="font-semibold text-[--text-primary] text-sm">{reply.author?.email || 'Unknown User'}</span>
                        <span className="text-xs text-[--text-muted]">{new Date(reply.created_at).toLocaleString()}</span>
                      </div>
                      
                      {editingNoteId === reply.id ? (
                        <div className="flex flex-col gap-2 mt-1">
                           <textarea
                            value={editContent}
                            onChange={(e) => setEditContent(e.target.value)}
                            className="w-full min-h-[80px] p-3 text-sm bg-white border border-[--border-strong] rounded focus:outline-none focus:ring-1 focus:ring-[--primary] resize-none"
                          />
                          <div className="flex gap-2">
                             <Button size="sm" onClick={() => handleSaveEdit(reply.id)}>Save</Button>
                             <Button size="sm" variant="outline" onClick={() => setEditingNoteId(null)}>Cancel</Button>
                          </div>
                        </div>
                      ) : (
                        <div className="bg-white border border-[--border-subtle] rounded-2xl rounded-tl-sm p-4 shadow-sm relative group">
                          <p className="text-sm text-[--text-primary] whitespace-pre-wrap leading-relaxed">{reply.content}</p>
                          <div className="absolute top-2 right-2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                            <button onClick={() => startEditing(reply)} className="p-1.5 text-[--text-muted] hover:text-[--primary] bg-white rounded-md shadow-sm border border-[--border-subtle]"><Edit2 size={12} /></button>
                            <button onClick={() => handleDeleteNote(reply.id)} className="p-1.5 text-[--text-muted] hover:text-[--danger] bg-white rounded-md shadow-sm border border-[--border-subtle]"><Trash2 size={12} /></button>
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>

              {/* Reply Box */}
              <div className="p-4 border-t border-[--border-subtle] bg-slate-50 shrink-0">
                <div className="flex items-end gap-3 max-w-4xl mx-auto">
                  <div className="flex-1">
                    <textarea
                      value={replyContent}
                      onChange={e => setReplyContent(e.target.value)}
                      placeholder="Type a reply to this thread..."
                      className="w-full min-h-[50px] max-h-[150px] p-3 text-sm bg-white border border-[--border-strong] rounded-lg focus:outline-none focus:ring-2 focus:ring-[--primary] resize-y"
                    />
                  </div>
                  <Button 
                    onClick={() => handleReply(selectedThread)} 
                    disabled={isPending || !replyContent.trim()}
                    className="mb-1"
                  >
                    Reply
                  </Button>
                </div>
              </div>
            </>
          )}
        </div>

      </div>
    </div>
  )
}
