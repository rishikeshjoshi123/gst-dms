'use client'

import { X, FileText, Calendar, ExternalLink, StickyNote, Plus, Trash2, Pin, Check, Edit2, Loader2, RefreshCw } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useState, useTransition, useEffect, useRef } from 'react'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'
import { createNote, updateNote, deleteNote } from '@/lib/actions/notes'
import { updateDocumentMetadata, deleteDocument } from '@/lib/actions/document'
import { reprocessDocument } from '@/lib/actions/reprocess'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { ReassignDocumentDialog } from './ReassignDocumentDialog'
import { MoveRight } from 'lucide-react'

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
  options = [],
  onSave, 
  disabled 
}: { 
  label: string, 
  value: any, 
  type?: 'text' | 'number' | 'date' | 'select', 
  options?: string[],
  onSave: (val: any) => Promise<void>,
  disabled?: boolean
}) {
  const [isEditing, setIsEditing] = useState(false)
  const [editValue, setEditValue] = useState(value ?? '')
  const [isSaving, setIsSaving] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const selectRef = useRef<HTMLSelectElement>(null)

  useEffect(() => {
    if (isEditing) {
      if (type === 'select' && selectRef.current) selectRef.current.focus()
      else if (inputRef.current) inputRef.current.focus()
    }
  }, [isEditing, type])

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
          {type === 'select' ? (
            <select
              ref={selectRef}
              value={editValue}
              onChange={(e) => setEditValue(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={isSaving || disabled}
              className="w-full text-sm font-medium text-[var(--text-primary)] bg-[var(--bg)] border border-[var(--border)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded px-2 py-1 shadow-sm"
            >
              <option value="">Select...</option>
              {options.map(opt => <option key={opt} value={opt}>{opt}</option>)}
            </select>
          ) : (
            <input
              ref={inputRef}
              type={type === 'number' ? 'number' : type === 'date' ? 'date' : 'text'}
              value={editValue}
              onChange={(e) => setEditValue(e.target.value)}
              onKeyDown={handleKeyDown}
              disabled={isSaving || disabled}
              className="flex-1 min-w-0 w-full text-sm font-medium text-[var(--text-primary)] bg-[var(--bg)] border border-[var(--border)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded px-2 py-1 shadow-sm"
            />
          )}
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
          <div className={`flex-1 min-w-0 break-words text-sm ${!value ? 'text-[--text-muted] italic' : 'text-[--text-primary] font-medium'}`}>
            {type === 'number' && value !== null && value !== undefined 
              ? `₹${Number(value).toLocaleString('en-IN')}` 
              : type === 'date' && value ? new Date(value).toLocaleDateString()
              : (value || 'Not Extracted')}
          </div>
          {!disabled && (
            <button 
              onClick={() => setIsEditing(true)}
              className="shrink-0 p-1.5 text-[--primary] opacity-0 group-hover:opacity-100 hover:bg-[--primary]/10 rounded transition-all"
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
  allDocuments = [],
  links = [],
  notes: propNotes = [], 
  onClose 
}: { 
  doc: any
  allDocuments?: any[]
  links?: any[]
  notes?: any[]
  onClose?: () => void 
}) {
  const [activeTab, setActiveTab] = useState<'details' | 'notes'>('details')
  const [isSynopsisOpen, setIsSynopsisOpen] = useState(false)
  const [notes, setNotes] = useState<any[]>(propNotes)
  const [newNoteContent, setNewNoteContent] = useState('')
  const [newNoteType, setNewNoteType] = useState<'general' | 'hearing_note' | 'client_instruction' | 'research_note'>('general')
  const [isPending, startTransition] = useTransition()
  const [isReprocessing, setIsReprocessing] = useState(false)
  const [activeQuote, setActiveQuote] = useState<{ text: string, pageNumber: number } | null>(null)

  const [isDeleting, setIsDeleting] = useState(false)
  const [isDocConfirmOpen, setIsDocConfirmOpen] = useState(false)
  const [isReassignOpen, setIsReassignOpen] = useState(false)
  const [pendingNoteDeleteId, setPendingNoteDeleteId] = useState<string | null>(null)

  const handleDeleteDocument = async () => {
    setIsDeleting(true)
    const res = await deleteDocument(doc.id)
    setIsDeleting(false)
    setIsDocConfirmOpen(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Document deleted successfully')
      onClose?.()
    }
  }

  const handleReprocess = async () => {
    setIsReprocessing(true)
    toast.info('Triggering reprocessing for this document...')
    const res = await reprocessDocument(doc.id, false)
    setIsReprocessing(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Reprocessing triggered. Processing in the background...')
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

  const handleDeleteNote = async () => {
    if (!pendingNoteDeleteId) return
    const noteId = pendingNoteDeleteId
    const res = await deleteNote(noteId)
    setPendingNoteDeleteId(null)
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

  // Find linked documents
  const linkedDocIds = new Set<string>()
  links.forEach(l => {
    if (l.from_doc_id === doc.id && l.to_doc_id) linkedDocIds.add(l.to_doc_id)
    if (l.to_doc_id === doc.id && l.from_doc_id) linkedDocIds.add(l.from_doc_id)
  })
  
  const linkedDocs = allDocuments.filter(d => linkedDocIds.has(d.id))

  return (
    <div className="flex flex-col h-full border border-[var(--border-strong)] bg-[var(--surface)] rounded-lg shadow-xl overflow-hidden animate-in slide-in-from-right-4 duration-300">
      
      {/* Header */}
      <div className="flex items-start justify-between p-3 border-b border-[--border-subtle] bg-[--bg-muted]/20 gap-3">
        <div className="flex items-start gap-2.5 min-w-0 flex-1">
          <div className="p-1.5 rounded-md bg-[--primary]/10 text-[--primary] mt-0.5 shrink-0">
            <FileText size={16} />
          </div>
          <div className="flex flex-col min-w-0 w-full">
            <h3 className="text-sm font-semibold text-[--text-primary] truncate mb-0.5" title={doc.reference_number || doc.storage_path.split('/').pop()}>
              {doc.reference_number || doc.storage_path.split('/').pop()}
            </h3>
            <div className="flex items-center flex-wrap gap-1.5">
              {doc.doc_type && <Badge variant="muted" className="text-[9px] uppercase h-4 px-1 py-0">{doc.doc_type}</Badge>}
              <span className="text-[10px] text-[--text-muted] flex items-center gap-1 shrink-0">
                <Calendar size={10} />
                {doc.doc_date ? new Date(doc.doc_date).toLocaleDateString() : 'Unknown'}
              </span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <Button variant="outline" size="icon" onClick={() => setIsReassignOpen(true)} className="h-7 w-7 text-[--text-secondary]" title="Reassign Document">
            <MoveRight size={12} />
          </Button>
          <Button variant="outline" size="icon" onClick={handleReprocess} disabled={isReprocessing || isDeleting} className="h-7 w-7 text-[--text-secondary]" title="Reprocess Document">
            {isReprocessing ? <RefreshCw size={12} className="animate-spin" /> : <RefreshCw size={12} />}
          </Button>
          <Button variant="outline" size="icon" onClick={() => setIsDocConfirmOpen(true)} disabled={isDeleting || isReprocessing} className="h-7 w-7 text-red-600 hover:text-red-700 hover:bg-red-50 dark:bg-red-950/20 dark:border-red-800" title="Delete Document">
            {isDeleting ? <Loader2 size={12} className="animate-spin" /> : <Trash2 size={12} />}
          </Button>
          <a href={viewUrl} className="inline-flex items-center justify-center rounded-md text-[11px] font-medium h-7 px-2.5 gap-1 bg-blue-600 text-white hover:bg-blue-700 shadow-sm transition-colors">
            <ExternalLink size={12} />
            View
          </a>
          {onClose && (
            <Button variant="ghost" size="icon" className="h-7 w-7 text-[--text-muted] hover:text-[--text-primary] ml-0.5" onClick={onClose}>
              <X size={14} />
            </Button>
          )}
        </div>
      </div>

      {/* Tabs Selector */}
      <div className="flex border-b border-[var(--border)] bg-[var(--surface-hover)] px-3 shrink-0">
        <button
          onClick={() => setActiveTab('details')}
          className={`flex items-center gap-1.5 py-2 px-2 text-[11px] font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === 'details'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <FileText size={12} />
          Details
        </button>
        <button
          onClick={() => setActiveTab('notes')}
          className={`flex items-center gap-1.5 py-2 px-2 text-[11px] font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === 'notes'
              ? 'border-blue-600 text-blue-600'
              : 'border-transparent text-[--text-muted] hover:text-[--text-primary]'
          }`}
        >
          <StickyNote size={12} />
          Notes
          <Badge variant="muted" className="ml-1 px-1 py-0 text-[9px] h-3.5">
            {docNotes.length}
          </Badge>
        </button>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 custom-scrollbar">
        {activeTab === 'details' ? (
          <div className="flex flex-col gap-4">
          
          {/* Summary */}
          {doc.summary && (
            <div className="flex flex-col gap-2 bg-[var(--bg)] border border-[var(--border)] p-4 rounded-lg shadow-sm">
              <div 
                className="flex items-center justify-between cursor-pointer group"
                onClick={() => setIsSynopsisOpen(!isSynopsisOpen)}
              >
                <h4 className="text-[11px] font-bold text-[--text-muted] uppercase tracking-wider group-hover:text-[--text-primary] transition-colors">Document Synopsis</h4>
                <span className="text-xs font-semibold text-slate-400 group-hover:text-slate-600">{isSynopsisOpen ? 'Collapse' : 'Expand'}</span>
              </div>
              {isSynopsisOpen && (
                <p className="text-sm text-[--text-secondary] leading-relaxed mt-1 animate-in fade-in slide-in-from-top-2">{doc.summary}</p>
              )}
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
              <EditableField label="Reference Number" value={doc.reference_number || metadata.reference_number} onSave={(val) => handleUpdateMetadata('reference_number', val)} />
              <EditableField label="Document Type" value={doc.doc_type || metadata.doc_type} type="select" options={['DRC-01', 'DRC-01A', 'DRC-01C', 'DRC-07', 'DRC-03', 'SCN', 'OIO', 'OIA', 'APL-01', 'APL-02', 'APL-05', 'STAY', 'REPLY', 'HC_PETITION', 'HC_ORDER', 'SC_PETITION', 'SC_ORDER', 'OTHER']} onSave={(val) => handleUpdateMetadata('doc_type', val)} />
              <EditableField label="Document Date" value={doc.doc_date || metadata.doc_date} type="date" onSave={(val) => handleUpdateMetadata('doc_date', val)} />
              <EditableField 
                label="Financial Year" 
                value={doc.financial_year || metadata.financial_year} 
                type="select"
                options={['2017-18', '2018-19', '2019-20', '2020-21', '2021-22', '2022-23', '2023-24', '2024-25', '2025-26', 'Unknown FY']}
                onSave={(val) => handleUpdateMetadata('financial_year', val)} 
              />
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

          {/* Linked Documents */}
          {linkedDocs.length > 0 && (
            <div className="flex flex-col gap-3 pt-6 border-t border-[--border-subtle] mt-2">
              <h4 className="text-sm font-semibold text-[--text-primary] px-1">
                Linked Documents
              </h4>
              <div className="grid grid-cols-1 gap-2">
                {linkedDocs.map(ldoc => {
                  // Determine the direction of the link from the current document's perspective
                  // DB convention: from_doc_id = CHILD, to_doc_id = PARENT
                  const link = links.find(l =>
                    (l.from_doc_id === doc.id && l.to_doc_id === ldoc.id) ||
                    (l.to_doc_id === doc.id && l.from_doc_id === ldoc.id)
                  )
                  const rawType = link?.link_type || 'linked'
                  const isCurrentDocChild = link?.from_doc_id === doc.id
                  
                  // Build a readable, directional label
                  // If current doc is child: "This doc [responds_to] [ldoc]"  → show: "[responds to] →"
                  // If current doc is parent: "[ldoc] [responds_to] this doc" → show: "← [responds to]"
                  const typeLabel = rawType.replace(/_/g, ' ')
                  const relationLabel = isCurrentDocChild
                    ? `${typeLabel} →`          // "This doc responds to → [ldoc]" (ldoc is parent)
                    : `← ${typeLabel}`           // "[ldoc] responds to ← this doc" (ldoc is child)
                  const roleLabel = isCurrentDocChild ? 'Parent' : 'Child'
                  
                  return (
                    <div key={ldoc.id} className="flex items-center justify-between p-3 rounded-lg border border-[var(--border)] bg-[var(--bg)] hover:bg-[var(--surface-hover)] transition-colors">
                      <div className="flex flex-col gap-1 min-w-0">
                        <span className="text-sm font-medium text-[--text-primary] truncate">{ldoc.reference_number || ldoc.storage_path.split('/').pop()}</span>
                        <div className="flex items-center gap-2 flex-wrap">
                          <Badge variant="muted" className={`text-[9px] uppercase tracking-wider py-0 px-1 font-semibold ${isCurrentDocChild ? 'text-[var(--primary)] border-[var(--primary)]/30' : 'text-emerald-600 dark:text-emerald-400 border-emerald-200'}`}>
                            {relationLabel}
                          </Badge>
                          <Badge variant="outline" className="text-[9px] uppercase tracking-wider py-0 px-1 text-[var(--text-muted)]">
                            {roleLabel}
                          </Badge>
                          {ldoc.document_class === 'supporting' && (
                            <Badge variant="outline" className="text-[9px] uppercase tracking-wider py-0 px-1 bg-slate-100 text-slate-600">Supporting</Badge>
                          )}
                          <span className="text-xs text-[--text-muted]">{ldoc.doc_date ? new Date(ldoc.doc_date).toISOString().split('T')[0] : ''}</span>
                        </div>
                      </div>
                      <a 
                        href={`/matters/${ldoc.matter_id}/documents/${ldoc.id}`}
                        target="_blank"
                        rel="noreferrer"
                        className="p-2 text-blue-600 hover:bg-blue-100 rounded transition-colors"
                        title="Open Document"
                      >
                        <ExternalLink size={14} />
                      </a>
                    </div>
                  )
                })}
              </div>
            </div>
          )}

          {/* System Info */}
          <div className="flex flex-col gap-3 pt-6 border-t border-[--border-subtle] mt-4">
            <h4 className="text-[11px] font-bold text-[--text-muted] uppercase tracking-wider px-1">System Info</h4>
            <div className="grid grid-cols-2 gap-4 px-1">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">Status</span>
                <div className="flex items-center gap-2">
                  <Badge 
                    variant={doc.status === 'needs_review' ? 'warning' : doc.status === 'failed' ? 'danger' : 'muted'} 
                    className={cn("w-fit", doc.status === 'failed' && doc.review_reason ? "cursor-pointer hover:opacity-80" : "")}
                    onClick={() => {
                      if (doc.status === 'failed' && doc.review_reason) {
                        toast.error(`Error details: ${doc.review_reason}`, { duration: 10000, dismissible: true })
                      }
                    }}
                  >
                    {doc.status.replace('_', ' ')}
                  </Badge>
                </div>
              </div>
              <div className="flex flex-col gap-1">
                <span className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">Storage Path</span>
                <span className="text-xs font-mono text-[var(--text-secondary)] break-all bg-[var(--bg)] p-1.5 rounded border border-[var(--border)]">{doc.storage_path}</span>
              </div>
            </div>
          </div>

          </div>
        ) : (
          <div className="flex flex-col gap-5 h-full">
            {/* Quick Add Note Form */}
            <div className="flex flex-col gap-2 p-3 bg-[var(--bg)] border border-[var(--border)] rounded-lg shadow-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-secondary)]">Quick Note</span>
                <select
                  value={newNoteType}
                  onChange={(e: any) => setNewNoteType(e.target.value)}
                  className="p-1 px-2 text-[11px] font-medium bg-[var(--surface)] border border-[var(--border)] text-[var(--text-primary)] rounded outline-none shadow-sm"
                >
                  <option value="general">General</option>
                  <option value="hearing_note">Hearing Note</option>
                  <option value="client_instruction">Client Instruction</option>
                  <option value="research_note">Research Note</option>
                </select>
              </div>
              
              {activeQuote && (
                <div className="flex flex-col gap-1.5 p-2.5 bg-amber-500/10 border-l-2 border-amber-500 rounded-r text-xs text-[var(--text-secondary)] relative group mt-1 shadow-sm">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold text-amber-600 dark:text-amber-400 text-[10px] uppercase tracking-wide flex items-center gap-1.5">
                      <FileText size={10} /> Selected from Page {activeQuote.pageNumber}
                    </span>
                    <button 
                      onClick={() => setActiveQuote(null)}
                      className="text-amber-500 hover:text-amber-700 opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded hover:bg-amber-500/20"
                    >
                      <X size={12} />
                    </button>
                  </div>
                  <p className="italic font-medium text-[var(--text-primary)] leading-relaxed">"{activeQuote.text}"</p>
                </div>
              )}

              <textarea
                value={newNoteContent}
                onChange={(e) => setNewNoteContent(e.target.value)}
                placeholder="Type note content..."
                className="w-full min-h-[80px] p-2.5 text-xs text-[var(--text-primary)] bg-[var(--surface)] border border-[var(--border)] rounded outline-none resize-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] shadow-inner mt-1"
              />
              <Button 
                onClick={handleAddNote} 
                disabled={isPending || !newNoteContent.trim()} 
                size="sm" 
                className="self-end bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-semibold h-8 px-4 mt-2 shadow-sm"
              >
                {isPending ? <Loader2 size={12} className="animate-spin mr-1.5" /> : <Plus size={12} className="mr-1.5" />} Save Note
              </Button>
            </div>

            {/* Notes List */}
            {docNotes.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center border border-dashed border-[var(--border-strong)] rounded-lg mt-2">
                <StickyNote size={24} className="text-[var(--text-disabled)] mb-2" />
                <span className="text-[var(--text-muted)] text-sm font-medium">No notes attached.</span>
              </div>
            ) : (
              <div className="flex flex-col gap-4 overflow-y-auto pr-1">
                {docNotes.map((note) => (
                  <div key={note.id} className="p-3 bg-[var(--surface)] border border-[var(--border)] rounded-lg shadow-sm flex flex-col relative group">
                    <div className="flex items-center justify-between gap-2 mb-2">
                      <span className="text-[9px] font-bold uppercase tracking-wider text-[var(--text-muted)] bg-[var(--bg)] border border-[var(--border)] px-1.5 py-0.5 rounded">
                        {note.template_type.replace('_', ' ')}
                      </span>
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                        <button
                          onClick={() => handleTogglePin(note)}
                          className={`p-1 rounded text-[var(--text-muted)] hover:text-amber-500 hover:bg-amber-500/10`}
                          title="Pin Note"
                        >
                          <Pin size={11} className={note.is_pinned ? 'fill-current text-amber-500' : ''} />
                        </button>
                        <button
                          onClick={() => setPendingNoteDeleteId(note.id)}
                          className="p-1 rounded text-[var(--text-muted)] hover:text-red-500 hover:bg-red-500/10"
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
                        className="mb-3 p-2 bg-[var(--bg)] border-l-2 border-blue-400 rounded-r text-xs text-[var(--text-secondary)] italic cursor-pointer hover:bg-[var(--surface-hover)] transition-colors shadow-sm"
                        title={`Jump to Page ${note.page_number}`}
                      >
                        "{note.quote}"
                      </div>
                    )}
                    <p className="text-[13px] text-[var(--text-primary)] whitespace-pre-wrap leading-relaxed">{note.content}</p>
                    <div className="mt-3 pt-2 border-t border-[var(--border)] flex items-center justify-between text-[10px] text-[var(--text-muted)] font-medium">
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

      <ConfirmDialog
        isOpen={isDocConfirmOpen}
        onClose={() => setIsDocConfirmOpen(false)}
        onConfirm={handleDeleteDocument}
        title="Delete Document?"
        description="Are you sure you want to delete this document? This will permanently remove it from the matter timeline."
        confirmText="Delete Document"
        variant="destructive"
        isPending={isDeleting}
      />

      <ConfirmDialog
        isOpen={!!pendingNoteDeleteId}
        onClose={() => setPendingNoteDeleteId(null)}
        onConfirm={handleDeleteNote}
        title="Delete Note?"
        description="Are you sure you want to delete this note? This action cannot be undone."
        confirmText="Delete Note"
        variant="destructive"
      />

      <ReassignDocumentDialog
        isOpen={isReassignOpen}
        onClose={() => {
          setIsReassignOpen(false)
        }}
        documentId={doc.id}
        currentMatterId={doc.matter_id}
      />
    </div>
  )
}
