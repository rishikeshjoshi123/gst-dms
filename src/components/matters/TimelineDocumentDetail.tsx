'use client'

import { X, FileText, Calendar, ExternalLink, StickyNote, Plus, Trash2, Pin, Check, Edit2, Loader2, RefreshCw } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useState, useTransition, useEffect, useRef } from 'react'
import { toast } from 'sonner'
import { createNote, updateNote, deleteNote } from '@/lib/actions/notes'
import { updateDocumentMetadata } from '@/lib/actions/document'
import { reprocessDocument } from '@/lib/actions/reprocess'

function humanizeKey(key: string) {
  return key
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .split(' ')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}

function EditableField({ 
  label, 
  value, 
  type = 'text', 
  onSave, 
  disabled 
}: { 
  label: string, 
  value: any, 
  type?: string, 
  onSave: (val: any) => Promise<void>,
  disabled?: boolean
}) {
  const [isEditing, setIsEditing] = useState(false)
  const [editValue, setEditValue] = useState(value ?? '')
  const [isSaving, setIsSaving] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (isEditing && inputRef.current) inputRef.current.focus()
  }, [isEditing])

  const handleSave = async () => {
    if (editValue === value) {
      setIsEditing(false)
      return
    }
    setIsSaving(true)
    await onSave(type === 'number' ? Number(editValue) : editValue)
    setIsSaving(false)
    setIsEditing(false)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleSave()
    if (e.key === 'Escape') {
      setIsEditing(false)
      setEditValue(value ?? '')
    }
  }

  return (
    <div className="flex flex-col gap-1.5 p-2 rounded hover:bg-slate-50 transition-colors group relative">
      <h5 className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">
        {label}
      </h5>
      {isEditing ? (
        <div className="flex items-center gap-1.5">
          <input
            ref={inputRef}
            type={type === 'number' ? 'number' : 'text'}
            value={editValue}
            onChange={(e) => setEditValue(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={isSaving || disabled}
            className="w-full text-sm font-medium text-[--text-primary] bg-white border border-blue-400 focus:ring-2 focus:ring-blue-200 outline-none rounded px-2 py-1 shadow-sm"
          />
          <button 
            onClick={handleSave} 
            disabled={isSaving || disabled}
            className="p-1.5 text-green-600 hover:bg-green-100 rounded transition-colors shrink-0"
          >
            {isSaving ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} />}
          </button>
          <button 
            onClick={() => { setIsEditing(false); setEditValue(value ?? ''); }} 
            disabled={isSaving || disabled}
            className="p-1.5 text-red-600 hover:bg-red-100 rounded transition-colors shrink-0"
          >
            <X size={14} />
          </button>
        </div>
      ) : (
        <div className="flex items-center justify-between gap-2 min-h-[28px]">
          <div className={`text-sm ${!value ? 'text-[--text-muted] italic' : 'text-[--text-primary] font-medium'}`}>
            {type === 'number' && value !== null && value !== undefined 
              ? `₹${Number(value).toLocaleString('en-IN')}` 
              : (value || 'Not Extracted')}
          </div>
          {!disabled && (
            <button 
              onClick={() => setIsEditing(true)}
              className="p-1.5 text-[--primary] opacity-0 group-hover:opacity-100 hover:bg-[--primary]/10 rounded transition-all"
              title="Edit value"
            >
              <Edit2 size={12} />
            </button>
          )}
        </div>
      )}
    </div>
  )
}

export function TimelineDocumentDetail({ 
  doc, 
  notes: propNotes = [], 
  onClose 
}: { 
  doc: any
  notes?: any[]
  onClose?: () => void 
}) {
  const [activeTab, setActiveTab] = useState<'details' | 'notes'>('details')
  const [notes, setNotes] = useState<any[]>(propNotes)
  const [newNoteContent, setNewNoteContent] = useState('')
  const [newNoteType, setNewNoteType] = useState<'general' | 'hearing_note' | 'client_instruction' | 'research_note'>('general')
  const [isPending, startTransition] = useTransition()
  const [isReprocessing, setIsReprocessing] = useState(false)
  const [activeQuote, setActiveQuote] = useState<{ text: string, pageNumber: number } | null>(null)

  const handleReprocess = async () => {
    setIsReprocessing(true)
    toast.info('Triggering AI reprocessing for this document...')
    const res = await reprocessDocument(doc.id, false)
    setIsReprocessing(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Reprocessing triggered. Processing with AI in the background...')
    }
  }
  useEffect(() => {
    const handleQuote = (e: CustomEvent) => {
      if (e.detail && e.detail.quote) {
        setActiveQuote({
          text: e.detail.quote,
          pageNumber: e.detail.pageNumber
        });
        setActiveTab('notes');
      }
    };
    window.addEventListener('SET_PDF_QUOTE', handleQuote as EventListener);
    return () => window.removeEventListener('SET_PDF_QUOTE', handleQuote as EventListener);
  }, []);

  const docNotes = notes.filter(n => n.document_id === doc.id)

  const handleAddNote = () => {
    if (!newNoteContent.trim()) return
    startTransition(async () => {
      const res = await createNote({
        matterId: doc.matter_id,
        documentId: doc.id,
        content: newNoteContent,
        templateType: newNoteType,
        isActionItem: false,
        quote: activeQuote?.text,
        pageNumber: activeQuote?.pageNumber
      })
      if (res.error) {
        toast.error(res.error)
      } else {
        setNotes(prev => [res.note, ...prev])
        setNewNoteContent('')
        setActiveQuote(null)
        toast.success('Note added successfully')
      }
    })
  }

  const handleDeleteNote = async (noteId: string) => {
    if (!confirm('Are you sure you want to delete this note?')) return
    const res = await deleteNote(noteId)
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.filter(n => n.id !== noteId))
      toast.success('Note deleted')
    }
  }

  const handleTogglePin = async (note: any) => {
    const newPinned = !note.is_pinned
    const res = await updateNote(note.id, { is_pinned: newPinned })
    if (res.error) {
      toast.error(res.error)
    } else {
      setNotes(prev => prev.map(n => n.id === note.id ? { ...n, is_pinned: newPinned } : n).sort((a, b) => {
        if (a.is_pinned !== b.is_pinned) return a.is_pinned ? -1 : 1
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      }))
      toast.success(newPinned ? 'Note pinned' : 'Note unpinned')
    }
  }

  const handleUpdateMetadata = async (key: string, value: any) => {
    const res = await updateDocumentMetadata(doc.id, key, value)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Metadata updated successfully')
    }
    // we don't need to manually update local state since the component will receive updated props via Server Component refresh triggered by revalidatePath in action
  }

  const metadata = doc.raw_metadata || {}
  const amounts = metadata.extracted_amounts || {}
  const viewUrl = `/matters/${doc.matter_id}/documents/${doc.id}`

  return (
    <div className="flex flex-col h-full min-h-[600px] border border-[--border-subtle] bg-white rounded-lg shadow-xl overflow-hidden animate-in slide-in-from-right-4 duration-300">
      
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-[--border-subtle] bg-[--bg-muted]/20">
        <div className="flex items-center gap-3 min-w-0">
          <div className="p-2 rounded-md bg-[--primary]/10 text-[--primary]">
            <FileText size={20} />
          </div>
          <div className="flex flex-col min-w-0">
            <h3 className="text-base font-semibold text-[--text-primary] truncate pr-4">
              {doc.reference_number || doc.storage_path.split('/').pop()}
            </h3>
            <div className="flex items-center gap-2 mt-0.5">
              {doc.doc_type && <Badge variant="muted" className="text-[10px] uppercase h-4 px-1.5 py-0">{doc.doc_type}</Badge>}
              <span className="text-xs text-[--text-muted] flex items-center gap-1">
                <Calendar size={12} />
                {doc.doc_date ? new Date(doc.doc_date).toLocaleDateString() : 'Unknown date'}
              </span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <Button variant="outline" size="sm" onClick={handleReprocess} disabled={isReprocessing} className="h-8 text-xs shrink-0 text-[--text-secondary]">
            {isReprocessing ? <RefreshCw size={14} className="mr-1.5 animate-spin" /> : <RefreshCw size={14} className="mr-1.5" />}
            Reprocess
          </Button>
          <a href={viewUrl} className="inline-flex items-center justify-center rounded-md text-sm font-medium h-8 px-3 gap-1.5 bg-[--primary] text-white hover:bg-[--primary-hover] shadow-sm transition-colors">
            <ExternalLink size={14} />
            View PDF
          </a>
          {onClose && (
            <Button variant="ghost" size="icon" className="h-8 w-8 text-[--text-muted] hover:text-[--text-primary]" onClick={onClose}>
              <X size={16} />
            </Button>
          )}
        </div>
      </div>

      {/* Tabs Selector */}
      <div className="flex border-b border-[--border-subtle] bg-slate-50/50 px-4 shrink-0">
        <button
          onClick={() => setActiveTab('details')}
          className={`flex items-center gap-1.5 py-2.5 px-3 text-xs font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === 'details'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <FileText size={14} />
          Details
        </button>
        <button
          onClick={() => setActiveTab('notes')}
          className={`flex items-center gap-1.5 py-2.5 px-3 text-xs font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === 'notes'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <StickyNote size={14} />
          Notes
          <Badge variant="muted" className="ml-1 px-1 py-0 text-[10px] h-4">
            {docNotes.length}
          </Badge>
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-5 custom-scrollbar">
        {activeTab === 'details' ? (
          <div className="flex flex-col gap-6">
          
          {/* Summary */}
          {doc.summary && (
            <div className="flex flex-col gap-2 bg-slate-50 border border-[--border-subtle] p-4 rounded-lg shadow-sm">
              <h4 className="text-[11px] font-bold text-[--text-muted] uppercase tracking-wider">AI Synopsis</h4>
              <p className="text-sm text-[--text-secondary] leading-relaxed">{doc.summary}</p>
            </div>
          )}

          {/* Core Extracted Metadata Grid */}
          <div className="flex flex-col gap-3">
            <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1.5 px-1">
              Core Details
            </h4>
            <div className="grid grid-cols-2 gap-x-4 gap-y-2">
              <EditableField label="Client Name" value={metadata.client_name} onSave={(val) => handleUpdateMetadata('client_name', val)} />
              <EditableField label="GSTIN" value={metadata.gstin} onSave={(val) => handleUpdateMetadata('gstin', val)} />
              <EditableField label="Reference Number" value={metadata.reference_number} onSave={(val) => handleUpdateMetadata('reference_number', val)} />
              <EditableField label="Document Type" value={metadata.doc_type} onSave={(val) => handleUpdateMetadata('doc_type', val)} />
              <EditableField label="Financial Year" value={metadata.financial_year} onSave={(val) => handleUpdateMetadata('financial_year', val)} />
              <EditableField label="Tax Period" value={metadata.tax_period} onSave={(val) => handleUpdateMetadata('tax_period', val)} />
            </div>
          </div>

          {/* Financials Extracted Metadata Grid */}
          <div className="flex flex-col gap-3 mt-2">
            <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1.5 px-1">
              Extracted Amounts
            </h4>
            <div className="grid grid-cols-2 gap-x-4 gap-y-2">
              <EditableField label="Tax" value={amounts.tax} type="number" onSave={(val) => handleUpdateMetadata('extracted_amounts.tax', val)} />
              <EditableField label="Interest" value={amounts.interest} type="number" onSave={(val) => handleUpdateMetadata('extracted_amounts.interest', val)} />
              <EditableField label="Penalty" value={amounts.penalty} type="number" onSave={(val) => handleUpdateMetadata('extracted_amounts.penalty', val)} />
              <EditableField label="Total Demand" value={amounts.total_demand} type="number" onSave={(val) => handleUpdateMetadata('extracted_amounts.total_demand', val)} />
            </div>
          </div>

          {/* System Info */}
          <div className="flex flex-col gap-3 pt-6 border-t border-[--border-subtle] mt-4">
            <h4 className="text-[11px] font-bold text-[--text-muted] uppercase tracking-wider px-1">System Info</h4>
            <div className="grid grid-cols-2 gap-4 px-1">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">Status</span>
                <Badge variant={doc.status === 'needs_review' ? 'warning' : doc.status === 'failed' ? 'danger' : 'muted'} className="w-fit">{doc.status.replace('_', ' ')}</Badge>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">Storage Path</span>
                <span className="text-xs font-mono text-[--text-secondary] break-all bg-slate-50 p-1.5 rounded border border-slate-100">{doc.storage_path}</span>
              </div>
              {doc.review_reason && (
                <div className="flex flex-col gap-1 col-span-2 mt-2 p-3 rounded-md bg-[--danger-muted] border border-[--danger] text-[--danger] text-xs shadow-sm">
                  <span className="font-semibold uppercase tracking-wider text-[10px]">Error Details</span>
                  <span className="leading-relaxed">{doc.review_reason}</span>
                </div>
              )}
            </div>
          </div>

          </div>
        ) : (
          <div className="flex flex-col gap-5 h-full">
            {/* Quick Add Note Form */}
            <div className="flex flex-col gap-2 p-3 bg-slate-50 border border-[#E5E2DC] rounded-lg shadow-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="text-[10px] font-bold uppercase tracking-wider text-[#78716C]">Quick Note</span>
                <select
                  value={newNoteType}
                  onChange={(e: any) => setNewNoteType(e.target.value)}
                  className="p-1 px-2 text-[11px] font-medium bg-white border border-[#C9C5BE] rounded outline-none shadow-sm"
                >
                  <option value="general">General</option>
                  <option value="hearing_note">Hearing Note</option>
                  <option value="client_instruction">Client Instruction</option>
                  <option value="research_note">Research Note</option>
                </select>
              </div>
              
              {activeQuote && (
                <div className="flex flex-col gap-1.5 p-2.5 bg-yellow-50/50 border-l-2 border-amber-400 rounded-r text-xs text-[--text-secondary] relative group mt-1 shadow-sm">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold text-amber-700/80 text-[10px] uppercase tracking-wide flex items-center gap-1.5">
                      <FileText size={10} /> Selected from Page {activeQuote.pageNumber}
                    </span>
                    <button 
                      onClick={() => setActiveQuote(null)}
                      className="text-amber-500 hover:text-amber-700 opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded hover:bg-amber-100"
                    >
                      <X size={12} />
                    </button>
                  </div>
                  <p className="italic font-medium text-amber-900/90 leading-relaxed">"{activeQuote.text}"</p>
                </div>
              )}

              <textarea
                value={newNoteContent}
                onChange={(e) => setNewNoteContent(e.target.value)}
                placeholder="Type note content..."
                className="w-full min-h-[80px] p-2.5 text-xs text-[--text-primary] bg-white border border-[#C9C5BE] rounded outline-none resize-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 shadow-inner mt-1"
              />
              <Button 
                onClick={handleAddNote} 
                disabled={isPending || !newNoteContent.trim()} 
                size="sm" 
                className="self-end bg-blue-600 hover:bg-blue-700 text-white text-xs font-semibold h-8 px-4 mt-2 shadow-sm"
              >
                {isPending ? <Loader2 size={12} className="animate-spin mr-1.5" /> : <Plus size={12} className="mr-1.5" />} Save Note
              </Button>
            </div>

            {/* Notes List */}
            {docNotes.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center border border-dashed border-[--border-strong] rounded-lg mt-2">
                <StickyNote size={24} className="text-slate-300 mb-2" />
                <span className="text-[--text-muted] text-sm font-medium">No notes attached.</span>
              </div>
            ) : (
              <div className="flex flex-col gap-4 overflow-y-auto pr-1">
                {docNotes.map((note) => (
                  <div key={note.id} className="p-3 bg-white border border-[#E5E2DC] rounded-lg shadow-sm flex flex-col relative group">
                    <div className="flex items-center justify-between gap-2 mb-2">
                      <span className="text-[9px] font-bold uppercase tracking-wider text-[#A8A29E] bg-slate-100 border border-slate-200 px-1.5 py-0.5 rounded">
                        {note.template_type.replace('_', ' ')}
                      </span>
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                        <button
                          onClick={() => handleTogglePin(note)}
                          className={`p-1 rounded text-[#A8A29E] hover:text-amber-500 hover:bg-amber-50`}
                          title="Pin Note"
                        >
                          <Pin size={11} className={note.is_pinned ? 'fill-current text-amber-500' : ''} />
                        </button>
                        <button
                          onClick={() => handleDeleteNote(note.id)}
                          className="p-1 rounded text-[#A8A29E] hover:text-red-500 hover:bg-red-50"
                          title="Delete Note"
                        >
                          <Trash2 size={11} />
                        </button>
                      </div>
                    </div>
                    {note.quote && (
                      <div 
                        onClick={() => {
                          window.dispatchEvent(new CustomEvent('JUMP_TO_PDF_PAGE', { detail: { pageNumber: note.page_number } }))
                        }}
                        className="mb-3 p-2 bg-slate-50 border-l-2 border-blue-400 rounded-r text-xs text-[--text-secondary] italic cursor-pointer hover:bg-blue-50 transition-colors shadow-sm"
                        title={`Jump to Page ${note.page_number}`}
                      >
                        "{note.quote}"
                      </div>
                    )}
                    <p className="text-[13px] text-[#1C1917] whitespace-pre-wrap leading-relaxed">{note.content}</p>
                    <div className="mt-3 pt-2 border-t border-slate-100 flex items-center justify-between text-[10px] text-[#A8A29E] font-medium">
                      <span>{note.author?.email || 'System'}</span>
                      <span>{new Date(note.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
