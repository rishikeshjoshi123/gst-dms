'use client'

import { useState, useTransition, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { FileText, AlertCircle, Building2, FolderOpen, X, Check, Loader2, Plus, ExternalLink, Calendar, DollarSign, Users, Info, ChevronRight, Settings2, RefreshCw, RotateCcw, ChevronDown, ChevronUp, Sparkles } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { createClient } from '@/lib/supabase/client'
import { assignStagedDocument, discardStagedDocument, autoCreateClientAndMatterForStagedDocument, getStagedDocuments, reevaluateStagedDocuments } from '@/lib/actions/inbox'
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

  useEffect(() => {
    reevaluateStagedDocuments()
  }, [])

  
  // Sync state when Server Component re-fetches data (e.g. after upload)
  useEffect(() => {
    setDocuments(initialDocuments)
  }, [initialDocuments])
  
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

  // Auto-fill suggested matter if available (and if no preselected)
  useEffect(() => {
    if (preselectedMatterId) {
      setSelectedMatterId(preselectedMatterId)
      return
    }
    if (activeDoc?.suggested_matter?.id) {
      setSelectedMatterId(activeDoc.suggested_matter.id)
    } else {
      setSelectedMatterId('')
    }
  }, [activeDoc, preselectedMatterId])

  // Keep track of intentionally discarded docs to prevent false positive success toasts
  const discardedDocIds = useRef<Set<string>>(new Set())

  useEffect(() => {
    // Only subscribe if there are running jobs, or we can just always subscribe to be safe.
    // Let's always subscribe so if a job starts, we get updates.
    const supabase = createClient()
    
    const channel = supabase.channel('staged_docs_changes')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'staged_documents'
        },
        async (payload) => {
          // Re-fetch latest documents to ensure we have full state (or we could mutate state manually)
          const latestDocs = await getStagedDocuments()
          
          if (payload.eventType === 'DELETE') {
            const deletedId = payload.old.id
            if (!discardedDocIds.current.has(deletedId)) {
              // It was deleted by the backend (assigned to a matter)
              // We don't have the storage_path in payload.old for sure unless replica identity is full,
              // but we can just show a generic success toast or find it in our current state.
              const oldDoc = documents.find(d => d.id === deletedId)
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
            if (!stillExists && latestDocs.length > 0) {
              setSelectedDocId(latestDocs[0].id)
            } else if (!stillExists) {
              setSelectedDocId(null)
            }
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [selectedDocId, documents])

  const handleSelectDoc = (doc: any) => {
    setSelectedDocId(doc.id)
    if (preselectedMatterId) {
      setSelectedMatterId(preselectedMatterId)
    } else if (doc.suggested_matter?.id) {
      setSelectedMatterId(doc.suggested_matter.id)
    } else {
      setSelectedMatterId('')
    }
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
    
    // Add to ignored list for polling
    discardedDocIds.current.add(selectedDocId)
    
    startTransition(async () => {
      const res = await discardStagedDocument(selectedDocId)
      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Document discarded')
        setIsDiscardConfirmOpen(false)
        setIsActionModalOpen(false)
        // Select next doc if available
        const remainingDocs = documents.filter(d => d.id !== selectedDocId)
        if (remainingDocs.length > 0) {
          handleSelectDoc(remainingDocs[0])
        } else {
          setSelectedDocId(null)
        }
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
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Reprocessing triggered. Processing with AI in the background...')
    }
  }

  const hasExtractedMetadata = activeDoc && activeDoc.raw_metadata && Object.keys(activeDoc.raw_metadata).length > 0 && (
    activeDoc.raw_metadata.client_name || 
    activeDoc.raw_metadata.gstin || 
    activeDoc.raw_metadata.reference_number ||
    activeDoc.raw_metadata.doc_type ||
    activeDoc.raw_metadata.financial_year ||
    activeDoc.raw_metadata.tax_period
  )

  return (
    <div className="flex flex-col flex-1 overflow-hidden gap-4 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between pb-4 border-b border-[var(--border)] shrink-0">
        <div>
          <h1 className="text-page-title text-[var(--text-primary)]">
            {preselectedMatter ? `Uploading to ${preselectedMatter.title}` : 'Document Hub'}
          </h1>
          <p className="text-body text-[var(--text-muted)] mt-0.5">
            {preselectedMatter && preselectedMatter.clients?.name
              ? `Client: ${preselectedMatter.clients.name} | FY: ${preselectedMatter.financial_year}`
              : 'Centralized processing and assignment queue'}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <Button onClick={async () => {
            const toastId = toast.loading('Re-evaluating client and matter matching for queue documents...')
            try {
              await reevaluateStagedDocuments()
              const latestDocs = await getStagedDocuments()
              setDocuments(latestDocs)
              router.refresh()
              toast.success('Queue refreshed. Matching recommendations updated.', { id: toastId })
            } catch (err: any) {
              toast.error(err.message || 'Failed to refresh queue', { id: toastId })
            }
          }} variant="outline" className="text-[var(--text-secondary)]">
            <RefreshCw size={16} className="mr-2" />
            Refresh
          </Button>
          <Button onClick={() => setIsUploadModalOpen(true)} variant="default">
            <Plus size={16} className="mr-2" />
            Add Document
          </Button>
        </div>
      </div>

      <div className="flex flex-1 gap-6 overflow-hidden pt-2">
        {/* Left Pane: Queue (40%) */}
        <div className="w-[40%] flex flex-col gap-2 overflow-y-auto p-1 pr-3 custom-scrollbar">
          {documents.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full p-12 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] text-center shadow-[var(--shadow-sm)]">
              <FolderOpen size={32} className="text-[var(--text-muted)] mb-3" />
              <h3 className="text-section-heading text-[var(--text-primary)]">Queue is empty</h3>
              <p className="text-caption text-[var(--text-muted)] mt-1 max-w-xs">
                Upload files using the 'Add Document' button to stage them for analysis.
              </p>
            </div>
          ) : (
            documents.map((doc, index) => {
              const fileName = doc.storage_path.split('/').pop()
              const isSelected = doc.id === selectedDocId
              const isAnalyzing = doc.status === 'analyzing'
              const isPending = doc.status === 'pending_assignment'
              const hasSuggestion = doc.suggested_client && doc.suggested_matter

              return (
                <div
                  key={doc.id}
                  onClick={() => {
                    setSelectedDocId(doc.id)
                    if (doc.suggested_matter?.id) {
                      setSelectedMatterId(doc.suggested_matter.id)
                    }
                  }}
                  className={`group rounded-lg transition-all duration-150 cursor-pointer relative ${
                    isSelected
                      ? 'border-2 border-[var(--primary)] bg-[var(--surface)] shadow-sm'
                      : 'border border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-hover)]'
                  } ${isAnalyzing ? 'animated-gradient-border' : ''}`}
                >
                  <div className="p-2.5 px-3 flex items-center justify-between gap-2 overflow-hidden">
                    <div className="flex items-center gap-2.5 min-w-0 flex-1">
                      <FileText size={15} className={`shrink-0 ${isSelected ? 'text-[var(--primary)]' : 'text-[var(--text-muted)]'}`} />
                      <div className="flex flex-col min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-2">
                          <h4 className="text-[13px] font-medium text-[var(--text-primary)] truncate">
                            {fileName}
                          </h4>
                          
                          {/* Status Badge */}
                          {isAnalyzing ? (
                            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold animated-gradient-badge shrink-0">
                              <Loader2 size={10} className="animate-spin" />
                              Engine
                            </span>
                          ) : isPending ? (
                            <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-[var(--border-subtle)] text-[var(--text-secondary)] shrink-0">
                              Queued
                            </span>
                          ) : doc.status === 'failed' ? (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-red-500/10 text-red-500 border border-red-500/20 shrink-0">
                              <AlertCircle size={10} />
                              Failed
                            </span>
                          ) : doc.suggestion_reason?.startsWith('DUPLICATE:') ? (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-amber-500/10 text-amber-500 border border-amber-500/20 shrink-0">
                              <AlertCircle size={10} />
                              Duplicate
                            </span>
                          ) : hasSuggestion ? (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-emerald-500/10 text-emerald-500 border border-emerald-500/20 shrink-0">
                              <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" />
                              Ready
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-semibold bg-[var(--border-subtle)] text-[var(--text-secondary)] border border-[var(--border)] shrink-0">
                              <AlertCircle size={10} />
                              Review
                            </span>
                          )}
                        </div>

                        <span className="text-[11px] text-[var(--text-muted)] truncate mt-0.5">
                          Uploaded {new Date(doc.created_at).toLocaleDateString()}
                        </span>
                      </div>
                    </div>

                    <ChevronRight size={14} className={`shrink-0 transition-transform duration-150 group-hover:translate-x-0.5 ${isSelected ? 'text-[var(--primary)]' : 'text-[var(--text-disabled)]'}`} />
                  </div>
                </div>
              )
            })
          )}
        </div>

        {/* Right Pane: Extracted Info & Action Panel (60%) */}
        <div className="w-[60%] flex flex-col overflow-y-auto pl-2 custom-scrollbar">
          {activeDoc ? (
            <div className="flex flex-col gap-6">
              {/* Document Header */}
              <div className="flex items-start justify-between">
                <div>
                  <h2 className="text-[18px] font-semibold text-[var(--text-primary)] truncate max-w-[350px]">
                    {activeDoc.storage_path.split('/').pop()}
                  </h2>
                  <span className="text-[12px] text-[var(--text-muted)] uppercase tracking-wide font-medium">
                    Staged Document Details
                  </span>
                </div>
                <div className="flex flex-wrap items-center gap-2 justify-end">
                  <Button variant="outline" size="sm" onClick={() => handleReprocess(activeDoc.id)} disabled={isReprocessing === activeDoc.id} className="h-8 text-xs shrink-0 text-[var(--text-secondary)]">
                    {isReprocessing === activeDoc.id ? <RotateCcw size={14} className="mr-1.5 animate-spin" /> : <RotateCcw size={14} className="mr-1.5" />}
                    Reprocess
                  </Button>
                  <Button onClick={handleViewDocument} variant="secondary" size="sm" className="h-8 text-xs shrink-0">
                    <ExternalLink size={14} className="mr-1.5" />
                    Original PDF
                  </Button>
                  <Button onClick={() => setIsActionModalOpen(true)} variant="default" size="sm" className="h-8 text-xs shrink-0 whitespace-nowrap">
                    <Check size={14} className="mr-1.5" />
                    Take Action
                  </Button>
                </div>
              </div>

              {/* Analysis Result */}
              {activeDoc.status === 'analyzing' ? (
                <div className="flex flex-col items-center justify-center p-12 rounded-md bg-[var(--surface)] border border-[var(--border)] shadow-sm text-center">
                  <Loader2 size={32} className="animate-spin mb-3 text-[var(--primary)]" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">Extracting Metadata...</h3>
                  <p className="text-[12px] text-[var(--text-secondary)] mt-1">System engine is analyzing the document context.</p>
                </div>
              ) : activeDoc.status === 'failed' ? (
                <div className="flex flex-col gap-3 p-5 rounded-md border border-red-500/20 bg-red-500/10">
                  <div className="flex items-center gap-2 text-[14px] font-semibold text-red-500">
                    <AlertCircle size={16} />
                    Analysis Failed
                  </div>
                  <p className="text-[14px] text-[var(--text-primary)] leading-relaxed">
                    {activeDoc.suggestion_reason || 'An unknown error occurred during extraction.'}
                  </p>
                  <p className="text-[12px] text-[var(--text-secondary)] font-medium">
                    You can still assign this document manually using the "Take Action" button.
                  </p>
                </div>
              ) : !hasExtractedMetadata ? (
                <div className="flex flex-col items-center justify-center p-12 rounded-md bg-[var(--surface)] border border-[var(--border)] shadow-sm text-center">
                  <AlertCircle size={32} className="text-[var(--text-muted)] mb-3" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">AI could not extract data from this document</h3>
                  <Button onClick={() => setIsActionModalOpen(true)} variant="secondary" className="mt-4">
                    Assign Manually
                  </Button>
                </div>
              ) : (
                /* Extracted Metadata Card */
                <div className="flex flex-col gap-4">
                  {activeDoc.suggestion_reason?.startsWith('DUPLICATE:') && (
                    <div className="flex flex-col gap-2 p-4 rounded-[var(--radius-md)] border border-amber-500/20 bg-amber-500/10 text-[14px] shadow-sm">
                      <div className="flex items-center gap-2 font-semibold text-amber-500">
                        <AlertCircle size={16} />
                        Duplicate Document Detected
                      </div>
                      <p className="text-[var(--text-primary)] leading-relaxed font-medium">
                        {activeDoc.suggestion_reason}
                      </p>
                    </div>
                  )}
                  
                  <div className="flex flex-col rounded-[var(--radius-lg)] border border-[var(--border)] bg-[var(--surface)] shadow-[var(--shadow-md)] overflow-hidden relative">
                    {/* Decorative Top Accent */}
                    <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-[var(--primary)] to-purple-500" />
                    
                    <div className="p-6 flex flex-col gap-6">
                      <div className="flex items-center gap-2 text-[15px] font-semibold text-[var(--text-primary)]">
                        <Info size={18} className="text-[var(--primary)]" />
                        AI-Extracted Metadata
                      </div>

                      <div className="grid grid-cols-2 gap-x-8 gap-y-5">
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Client Name</span>
                          <span className="text-[14px] font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.client_name || '-'}</span>
                        </div>
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">GSTIN / PAN</span>
                          <span className="text-[14px] font-mono font-medium text-[var(--text-primary)]">
                            {activeDoc.raw_metadata?.gstin || '-'} 
                            {activeDoc.raw_metadata?.pan && ` / ${activeDoc.raw_metadata.pan}`}
                          </span>
                        </div>
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Document Type</span>
                          <span className="text-[14px] font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.doc_type || '-'}</span>
                        </div>
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Ref / Case Number</span>
                          <span className="text-[14px] font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.reference_number || '-'}</span>
                        </div>
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Financial Year</span>
                          <span className="text-[14px] font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.financial_year || '-'}</span>
                        </div>
                        <div className="flex flex-col gap-1">
                          <span className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-wider">Tax Period</span>
                          <span className="text-[14px] font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.tax_period || '-'}</span>
                        </div>
                      </div>

                      {/* AI Synopsis (Collapsible) */}
                      {activeDoc.raw_metadata?.summary && (
                        <div className="pt-4 border-t border-[var(--border-subtle)]">
                          <button
                            type="button"
                            onClick={() => setIsSynopsisExpanded(!isSynopsisExpanded)}
                            className="w-full flex items-center justify-between text-left p-3 rounded-md bg-[var(--bg)] border border-[var(--border-subtle)] hover:border-[var(--border)] transition-colors group"
                          >
                            <div className="flex items-center gap-2 min-w-0">
                              <Sparkles size={14} className="text-[var(--primary)] shrink-0" />
                              <span className="text-[12px] font-bold text-[var(--text-primary)] uppercase tracking-wider">AI Synopsis</span>
                              {!isSynopsisExpanded && (
                                <span className="text-[12px] text-[var(--text-muted)] truncate max-w-[280px] font-normal ml-1">
                                  — {activeDoc.raw_metadata.summary}
                                </span>
                              )}
                            </div>
                            <div className="flex items-center gap-1 text-[11px] font-semibold text-[var(--primary)] shrink-0 ml-2">
                              {isSynopsisExpanded ? (
                                <>
                                  Hide <ChevronUp size={14} />
                                </>
                              ) : (
                                <>
                                  Expand <ChevronDown size={14} />
                                </>
                              )}
                            </div>
                          </button>

                          {isSynopsisExpanded && (
                            <div className="mt-2 text-[13px] text-[var(--text-secondary)] leading-relaxed bg-[var(--bg)] p-4 rounded-md border border-[var(--border-subtle)] animate-fade-in">
                              {activeDoc.raw_metadata.summary}
                            </div>
                          )}
                        </div>
                      )}

                      {/* Extracted Amounts */}
                      {activeDoc.raw_metadata?.extracted_amounts && Object.values(activeDoc.raw_metadata.extracted_amounts).some(v => v !== null) && (
                        <div className="pt-5 border-t border-[var(--border-subtle)]">
                          <h4 className="text-[12px] font-bold text-[var(--text-muted)] uppercase tracking-wider mb-3">Financials</h4>
                          <div className="grid grid-cols-2 gap-4">
                            {Object.entries(activeDoc.raw_metadata.extracted_amounts).map(([key, val]) => {
                              if (val === null || val === undefined) return null
                              return (
                                <div key={key} className="flex flex-col p-3 rounded-md bg-[var(--bg)] border border-[var(--border-subtle)]">
                                  <span className="text-[var(--text-secondary)] text-[12px] mb-1">{humanizeKey(key)}</span>
                                  <span className="text-[var(--text-primary)] font-mono font-semibold text-[15px]">
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
            <div className="h-full flex flex-col items-center justify-center text-[var(--text-muted)]">
              <FileText size={48} className="mb-4 text-slate-200" />
              <p className="text-[14px] font-medium">No document selected</p>
            </div>
          )}
        </div>
      </div>

      {isUploadModalOpen && (
        <UploadModal 
          onClose={() => setIsUploadModalOpen(false)} 
          matterId={preselectedMatterId}
        />
      )}

      {/* Action Modal */}
      {isActionModalOpen && activeDoc && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-surface rounded-lg shadow-xl border border-border w-[90%] max-w-md overflow-hidden flex flex-col animate-in zoom-in-95 duration-200">
            <div className="flex items-center justify-between p-4 border-b border-border bg-[var(--bg)]">
              <div>
                <h2 className="text-[18px] font-semibold text-[var(--text-primary)] leading-none">Assign Document</h2>
                <p className="text-[14px] text-[var(--text-muted)] mt-1">Route to a matter timeline.</p>
              </div>
              <button 
                onClick={() => setIsActionModalOpen(false)}
                className="p-1 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--border-subtle)] transition-colors"
              >
                <X size={20} />
              </button>
            </div>
            
            <div className="p-5 flex flex-col gap-5">
              {/* AI suggestion panel */}
              {activeDoc.suggested_client && activeDoc.suggested_matter && (
                <div className="p-4 bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800/50 rounded-md flex flex-col gap-2">
                  <span className="text-[12px] font-semibold text-emerald-700 dark:text-emerald-400 uppercase flex items-center gap-1.5">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" />
                    Recommended Match
                  </span>
                  <div className="text-[14px] text-emerald-900 dark:text-emerald-100 font-medium">
                    Client: {activeDoc.suggested_client.name}
                  </div>
                  <div className="text-[14px] text-emerald-800 dark:text-emerald-200">
                    Matter: {activeDoc.suggested_matter.title} ({activeDoc.suggested_matter.matter_code})
                  </div>
                </div>
              )}

              {/* Dropdown search manual assignment */}
              <div className="flex flex-col gap-2">
                <label className="text-[12px] font-semibold text-[var(--text-secondary)] uppercase tracking-wider">
                  Select Matter
                </label>
                <select 
                  className="w-full bg-[var(--bg)] border border-[var(--border-strong)] rounded-md px-3 py-2.5 text-[14px] text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent transition-shadow cursor-pointer"
                  value={selectedMatterId}
                  onChange={(e) => setSelectedMatterId(e.target.value)}
                >
                  <option value="">-- Choose an existing matter --</option>
                  {matters.map(m => (
                    <option key={m.id} value={m.id}>
                      {m.clients?.name} - {m.title} ({m.matter_code || 'no code'})
                    </option>
                  ))}
                </select>
              </div>

              {/* Dynamic Action Buttons */}
              {/* There should be exactly ONE primary button here: "Confirm Assignment". */}
              <div className="flex flex-col gap-3 border-t border-[var(--border-subtle)] pt-5 mt-1">
                <Button 
                  onClick={handleAssign} 
                  disabled={!selectedMatterId || isPending}
                  variant="default"
                  className="w-full"
                >
                  {isPending && <Loader2 size={16} className="animate-spin mr-2" />}
                  Confirm Assignment
                </Button>

                {activeDoc.status !== 'failed' && (!activeDoc.suggested_matter || matters.length === 0) && !preselectedMatterId && (
                  <Button 
                    onClick={handleAutoCreate}
                    variant="secondary"
                    disabled={isPending}
                    className="w-full"
                  >
                    {isPending ? <Loader2 size={16} className="animate-spin mr-2" /> : <Plus size={16} className="mr-2" />}
                    Auto-Create Client & Matter
                  </Button>
                )}

                <Button 
                  variant="destructive" 
                  className="w-full" 
                  onClick={() => setIsDiscardConfirmOpen(true)}
                  disabled={isPending}
                >
                  <X size={16} className="mr-2" />
                  Discard Document
                </Button>
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
