'use client'

import { X, FileText, Calendar, ExternalLink, StickyNote, Plus, Trash2, Pin, Loader2, RefreshCw } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useState, useTransition, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'
import { createNote, updateNote, deleteNote } from '@/lib/actions/notes'
import { correctInspectorField, type EditableFieldPath } from '@/lib/actions/document-field-decision'
import { formatInrDecimal } from '@/lib/documents/format-inr-decimal'
import { linkedDocumentDate, linkedDocumentIdentity, selectedDocumentIdentity } from '@/lib/documents/document-inspector-identity'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { deleteDocument } from '@/lib/actions/document'
import { reprocessDocument } from '@/lib/actions/reprocess'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { ReassignDocumentDialog } from './ReassignDocumentDialog'
import { MoveRight } from 'lucide-react'

function EffectiveMetadataField({ label, value, type = 'text', correction }: {
  label: string
  value: string | null
  type?: 'text' | 'date' | 'decimal'
  correction?: { onSave: (value: string) => Promise<void> }
}) {
  const [isEditing, setIsEditing] = useState(false)
  const [editValue, setEditValue] = useState(value ?? '')
  const [isSaving, setIsSaving] = useState(false)
  const displayValue = type === 'date' && value
    ? new Date(`${value}T00:00:00`).toLocaleDateString()
    : type === 'decimal' && value ? formatInrDecimal(value) : value

  const save = async () => {
    if (!correction || editValue === (value ?? '')) {
      setIsEditing(false)
      return
    }
    setIsSaving(true)
    await correction.onSave(editValue)
    setIsSaving(false)
    setIsEditing(false)
  }

  return (
    <div className="flex flex-col gap-1.5 p-2 rounded-[var(--radius-sm)]">
      <h5 className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">{label}</h5>
      {isEditing ? (
        <div className="flex flex-col gap-1.5 sm:flex-row">
          <Input
            aria-label={`Correct ${label}`}
            type={type === 'date' ? 'date' : 'text'}
            inputMode={type === 'decimal' ? 'decimal' : undefined}
            value={editValue}
            onChange={(event) => setEditValue(event.target.value)}
            onKeyDown={(event) => { if (event.key === 'Enter') void save(); if (event.key === 'Escape') { setEditValue(value ?? ''); setIsEditing(false) } }}
            autoFocus
            className="min-w-0 flex-1"
          />
          <Button type="button" size="sm" onClick={save} loading={isSaving}>Save</Button>
          <Button type="button" size="sm" variant="ghost" onClick={() => { setEditValue(value ?? ''); setIsEditing(false) }} disabled={isSaving}>Cancel</Button>
        </div>
      ) : (
        <div className="flex min-h-[28px] items-start gap-2">
          <div className={`min-w-0 flex-1 break-words text-sm ${displayValue ? 'text-[--text-primary] font-medium' : 'text-[--text-muted] italic'}`}>
            {displayValue || 'Unavailable'}
          </div>
          {correction && (
            <Button type="button" size="sm" variant="ghost" onClick={() => setIsEditing(true)}>Edit</Button>
          )}
        </div>
      )}
    </div>
  )
}

function DeferredMetadataField({ label, message }: { label: string; message: string }) {
  return (
    <div className="flex flex-col gap-1.5 p-2 rounded-[var(--radius-sm)]">
      <h5 className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">{label}</h5>
      <div className="min-h-[28px] break-words text-sm italic text-[--text-muted]">{message}</div>
    </div>
  )
}

export function TimelineDocumentDetail({ 
  doc, 
  allDocuments = [],
  links = [],
  notes: propNotes = [], 
  effectiveMetadata,
  inspectorMetadataByDocumentId,
  onClose,
  readOnly = false,
}: { 
  doc: any
  allDocuments?: any[]
  links?: any[]
  notes?: any[]
  effectiveMetadata?: DocumentInspectorMetadata
  inspectorMetadataByDocumentId?: Record<string, DocumentInspectorMetadata>
  onClose?: () => void
  readOnly?: boolean
}) {
  const [activeTab, setActiveTab] = useState<'details' | 'notes'>('details')
  const [isSynopsisOpen, setIsSynopsisOpen] = useState(false)
  const [notes, setNotes] = useState<any[]>(propNotes)
  const [newNoteContent, setNewNoteContent] = useState('')
  const [newNoteType, setNewNoteType] = useState<'general' | 'hearing_note' | 'client_instruction' | 'research_note'>('general')
  const [isPending, startTransition] = useTransition()
  const [activeQuote, setActiveQuote] = useState<{ text: string, pageNumber: number } | null>(null)

  const [isDeleting, setIsDeleting] = useState(false)
  const [isDocConfirmOpen, setIsDocConfirmOpen] = useState(false)
  const documentTrashIdempotencyKey = useRef<string | null>(null)
  const [isReassignOpen, setIsReassignOpen] = useState(false)
  const [isReprocessing, setIsReprocessing] = useState(false)
  const reprocessIdempotencyKey = useRef<string | null>(null)
  const [pendingNoteDeleteId, setPendingNoteDeleteId] = useState<string | null>(null)
  const router = useRouter()

  const handleDeleteDocument = async () => {
    if (readOnly) return
    if (!documentTrashIdempotencyKey.current) {
      documentTrashIdempotencyKey.current = `trash.document.${crypto.randomUUID()}`
    }
    setIsDeleting(true)
    const res = await deleteDocument(doc.id, documentTrashIdempotencyKey.current)
    setIsDeleting(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      documentTrashIdempotencyKey.current = null
      setIsDocConfirmOpen(false)
      toast.success('Document deleted successfully')
      onClose?.()
    }
  }

  const handleSearchIndexReprocess = async () => {
    if (readOnly) return
    if (!reprocessIdempotencyKey.current) reprocessIdempotencyKey.current = crypto.randomUUID()
    setIsReprocessing(true)
    const result = await reprocessDocument(doc.id, 'search_index', reprocessIdempotencyKey.current)
    setIsReprocessing(false)
    if (result.error) toast.error(result.error)
    else toast.success(result.status === 'queued' ? 'Search-index reprocessing queued.' : 'Search-index reprocessing is already queued.')
  }

  useEffect(() => {
    reprocessIdempotencyKey.current = null
    documentTrashIdempotencyKey.current = null
  }, [doc.id])

  useEffect(() => {
    if (readOnly) return
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
  }, [readOnly]);

  const docNotes = notes.filter(n => n.document_id === doc.id)

  const handleAddNote = () => {
    if (readOnly) return
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
    if (readOnly) return
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
    if (readOnly) return
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

  const inspectorMetadata: DocumentInspectorMetadata = effectiveMetadata ?? {
    state: 'unavailable' as const,
    docType: null,
    referenceNumber: null,
    documentDate: null,
    clientName: null,
    gstin: null,
    financialYears: [],
    tax: null,
    interest: null,
    penalty: null,
    totalDemand: null,
    issuedBy: null,
    direction: null,
    documentVersionId: null,
    fieldCandidates: {},
  }
  const correction = (fieldPath: keyof typeof inspectorMetadata.fieldCandidates) => {
    if (readOnly) return undefined
    const candidate = inspectorMetadata.fieldCandidates[fieldPath]
    if (!candidate || !inspectorMetadata.documentVersionId) return undefined
    return {
      onSave: async (value: string) => {
        const result = await correctInspectorField({
          documentId: doc.id,
          documentVersionId: inspectorMetadata.documentVersionId!,
          candidateId: candidate.id,
          fieldPath: fieldPath as EditableFieldPath,
          value,
          idempotencyKey: `inspector:${crypto.randomUUID()}`,
        })
        if (result.error) toast.error(result.error)
        else {
          toast.success('Correction recorded.')
          router.refresh()
        }
      },
    }
  }
  const financialYearCorrection = correction('document.financial_year')
  const financialYearValue = inspectorMetadata.financialYears.join(', ') || null
  const financialYearNeedsReview = inspectorMetadata.financialYears.length > 1
    || (inspectorMetadata.financialYears.length === 1 && !financialYearCorrection)
  const viewUrl = `/matters/${doc.matter_id}/documents/${doc.id}`
  const headerDocType = inspectorMetadata.state === 'available' ? inspectorMetadata.docType : null
  const headerDocDate = inspectorMetadata.state === 'available' ? inspectorMetadata.documentDate : null
  const documentLabel = selectedDocumentIdentity(doc, inspectorMetadata)

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
            <h3 className="text-sm font-semibold text-[--text-primary] truncate mb-0.5" title={documentLabel}>
              {documentLabel}
            </h3>
            <div className="flex items-center flex-wrap gap-1.5">
              {headerDocType && <Badge variant="muted" className="text-[9px] uppercase h-4 px-1 py-0">{headerDocType}</Badge>}
              <span className="text-[10px] text-[--text-muted] flex items-center gap-1 shrink-0">
                <Calendar size={10} />
                {headerDocDate ? new Date(`${headerDocDate}T00:00:00`).toLocaleDateString() : 'Unavailable'}
              </span>
            </div>
          </div>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-1.5 shrink-0">
          {!readOnly && <Button type="button" variant="outline" size="sm" onClick={() => setIsReassignOpen(true)}>
            <MoveRight size={14} aria-hidden="true" />
            Reassign
          </Button>}
          {!readOnly && <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleSearchIndexReprocess}
            disabled={isReprocessing}
            loading={isReprocessing}
            aria-describedby="scoped-reprocess-status"
          >
            <RefreshCw size={14} aria-hidden="true" />
            Reprocess search index
          </Button>}
          {!readOnly && <Button
            type="button"
            variant="destructive"
            size="sm"
            onClick={() => setIsDocConfirmOpen(true)}
            disabled={isDeleting}
            loading={isDeleting}
          >
            <Trash2 size={14} aria-hidden="true" />
            Delete document
          </Button>}
          <a href={viewUrl} className="inline-flex min-h-11 items-center justify-center gap-1 rounded-[var(--radius-sm)] bg-[var(--primary)] px-3 text-[11px] font-medium text-[var(--on-accent)] shadow-sm transition-colors hover:bg-[var(--primary-hover)]">
            <ExternalLink size={12} />
            View
          </a>
          {onClose && (
            <Button variant="ghost" size="icon" className="text-[--text-muted] hover:text-[--text-primary] ml-0.5" onClick={onClose} aria-label="Close document details">
              <X size={14} aria-hidden="true" />
            </Button>
          )}
        </div>
      </div>
      {!readOnly && <p id="scoped-reprocess-status" className="px-3 py-2 text-xs text-[var(--text-secondary)]">
        Search-index reprocessing is available. Extraction, OCR, relationship, and full reprocessing remain unavailable until their dedicated workers are deployed.
      </p>}

      {/* Tabs Selector */}
      <div className="flex border-b border-[var(--border)] bg-[var(--surface-hover)] px-3 shrink-0">
        <button
          onClick={() => setActiveTab('details')}
          className={`flex items-center gap-1.5 py-2 px-2 text-[11px] font-semibold border-b-2 transition-colors -mb-px ${
            activeTab === 'details'
              ? 'border-[var(--primary)] text-[var(--primary)]'
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
              ? 'border-[var(--primary)] text-[var(--primary)]'
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
                <span className="text-xs font-semibold text-[var(--text-muted)] group-hover:text-[var(--text-primary)]">{isSynopsisOpen ? 'Collapse' : 'Expand'}</span>
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
            {inspectorMetadata.state === 'unavailable' && <p className="text-sm text-[var(--text-muted)]">Current extracted metadata is unavailable for this document version.</p>}
            <div className="grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
              <EffectiveMetadataField label="Client Name" value={inspectorMetadata.clientName} correction={correction('document.client_name')} />
              <EffectiveMetadataField label="GSTIN" value={inspectorMetadata.gstin} correction={correction('document.gstin')} />
              <EffectiveMetadataField label="Reference Number" value={inspectorMetadata.referenceNumber} correction={correction('document.reference_number')} />
              <EffectiveMetadataField label="Document Type" value={inspectorMetadata.docType} correction={correction('document.type')} />
              <EffectiveMetadataField label="Document Date" value={inspectorMetadata.documentDate} type="date" correction={correction('document.date')} />
              <div>
                <EffectiveMetadataField label="Financial Year" value={financialYearValue} correction={financialYearCorrection} />
                {financialYearNeedsReview && (
                  <p className="px-2 text-xs text-[var(--text-muted)]">Review required — multiple or ambiguous current financial-year candidates cannot be corrected here.</p>
                )}
              </div>
              <DeferredMetadataField label="Tax Period" message="Unavailable — tax-period candidates are not yet in the effective-metadata contract." />
            </div>
          </div>

          {/* Financials Extracted Metadata Grid */}
          <div className="flex flex-col gap-3 mt-2">
            <h4 className="text-sm font-semibold text-[--text-primary] border-b border-[--border-subtle] pb-1.5 px-1">
              Extracted Amounts
            </h4>
            <div className="grid grid-cols-1 gap-x-4 gap-y-2 sm:grid-cols-2">
              <EffectiveMetadataField label="Tax" value={inspectorMetadata.tax} type="decimal" correction={correction('financial.tax')} />
              <EffectiveMetadataField label="Interest" value={inspectorMetadata.interest} type="decimal" correction={correction('financial.interest')} />
              <EffectiveMetadataField label="Penalty" value={inspectorMetadata.penalty} type="decimal" correction={correction('financial.penalty')} />
              <EffectiveMetadataField label="Total Demand" value={inspectorMetadata.totalDemand} type="decimal" correction={correction('financial.total_demand')} />
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
                  const linkedMetadata = inspectorMetadataByDocumentId?.[ldoc.id]
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
                        <span className="text-sm font-medium text-[--text-primary] truncate">{linkedDocumentIdentity(ldoc, linkedMetadata)}</span>
                        <div className="flex items-center gap-2 flex-wrap">
                          <Badge variant="muted" className={`text-[9px] uppercase tracking-wider py-0 px-1 font-semibold ${isCurrentDocChild ? 'text-[var(--primary)] border-[var(--primary)]/30' : 'text-[var(--success)] border-[color-mix(in_srgb,var(--success)_30%,transparent)]'}`}>
                            {relationLabel}
                          </Badge>
                          <Badge variant="outline" className="text-[9px] uppercase tracking-wider py-0 px-1 text-[var(--text-muted)]">
                            {roleLabel}
                          </Badge>
                          {ldoc.document_class === 'supporting' && (
                            <Badge variant="outline" className="text-[9px] uppercase tracking-wider py-0 px-1 bg-[var(--surface-hover)] text-[var(--text-secondary)] border-transparent">Supporting</Badge>
                          )}
                          <span className="text-xs text-[--text-muted]">{linkedDocumentDate(ldoc, linkedMetadata)}</span>
                        </div>
                      </div>
                      <a 
                        href={`/matters/${ldoc.matter_id}/documents/${ldoc.id}`}
                        target="_blank"
                        rel="noreferrer"
                        className="p-2 text-[var(--primary)] hover:bg-[var(--primary)]/10 rounded-[var(--radius-sm)] transition-colors"
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
                <span className="text-[10px] font-semibold text-[--text-muted] uppercase tracking-wider">File label</span>
                <span className="break-words rounded border border-[var(--border)] bg-[var(--bg)] p-1.5 text-xs text-[var(--text-secondary)]">{doc.display_title || doc.effective_filename || 'Untitled document'}</span>
              </div>
            </div>
          </div>

          </div>
        ) : (
          <div className="flex flex-col gap-5 h-full">
            {/* Quick Add Note Form */}
            {!readOnly && <div className="flex flex-col gap-2 p-3 bg-[var(--bg)] border border-[var(--border)] rounded-lg shadow-sm">
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
                <div className="flex flex-col gap-1.5 p-2.5 bg-[var(--warning-muted)] border-l-2 border-[var(--warning)] rounded-r-[var(--radius-md)] text-xs text-[var(--text-secondary)] relative group mt-1 shadow-sm">
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-bold text-[var(--warning)] text-[10px] uppercase tracking-wide flex items-center gap-1.5">
                      <FileText size={10} /> Selected from Page {activeQuote.pageNumber}
                    </span>
                    <button 
                      onClick={() => setActiveQuote(null)}
                      className="text-[var(--warning)] hover:text-[color-mix(in_srgb,var(--warning)_70%,black)] opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded hover:bg-[var(--warning-muted)]"
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
            </div>}

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
                      {!readOnly && <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                        <button
                          onClick={() => handleTogglePin(note)}
                          className={`p-1 rounded-[var(--radius-sm)] text-[var(--text-muted)] hover:text-[var(--warning)] hover:bg-[var(--warning-muted)]`}
                          title="Pin Note"
                        >
                          <Pin size={11} className={note.is_pinned ? 'fill-current text-[var(--warning)]' : ''} />
                        </button>
                        <button
                          onClick={() => setPendingNoteDeleteId(note.id)}
                          className="p-1 rounded-[var(--radius-sm)] text-[var(--text-muted)] hover:text-[var(--danger)] hover:bg-[var(--danger-muted)]"
                          title="Delete Note"
                        >
                          <Trash2 size={11} />
                        </button>
                      </div>}
                    </div>
                    {note.quote && (
                      <div 
                        onClick={() => {
                          window.dispatchEvent(new CustomEvent('JUMP_TO_PDF_PAGE', { detail: { pageNumber: note.page_number } }))
                        }}
                        className="mb-3 p-2 bg-[var(--bg)] border-l-2 border-[var(--primary)] rounded-r-[var(--radius-md)] text-xs text-[var(--text-secondary)] italic cursor-pointer hover:bg-[var(--surface-hover)] transition-colors shadow-sm"
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

      {!readOnly && <ConfirmDialog
        isOpen={isDocConfirmOpen}
        onClose={() => {
          documentTrashIdempotencyKey.current = null
          setIsDocConfirmOpen(false)
        }}
        onConfirm={handleDeleteDocument}
        title="Delete Document?"
        description="Are you sure you want to delete this document? This will permanently remove it from the matter timeline."
        confirmText="Delete Document"
        variant="destructive"
        isPending={isDeleting}
      />}

      {!readOnly && <ConfirmDialog
        isOpen={!!pendingNoteDeleteId}
        onClose={() => setPendingNoteDeleteId(null)}
        onConfirm={handleDeleteNote}
        title="Delete Note?"
        description="Are you sure you want to delete this note? This action cannot be undone."
        confirmText="Delete Note"
        variant="destructive"
      />}

      {!readOnly && <ReassignDocumentDialog
        isOpen={isReassignOpen}
        onClose={() => {
          setIsReassignOpen(false)
        }}
        documentId={doc.id}
        currentMatterId={doc.matter_id}
      />}
    </div>
  )
}
