'use client'

import { useState, useTransition, useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import {
  FileText, AlertCircle, X, Check, Loader2, Plus, ExternalLink,
  Info, RotateCcw, ChevronDown, ChevronUp, Sparkles, Search,
  FolderOpen, Zap, ArrowRight, Trash2, RefreshCw, Bot, Building2,
  FolderPlus, Copy, AlertTriangle
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { createClient } from '@/lib/supabase/client'
import {
  assignStagedDocument, discardStagedDocument,
  autoCreateClientAndMatterForStagedDocument,
  getStagedDocuments, reevaluateStagedDocuments
} from '@/lib/actions/inbox'
import { getDocumentSignedUrl } from '@/lib/actions/document'
import { reprocessDocument } from '@/lib/actions/reprocess'
import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'
import { UploadModal } from './UploadModal'
import { DocumentViewerModal } from './DocumentViewerModal'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'

function humanizeKey(key: string) {
  return key
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .split(' ')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}

function StatusBadge({ doc }: { doc: any }) {
  const isAnalyzing = doc.status === 'analyzing'
  const isPending = doc.status === 'pending_assignment'
  const hasSuggestion = doc.suggested_client && doc.suggested_matter

  if (isAnalyzing) return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold animated-gradient-badge shrink-0">
      <Bot size={9} className="animate-pulse" /> AI
    </span>
  )
  if (isPending) return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-500/10 text-slate-400 border border-slate-500/20 shrink-0">
      Queued
    </span>
  )
  if (doc.status === 'failed') return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-red-500/15 text-red-400 border border-red-500/25 shrink-0">
      <AlertCircle size={9} /> Failed
    </span>
  )
  if (doc.suggestion_reason?.startsWith('DUPLICATE:')) return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/15 text-amber-400 border border-amber-500/25 shrink-0">
      <Copy size={9} /> Duplicate
    </span>
  )
  if (hasSuggestion) return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/15 text-emerald-400 border border-emerald-500/25 shrink-0">
      <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" />
      Ready
    </span>
  )
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-violet-500/15 text-violet-400 border border-violet-500/25 shrink-0">
      <AlertCircle size={9} /> Review
    </span>
  )
}

// Searchable combobox for matters in the action modal
function MatterSearchBox({
  matters,
  selectedMatterId,
  onSelect
}: {
  matters: any[]
  selectedMatterId: string
  onSelect: (id: string) => void
}) {
  const [search, setSearch] = useState('')
  const [isOpen, setIsOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)

  const selectedMatter = matters.find(m => m.id === selectedMatterId)

  const filtered = matters.filter(m => {
    const q = search.toLowerCase()
    return (
      m.title?.toLowerCase().includes(q) ||
      m.matter_code?.toLowerCase().includes(q) ||
      m.clients?.name?.toLowerCase().includes(q)
    )
  })

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  return (
    <div ref={containerRef} className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={`w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-xl border text-sm transition-all ${
          isOpen
            ? 'border-[var(--primary)] ring-2 ring-[var(--primary)]/20 bg-[var(--surface)]'
            : 'border-[var(--border-strong)] bg-[var(--surface)] hover:border-[var(--primary)]/50'
        }`}
      >
        <span className={`truncate ${selectedMatter ? 'text-[var(--text-primary)]' : 'text-[var(--text-muted)]'}`}>
          {selectedMatter
            ? `${selectedMatter.clients?.name} · ${selectedMatter.title}`
            : 'Choose a matter...'}
        </span>
        <ChevronDown size={14} className={`shrink-0 text-[var(--text-muted)] transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && (
        <div className="absolute z-50 top-full mt-1 w-full bg-[var(--surface)] border border-[var(--border)] rounded-xl shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2 duration-150">
          <div className="p-2 border-b border-[var(--border)]">
            <div className="relative">
              <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--text-muted)]" />
              <input
                autoFocus
                value={search}
                onChange={e => setSearch(e.target.value)}
                placeholder="Search by client, matter or code..."
                className="w-full pl-8 pr-3 py-1.5 text-[13px] bg-[var(--surface-hover)] border border-[var(--border)] rounded-lg focus:outline-none focus:border-[var(--primary)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)]"
              />
            </div>
          </div>
          <div className="max-h-52 overflow-y-auto custom-scrollbar">
            {filtered.length === 0 ? (
              <div className="p-4 text-[12px] text-[var(--text-muted)] text-center">No matters found</div>
            ) : (
              filtered.map(m => (
                <button
                  key={m.id}
                  type="button"
                  onClick={() => { onSelect(m.id); setIsOpen(false); setSearch('') }}
                  className={`w-full text-left flex items-center justify-between px-3 py-2.5 transition-colors border-l-2 ${
                    m.id === selectedMatterId
                      ? 'bg-[var(--primary)]/10 border-[var(--primary)] text-[var(--primary)]'
                      : 'border-transparent hover:bg-[var(--surface-hover)] text-[var(--text-primary)]'
                  }`}
                >
                  <div className="flex flex-col min-w-0">
                    <span className="text-[13px] font-medium truncate">{m.title}</span>
                    <span className="text-[11px] text-[var(--text-muted)]">
                      {m.clients?.name} · {m.matter_code} · {m.financial_year || 'No FY'}
                    </span>
                  </div>
                  {m.id === selectedMatterId && <Check size={13} className="shrink-0 ml-2" />}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  )
}

export function InboxClientView({
  initialDocuments,
  matters,
  preselectedMatterId
}: {
  initialDocuments: any[]
  matters: any[]
  preselectedMatterId?: string
}) {
  const [documents, setDocuments] = useState(initialDocuments)
  const [selectedDocId, setSelectedDocId] = useState<string | null>(
    initialDocuments.length > 0 ? initialDocuments[0].id : null
  )
  const [selectedMatterId, setSelectedMatterId] = useState<string>(preselectedMatterId || '')
  const [isPending, startTransition] = useTransition()
  const [isReprocessing, setIsReprocessing] = useState<string | null>(null)
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [isActionModalOpen, setIsActionModalOpen] = useState(false)
  const [isDiscardConfirmOpen, setIsDiscardConfirmOpen] = useState(false)
  const [isSynopsisExpanded, setIsSynopsisExpanded] = useState(false)
  const [viewDocumentUrl, setViewDocumentUrl] = useState<string | null>(null)
  const router = useRouter()
  const { setBreadcrumbs } = useBreadcrumbs()

  useEffect(() => { reevaluateStagedDocuments() }, [])

  useEffect(() => { setDocuments(initialDocuments) }, [initialDocuments])

  const preselectedMatter = matters.find(m => m.id === preselectedMatterId)

  useEffect(() => {
    if (preselectedMatter) {
      setBreadcrumbs([
        { label: 'Matters', href: '/matters' },
        { label: preselectedMatter.title, href: `/matters/${preselectedMatter.id}` },
        { label: 'Upload' }
      ])
    } else {
      setBreadcrumbs([{ label: 'Document Hub' }])
    }
  }, [setBreadcrumbs, preselectedMatter])

  const activeDoc = documents.find(d => d.id === selectedDocId)

  useEffect(() => {
    if (preselectedMatterId) { setSelectedMatterId(preselectedMatterId); return }
    if (activeDoc?.suggested_matter?.id) {
      setSelectedMatterId(activeDoc.suggested_matter.id)
    } else {
      setSelectedMatterId('')
    }
  }, [activeDoc, preselectedMatterId])

  const discardedDocIds = useRef<Set<string>>(new Set())

  useEffect(() => {
    const supabase = createClient()
    const channel = supabase.channel('staged_docs_changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'staged_documents' }, async (payload) => {
        const latestDocs = await getStagedDocuments()
        if (payload.eventType === 'UPDATE' && payload.new.status === 'auto_assigned') {
          const updatedId = payload.new.id
          if (!discardedDocIds.current.has(updatedId)) {
            const oldDoc = documents.find(d => d.id === updatedId)
            if (oldDoc) {
              toast.success(`Automated Processing Complete`, {
                description: `${oldDoc.storage_path.split('/').pop()} was successfully assigned.`,
              })
            }
          }
        }
        setDocuments(latestDocs)
        if (selectedDocId) {
          const stillExists = latestDocs.some((d: any) => d.id === selectedDocId)
          if (!stillExists && latestDocs.length > 0) setSelectedDocId(latestDocs[0].id)
          else if (!stillExists) setSelectedDocId(null)
        }
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [selectedDocId, documents])

  const handleSelectDoc = (doc: any) => {
    setSelectedDocId(doc.id)
    if (preselectedMatterId) setSelectedMatterId(preselectedMatterId)
    else if (doc.suggested_matter?.id) setSelectedMatterId(doc.suggested_matter.id)
    else setSelectedMatterId('')
  }

  function handleAssign() {
    if (!selectedDocId || !selectedMatterId) return
    startTransition(async () => {
      const res = await assignStagedDocument(selectedDocId, selectedMatterId)
      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Document assigned successfully')
        setIsActionModalOpen(false)
        await reevaluateStagedDocuments()
        const latestDocs = await getStagedDocuments()
        setDocuments(latestDocs)
        router.refresh()
      }
    })
  }

  function handleAutoCreate() {
    if (!selectedDocId) return
    startTransition(async () => {
      const res = await autoCreateClientAndMatterForStagedDocument(selectedDocId)
      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Matter and client automatically created')
        setIsActionModalOpen(false)
        await reevaluateStagedDocuments()
        const latestDocs = await getStagedDocuments()
        setDocuments(latestDocs)
        router.refresh()
      }
    })
  }

  function handleDiscard() {
    if (!selectedDocId) return
    discardedDocIds.current.add(selectedDocId)
    startTransition(async () => {
      const res = await discardStagedDocument(selectedDocId)
      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Document discarded')
        setIsDiscardConfirmOpen(false)
        setIsActionModalOpen(false)
        const remainingDocs = documents.filter(d => d.id !== selectedDocId)
        if (remainingDocs.length > 0) handleSelectDoc(remainingDocs[0])
        else setSelectedDocId(null)
        router.refresh()
      }
    })
  }

  async function handleViewDocument() {
    if (!activeDoc) return
    const res = await getDocumentSignedUrl('staging', activeDoc.storage_path)
    if (res.error || !res.url) {
      toast.error(res.error || 'Failed to generate signed url')
    } else {
      setViewDocumentUrl(res.url)
    }
  }

  const handleReprocess = async (docId: string) => {
    setIsReprocessing(docId)
    toast.info('Triggering AI reprocessing for this document...')
    const res = await reprocessDocument(docId, true)
    setIsReprocessing(null)
    if (res.error) toast.error(res.error)
    else toast.success('Reprocessing triggered. AI engine is working in the background...')
  }

  const hasExtractedMetadata = activeDoc && activeDoc.raw_metadata && Object.keys(activeDoc.raw_metadata).length > 0 && (
    activeDoc.raw_metadata.client_name ||
    activeDoc.raw_metadata.gstin ||
    activeDoc.raw_metadata.reference_number ||
    activeDoc.raw_metadata.doc_type ||
    activeDoc.raw_metadata.financial_year ||
    activeDoc.raw_metadata.tax_period
  )

  const isDuplicate = activeDoc?.suggestion_reason?.startsWith('DUPLICATE:')
  const hasSuggestion = activeDoc?.suggested_client && activeDoc?.suggested_matter

  return (
    <div className="flex flex-col flex-1 overflow-hidden animate-fade-in">
      {/* ── Body ─────────────────────────────────── */}
      <div className="flex flex-1 gap-0 overflow-hidden pt-2">

        {/* ── Left Queue Panel ──────────────────── */}
        <div className="w-[38%] flex flex-col gap-2.5 overflow-y-auto pl-1 pr-3 py-1 custom-scrollbar shrink-0">
          {/* Action buttons at top of LHS */}
          <div className="flex items-center gap-2">
            <button
              onClick={async () => {
                const toastId = toast.loading('Re-evaluating queue...')
                try {
                  await reevaluateStagedDocuments()
                  const latestDocs = await getStagedDocuments()
                  setDocuments(latestDocs)
                  router.refresh()
                  toast.success('Queue refreshed', { id: toastId })
                } catch (err: any) {
                  toast.error(err.message || 'Failed to refresh', { id: toastId })
                }
              }}
              className="flex-1 flex items-center justify-center gap-1.5 h-8 px-3 text-[13px] font-medium rounded-lg border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] transition-colors"
            >
              <RefreshCw size={13} />
              Refresh
            </button>
            <button
              onClick={() => setIsUploadModalOpen(true)}
              className="flex-1 flex items-center justify-center gap-1.5 h-8 px-3 text-[13px] font-semibold rounded-lg bg-[var(--primary)] text-white hover:opacity-90 transition-opacity shadow-sm"
            >
              <Plus size={14} />
              Add Document
            </button>
          </div>

          {documents.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full p-12 rounded-2xl border border-dashed border-[var(--border)] text-center">
              <div className="w-14 h-14 rounded-2xl bg-[var(--primary)]/10 flex items-center justify-center mb-4">
                <FolderOpen size={24} className="text-[var(--primary)]" />
              </div>
              <h3 className="text-[15px] font-semibold text-[var(--text-primary)]">Queue is empty</h3>
              <p className="text-[13px] text-[var(--text-muted)] mt-1.5 max-w-xs leading-relaxed">
                Upload files using the 'Add Document' button to stage them for AI analysis.
              </p>
            </div>
          ) : (
            <>
              <div className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-widest px-0.5">
                Queue · {documents.length} document{documents.length !== 1 ? 's' : ''}
              </div>
              {documents.map((doc) => {
                const fileName = doc.storage_path.split('/').pop()
                const isSelected = doc.id === selectedDocId
                const isAnalyzing = doc.status === 'analyzing'
                const isDup = doc.suggestion_reason?.startsWith('DUPLICATE:')
                const isFailed = doc.status === 'failed'
                const isReady = doc.suggested_client && doc.suggested_matter

                return (
                  <div
                    key={doc.id}
                    onClick={() => handleSelectDoc(doc)}
                    className={cn(
                      'group relative cursor-pointer rounded-xl overflow-hidden transition-colors border duration-150',
                      isSelected
                        ? 'border-[var(--primary)] bg-[var(--surface)] shadow-[0_2px_12px_rgba(59,130,246,0.12)]'
                        : 'border-[var(--border)] bg-[var(--surface)] hover:border-[var(--primary)]/40 hover:bg-[var(--surface-hover)]',
                      isAnalyzing && 'animated-gradient-border'
                    )}
                  >
                    {/* selected left glow bar */}
                    <div className={cn(
                      "absolute left-0 top-0 bottom-0 w-1 bg-gradient-to-b from-[var(--primary)] to-purple-500 rounded-l-xl transition-opacity duration-150",
                      isSelected ? "opacity-100" : "opacity-0"
                    )} />

                    <div className="p-3 pl-4 flex items-center gap-3 bg-[var(--surface)]">
                      {/* File Icon */}
                      <div className={`shrink-0 w-9 h-9 rounded-lg flex items-center justify-center transition-colors ${
                        isSelected ? 'bg-[var(--primary)]/10' : 'bg-[var(--surface-hover)]'
                      }`}>
                        <FileText size={16} className={isSelected ? 'text-[var(--primary)]' : 'text-[var(--text-muted)]'} />
                      </div>

                      {/* Info */}
                      <div className="flex-1 min-w-0 flex flex-col gap-0.5">
                        <div className="flex items-center justify-between gap-1">
                          <span className="text-[12px] font-semibold text-[var(--text-primary)] truncate leading-tight">
                            {fileName}
                          </span>
                          <StatusBadge doc={doc} />
                        </div>
                        <span className="text-[11px] text-[var(--text-muted)]">
                          {new Date(doc.created_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}
                          {doc.raw_metadata?.doc_type && (
                            <> · <span className="font-mono">{doc.raw_metadata.doc_type}</span></>
                          )}
                        </span>
                      </div>

                      <ArrowRight size={12} className={`shrink-0 transition-all duration-200 ${
                        isSelected ? 'text-[var(--primary)] translate-x-0' : 'text-[var(--text-disabled)] -translate-x-0.5 group-hover:translate-x-0 group-hover:text-[var(--text-muted)]'
                      }`} />
                    </div>

                    {/* bottom hint strip for ready docs */}
                    {isReady && !isDup && !isFailed && (
                      <div className="px-4 pb-2 pt-0.5 flex items-center gap-1 bg-emerald-500/5 text-emerald-500 text-[10px] font-semibold">
                        <Zap size={9} /> AI matched · {doc.suggested_client?.name}
                      </div>
                    )}
                    {isDup && (
                      <div className="px-4 pb-2 pt-0.5 flex items-center gap-1 bg-amber-500/5 text-amber-500 text-[10px] font-semibold">
                        <Copy size={9} /> Duplicate detected
                      </div>
                    )}
                    {isFailed && (
                      <div className="px-4 pb-2 pt-0.5 flex items-center gap-1 bg-red-500/5 text-red-400 text-[10px] font-semibold">
                        <AlertCircle size={9} /> AI extraction failed · click to reprocess
                      </div>
                    )}
                  </div>
                )
              })}
            </>
          )}
        </div>

        {/* ── Vertical Divider ─── */}
        <div className="w-px bg-[var(--border)] shrink-0 mx-2" />

        {/* ── Right Detail Panel ─────────────────── */}
        <div className="flex-1 flex flex-col overflow-y-auto pl-4 custom-scrollbar">
          {activeDoc ? (
            <div className="flex flex-col gap-5">

              {/* Document title + action strip */}
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h2 className="text-[16px] font-bold text-[var(--text-primary)] leading-snug truncate max-w-[380px]">
                    {activeDoc.storage_path.split('/').pop()}
                  </h2>
                  <p className="text-[11px] text-[var(--text-muted)] uppercase tracking-widest font-semibold mt-0.5">
                    Staged Document · {activeDoc.status?.replace(/_/g, ' ')}
                  </p>
                </div>

                {/* Action Buttons row */}
                <div className="flex items-center gap-1.5 shrink-0">
                  <button
                    onClick={() => handleReprocess(activeDoc.id)}
                    disabled={isReprocessing === activeDoc.id}
                    title="Re-run AI extraction"
                    className="h-8 w-8 rounded-lg border border-[var(--border)] flex items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:border-[var(--border-strong)] transition-all disabled:opacity-50"
                  >
                    <RotateCcw size={13} className={isReprocessing === activeDoc.id ? 'animate-spin' : ''} />
                  </button>
                  <button
                    onClick={handleViewDocument}
                    title="View original PDF"
                    className="h-8 px-3 flex items-center gap-1.5 rounded-lg border border-[var(--border)] text-[12px] font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:border-[var(--border-strong)] transition-all"
                  >
                    <ExternalLink size={12} /> PDF
                  </button>
                  <button
                    onClick={() => setIsActionModalOpen(true)}
                    className="h-8 px-4 flex items-center gap-1.5 rounded-lg text-[13px] font-bold text-white transition-all shadow-lg hover:opacity-90 active:scale-95"
                    style={{ background: 'linear-gradient(135deg, #2563EB 0%, #7C3AED 100%)' }}
                  >
                    <Zap size={13} /> Take Action
                  </button>
                </div>
              </div>

              {/* ── State panels ── */}
              {activeDoc.status === 'analyzing' ? (
                <div className="flex flex-col items-center justify-center py-16 rounded-2xl border border-dashed border-[var(--primary)]/30 bg-[var(--primary)]/5 text-center">
                  <div className="relative mb-5">
                    <div className="w-14 h-14 rounded-2xl bg-[var(--primary)]/10 flex items-center justify-center">
                      <Bot size={24} className="text-[var(--primary)]" />
                    </div>
                    <Loader2 size={14} className="animate-spin text-[var(--primary)] absolute -bottom-1 -right-1" />
                  </div>
                  <h3 className="text-[15px] font-bold text-[var(--text-primary)]">AI Engine Running…</h3>
                  <p className="text-[13px] text-[var(--text-secondary)] mt-1.5 max-w-xs">
                    Extracting metadata, classifying document type and matching client records.
                  </p>
                </div>
              ) : activeDoc.status === 'failed' ? (
                <div className="rounded-2xl border border-red-500/20 bg-red-500/5 overflow-hidden">
                  <div className="flex items-center gap-3 p-4 border-b border-red-500/15">
                    <div className="w-9 h-9 rounded-xl bg-red-500/10 flex items-center justify-center shrink-0">
                      <AlertTriangle size={16} className="text-red-400" />
                    </div>
                    <div>
                      <div className="text-[14px] font-bold text-red-400">AI Extraction Failed</div>
                      <div className="text-[12px] text-red-400/70 mt-0.5">The document could not be processed automatically</div>
                    </div>
                  </div>
                  <div className="p-4 flex flex-col gap-3">
                    <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                      {activeDoc.suggestion_reason || 'An unknown error occurred during extraction.'}
                    </p>
                    <div className="flex gap-2">
                      <button
                        onClick={() => handleReprocess(activeDoc.id)}
                        disabled={isReprocessing === activeDoc.id}
                        className="flex items-center gap-1.5 h-8 px-3 text-[12px] font-semibold rounded-lg border border-[var(--border)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-all disabled:opacity-50"
                      >
                        <RotateCcw size={12} className={isReprocessing === activeDoc.id ? 'animate-spin' : ''} />
                        Retry AI
                      </button>
                      <button
                        onClick={() => setIsActionModalOpen(true)}
                        className="flex items-center gap-1.5 h-8 px-3 text-[12px] font-semibold rounded-lg bg-[var(--primary)]/10 text-[var(--primary)] hover:bg-[var(--primary)]/20 transition-all"
                      >
                        <FolderPlus size={12} />
                        Assign Manually
                      </button>
                    </div>
                  </div>
                </div>
              ) : !hasExtractedMetadata ? (
                <div className="flex flex-col items-center justify-center py-14 rounded-2xl border border-[var(--border)] bg-[var(--surface)] text-center">
                  <AlertCircle size={28} className="text-[var(--text-muted)] mb-3" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">No data could be extracted</h3>
                  <p className="text-[13px] text-[var(--text-muted)] mt-1 max-w-xs">AI could not identify key fields from this document. Assign it manually.</p>
                  <button
                    onClick={() => setIsActionModalOpen(true)}
                    className="mt-4 h-8 px-4 text-[13px] font-semibold rounded-lg border border-[var(--border)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] hover:border-[var(--border-strong)] transition-all"
                  >
                    Assign Manually
                  </button>
                </div>
              ) : (
                <div className="flex flex-col gap-4">

                  {/* Duplicate warning banner */}
                  {isDuplicate && (
                    <div className="flex items-start gap-3 p-4 rounded-2xl border border-amber-500/25 bg-amber-500/8">
                      <div className="w-8 h-8 rounded-xl bg-amber-500/15 flex items-center justify-center shrink-0 mt-0.5">
                        <Copy size={14} className="text-amber-400" />
                      </div>
                      <div>
                        <div className="text-[13px] font-bold text-amber-400 mb-1">Duplicate Document Detected</div>
                        <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                          {activeDoc.suggestion_reason?.replace('DUPLICATE: ', '')}
                        </p>
                      </div>
                    </div>
                  )}

                  {/* AI Match suggestion */}
                  {hasSuggestion && !isDuplicate && (
                    <div className="flex items-center justify-between gap-3 p-3.5 rounded-xl border border-emerald-500/20 bg-emerald-500/5">
                      <div className="flex items-center gap-2.5">
                        <div className="w-7 h-7 rounded-lg bg-emerald-500/15 flex items-center justify-center shrink-0">
                          <Zap size={12} className="text-emerald-400" />
                        </div>
                        <div>
                          <div className="text-[11px] font-bold text-emerald-500 uppercase tracking-wide">AI Recommended Match</div>
                          <div className="text-[13px] font-medium text-[var(--text-primary)] mt-0.5">
                            {activeDoc.suggested_client?.name} · {activeDoc.suggested_matter?.title}
                          </div>
                        </div>
                      </div>
                      <button
                        onClick={() => setIsActionModalOpen(true)}
                        className="shrink-0 h-7 px-3 text-[11px] font-bold rounded-lg bg-emerald-500 text-white hover:bg-emerald-600 transition-all"
                      >
                        Confirm
                      </button>
                    </div>
                  )}

                  {/* Metadata Card */}
                  <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] overflow-hidden shadow-sm">
                    {/* accent top line */}
                    <div className="h-0.5 bg-gradient-to-r from-blue-500 via-violet-500 to-purple-500" />

                    <div className="p-5 flex flex-col gap-5">
                      <div className="flex items-center gap-2">
                        <Bot size={15} className="text-[var(--primary)]" />
                        <span className="text-[13px] font-bold text-[var(--text-primary)]">AI-Extracted Metadata</span>
                        {activeDoc.raw_metadata?.confidence && (
                          <span className="ml-auto text-[10px] font-bold px-2 py-0.5 rounded-full bg-[var(--primary)]/10 text-[var(--primary)]">
                            {Math.round(activeDoc.raw_metadata.confidence * 100)}% confidence
                          </span>
                        )}
                      </div>

                      {/* Fields grid */}
                      <div className="grid grid-cols-2 gap-3">
                        {[
                          { label: 'Client Name', value: activeDoc.raw_metadata?.client_name },
                          { label: 'GSTIN / PAN', value: [activeDoc.raw_metadata?.gstin, activeDoc.raw_metadata?.pan].filter(Boolean).join(' / ') || null, mono: true },
                          { label: 'Document Type', value: activeDoc.raw_metadata?.doc_type },
                          { label: 'Ref / Case No.', value: activeDoc.raw_metadata?.reference_number, mono: true },
                          { label: 'Financial Year', value: activeDoc.raw_metadata?.financial_years?.join(', ') || activeDoc.raw_metadata?.financial_year },
                          { label: 'Tax Period', value: activeDoc.raw_metadata?.tax_period },
                        ].map(({ label, value, mono }) => (
                          <div key={label} className="flex flex-col gap-1 p-2.5 rounded-xl bg-[var(--surface-hover)]">
                            <span className="text-[10px] font-bold text-[var(--text-muted)] uppercase tracking-wider">{label}</span>
                            <span className={`text-[13px] font-semibold text-[var(--text-primary)] ${mono ? 'font-mono' : ''}`}>
                              {value || <span className="text-[var(--text-muted)] font-normal">—</span>}
                            </span>
                          </div>
                        ))}
                      </div>

                      {/* Synopsis */}
                      {activeDoc.raw_metadata?.summary && (
                        <div className="border-t border-[var(--border)] pt-4">
                          <button
                            type="button"
                            onClick={() => setIsSynopsisExpanded(!isSynopsisExpanded)}
                            className="w-full flex items-center justify-between gap-2 text-left group"
                          >
                            <div className="flex items-center gap-2">
                              <Sparkles size={13} className="text-violet-400 shrink-0" />
                              <span className="text-[12px] font-bold text-[var(--text-primary)]">AI Synopsis</span>
                              {!isSynopsisExpanded && (
                                <span className="text-[12px] text-[var(--text-muted)] truncate max-w-[220px]">
                                  — {activeDoc.raw_metadata.summary.slice(0, 80)}…
                                </span>
                              )}
                            </div>
                            <span className="text-[11px] font-bold text-[var(--primary)] shrink-0 flex items-center gap-0.5">
                              {isSynopsisExpanded ? (<>Hide <ChevronUp size={12} /></>) : (<>Expand <ChevronDown size={12} /></>)}
                            </span>
                          </button>
                          {isSynopsisExpanded && (
                            <div className="mt-3 text-[13px] text-[var(--text-secondary)] leading-relaxed bg-[var(--surface-hover)] p-4 rounded-xl border border-[var(--border)] animate-in fade-in duration-150">
                              {activeDoc.raw_metadata.summary}
                            </div>
                          )}
                        </div>
                      )}

                      {/* Financials */}
                      {activeDoc.raw_metadata?.extracted_amounts && Object.values(activeDoc.raw_metadata.extracted_amounts).some(v => v !== null) && (
                        <div className="border-t border-[var(--border)] pt-4">
                          <div className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-widest mb-3">Financials</div>
                          <div className="grid grid-cols-2 gap-2.5">
                            {Object.entries(activeDoc.raw_metadata.extracted_amounts).map(([key, val]) => {
                              if (val === null || val === undefined) return null
                              return (
                                <div key={key} className="flex flex-col p-3 rounded-xl bg-[var(--surface-hover)] border border-[var(--border)]">
                                  <span className="text-[11px] text-[var(--text-muted)] mb-1">{humanizeKey(key)}</span>
                                  <span className="text-[15px] font-bold font-mono text-[var(--text-primary)]">
                                    ₹{Number(val).toLocaleString('en-IN')}
                                  </span>
                                </div>
                              )
                            })}
                          </div>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="h-full flex flex-col items-center justify-center gap-3 text-[var(--text-muted)]">
              <div className="w-16 h-16 rounded-2xl bg-[var(--surface)] border border-[var(--border)] flex items-center justify-center">
                <FileText size={28} className="text-[var(--text-muted)]" />
              </div>
              <p className="text-[14px] font-medium">Select a document to inspect</p>
            </div>
          )}
        </div>
      </div>

      {/* ── Upload Modal ── */}
      {isUploadModalOpen && (
        <UploadModal onClose={() => setIsUploadModalOpen(false)} matterId={preselectedMatterId} />
      )}

      {/* ── Action Modal ── */}
      {isActionModalOpen && activeDoc && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="relative w-[92%] max-w-[460px] overflow-hidden flex flex-col rounded-2xl shadow-2xl border border-[var(--border)] animate-in zoom-in-95 duration-200"
            style={{ background: 'var(--surface)' }}
          >
            {/* gradient top bar */}
            <div className="h-1 w-full bg-gradient-to-r from-blue-500 via-violet-500 to-purple-600 shrink-0" />

            {/* Header */}
            <div className="flex items-start justify-between p-5 pb-3">
              <div className="flex items-start gap-3">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 mt-0.5"
                  style={{ background: 'linear-gradient(135deg, #2563EB20, #7C3AED20)' }}>
                  <Zap size={18} style={{ color: '#6366F1' }} />
                </div>
                <div>
                  <h2 className="text-[17px] font-bold text-[var(--text-primary)] leading-none">Assign Document</h2>
                  <p className="text-[13px] text-[var(--text-muted)] mt-1">Route this document to a matter timeline</p>
                </div>
              </div>
              <button
                onClick={() => setIsActionModalOpen(false)}
                className="p-1.5 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)] transition-colors"
              >
                <X size={16} />
              </button>
            </div>

            <div className="px-5 pb-5 flex flex-col gap-4">
              {/* Document name chip */}
              <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[var(--surface-hover)] border border-[var(--border)]">
                <FileText size={13} className="text-[var(--text-muted)] shrink-0" />
                <span className="text-[12px] font-medium text-[var(--text-secondary)] truncate">
                  {activeDoc.storage_path.split('/').pop()}
                </span>
              </div>

              {/* AI recommendation chip */}
              {hasSuggestion && !isDuplicate && (
                <div className="flex items-center gap-2.5 p-3 rounded-xl border border-emerald-500/20 bg-emerald-500/5">
                  <span className="h-2 w-2 rounded-full bg-emerald-400 animate-pulse shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="text-[10px] font-bold text-emerald-500 uppercase tracking-wide">AI Recommended</div>
                    <div className="text-[13px] font-semibold text-[var(--text-primary)] truncate">
                      {activeDoc.suggested_client?.name} · {activeDoc.suggested_matter?.title}
                    </div>
                  </div>
                  <Check size={14} className="text-emerald-400 shrink-0" />
                </div>
              )}

              {/* Searchable Matter Picker */}
              <div className="flex flex-col gap-1.5">
                <label className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-widest">
                  Select Matter
                </label>
                <MatterSearchBox
                  matters={matters}
                  selectedMatterId={selectedMatterId}
                  onSelect={setSelectedMatterId}
                />
              </div>

              {/* Action buttons */}
              <div className="flex flex-col gap-2 pt-2 border-t border-[var(--border)]">
                {/* Primary: Confirm Assignment */}
                <button
                  onClick={handleAssign}
                  disabled={!selectedMatterId || isPending}
                  className="w-full h-10 flex items-center justify-center gap-2 rounded-xl text-[14px] font-bold text-white transition-all disabled:opacity-50 disabled:cursor-not-allowed hover:opacity-90 active:scale-[0.98]"
                  style={{ background: 'linear-gradient(135deg, #2563EB 0%, #7C3AED 100%)' }}
                >
                  {isPending ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                  {isPending ? 'Assigning…' : 'Confirm Assignment'}
                </button>

                {/* Auto-create */}
                {activeDoc.status !== 'failed' && (!activeDoc.suggested_matter || matters.length === 0) && !preselectedMatterId && (
                  <button
                    onClick={handleAutoCreate}
                    disabled={isPending}
                    className="w-full h-10 flex items-center justify-center gap-2 rounded-xl text-[13px] font-semibold border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] transition-all disabled:opacity-50"
                  >
                    {isPending ? <Loader2 size={14} className="animate-spin" /> : <FolderPlus size={14} />}
                    Auto-Create Client & Matter
                  </button>
                )}

                {/* Discard */}
                <button
                  onClick={() => setIsDiscardConfirmOpen(true)}
                  disabled={isPending}
                  className="w-full h-9 flex items-center justify-center gap-2 rounded-xl text-[12px] font-semibold text-red-400 hover:bg-red-500/8 transition-all disabled:opacity-50"
                >
                  <Trash2 size={13} /> Discard Document
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        isOpen={isDiscardConfirmOpen}
        onClose={() => setIsDiscardConfirmOpen(false)}
        onConfirm={handleDiscard}
        title="Discard Document?"
        description="Are you sure you want to discard this document? It will be permanently deleted from the staging queue."
        confirmText="Discard Document"
        variant="destructive"
        isPending={isPending}
      />

      {viewDocumentUrl && activeDoc && (
        <DocumentViewerModal
          url={viewDocumentUrl}
          title={activeDoc.storage_path.split('/').pop()}
          onClose={() => setViewDocumentUrl(null)}
        />
      )}
    </div>
  )
}
