'use client'

import { useState, useTransition, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { FileText, AlertCircle, Building2, FolderOpen, X, Check, Loader2, Plus, ExternalLink, Calendar, DollarSign, Users, Info, ChevronRight, Settings2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { assignStagedDocument, discardStagedDocument, autoCreateClientAndMatterForStagedDocument, getStagedDocuments } from '@/lib/actions/inbox'
import { getDocumentSignedUrl } from '@/lib/actions/document'
import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'
import { UploadModal } from './UploadModal'

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
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [isActionModalOpen, setIsActionModalOpen] = useState(false)
  const router = useRouter()
  const { setBreadcrumbs } = useBreadcrumbs()
  
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

  // Polling for live status updates if any document is analyzing or pending
  const hasRunningJobs = documents.some(
    d => d.status === 'analyzing' || d.status === 'pending_assignment'
  )

  useEffect(() => {
    if (!hasRunningJobs) return

    const interval = setInterval(async () => {
      const latestDocs = await getStagedDocuments()
      setDocuments(latestDocs)
      
      // Update selected doc ref if it is no longer in list
      if (selectedDocId) {
        const stillExists = latestDocs.some(d => d.id === selectedDocId)
        if (!stillExists && latestDocs.length > 0) {
          setSelectedDocId(latestDocs[0].id)
        }
      }
    }, 4000)

    return () => clearInterval(interval)
  }, [hasRunningJobs, selectedDocId])

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
        alert(res.error)
      } else {
        setIsActionModalOpen(false)
        router.refresh()
      }
    })
  }

  function handleAutoCreate() {
    if (!selectedDocId) return
    startTransition(async () => {
      const res = await autoCreateClientAndMatterForStagedDocument(selectedDocId)
      if (res.error) {
        alert(res.error)
      } else {
        setIsActionModalOpen(false)
        router.refresh()
      }
    })
  }

  function handleDiscard() {
    if (!selectedDocId) return
    if (!confirm('Are you sure you want to discard this document? It will be permanently deleted.')) return
    
    startTransition(async () => {
      const res = await discardStagedDocument(selectedDocId)
      if (res.error) {
        alert(res.error)
      } else {
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
      alert(res.error || 'Failed to generate signed url')
    } else {
      window.open(res.url, '_blank')
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
    <div className="flex flex-col h-[calc(100vh-140px)] gap-4 animate-fade-in">
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
        <Button onClick={() => setIsUploadModalOpen(true)} variant="default">
          <Plus size={16} className="mr-2" />
          Add Document
        </Button>
      </div>

      <div className="flex flex-1 gap-6 overflow-hidden pt-2">
        {/* Left Pane: Queue (40%) */}
        <div className="w-[40%] flex flex-col gap-3 overflow-y-auto pr-4 custom-scrollbar">
          {documents.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full p-12 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] text-center shadow-[var(--shadow-sm)]">
              <FolderOpen size={32} className="text-[var(--text-muted)] mb-3" />
              <h3 className="text-section-heading text-[var(--text-primary)]">Queue is empty</h3>
              <p className="text-caption text-[var(--text-muted)] mt-1 max-w-xs">
                Upload files using the 'Add Document' button to stage them for AI analysis.
              </p>
            </div>
          ) : (
            documents.map(doc => {
              const fileName = doc.storage_path.split('/').pop()
              const isSelected = doc.id === selectedDocId
              const isAnalyzing = doc.status === 'analyzing'
              const isPending = doc.status === 'pending_assignment'
              const hasSuggestion = doc.suggested_client && doc.suggested_matter

              return (
                <div 
                  key={doc.id}
                  onClick={() => handleSelectDoc(doc)}
                  className={`relative flex items-start gap-3 p-4 rounded-[var(--radius-md)] border transition-all cursor-pointer overflow-hidden ${
                    isSelected 
                      ? 'border-[var(--primary)] bg-[#EFF6FF] shadow-[var(--shadow-sm)] border-l-[4px]' 
                      : 'border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-sm)]'
                  } ${isAnalyzing ? 'animate-pulse-slow' : ''}`}
                >
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-slate-50 border border-slate-200">
                    <FileText size={20} className="text-slate-500" />
                  </div>
                  <div className="flex flex-col gap-1 min-w-0 pt-0.5 flex-1">
                    <h3 className={`text-section-heading truncate ${isSelected ? 'text-[var(--primary)]' : 'text-[var(--text-primary)]'}`}>
                      {fileName}
                    </h3>
                    
                    {isAnalyzing ? (
                      <div className="flex items-center gap-1.5 text-caption text-[var(--accent)]">
                        <div className="h-3 w-3 animate-spin rounded-full border border-[var(--accent)] border-t-transparent" />
                        AI is analyzing...
                      </div>
                    ) : isPending ? (
                      <span className="text-caption text-[var(--text-muted)]">Queued for analysis</span>
                    ) : doc.status === 'failed' ? (
                      <span className="text-caption text-[var(--danger)] flex items-center gap-1">
                        <AlertCircle size={12} />
                        Analysis failed
                      </span>
                    ) : hasSuggestion ? (
                      <span className="text-caption text-[var(--success)] flex items-center gap-1">
                        <span className="h-1.5 w-1.5 rounded-full bg-[var(--success)]" />
                        AI suggestion ready
                      </span>
                    ) : (
                      <span className="text-caption text-amber-600 flex items-center gap-1">
                        <AlertCircle size={12} />
                        No match found
                      </span>
                    )}
                  </div>
                  {isSelected && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-[var(--primary)]">
                      <ChevronRight size={20} />
                    </div>
                  )}
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
                <div className="flex items-center gap-2">
                  <Button onClick={handleViewDocument} variant="secondary" size="sm">
                    <ExternalLink size={14} className="mr-1.5" />
                    Original PDF
                  </Button>
                  <Button onClick={() => setIsActionModalOpen(true)} variant="default" size="sm">
                    <Settings2 size={14} className="mr-1.5" />
                    Take Action
                  </Button>
                </div>
              </div>

              {/* AI Analysis Result */}
              {activeDoc.status === 'analyzing' ? (
                <div className="flex flex-col items-center justify-center p-12 rounded-md bg-surface border border-border-strong shadow-[var(--shadow-sm)] text-center text-primary">
                  <Loader2 size={32} className="animate-spin mb-3 text-[var(--accent)]" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">Extracting Metadata...</h3>
                  <p className="text-[12px] text-[var(--text-secondary)] mt-1">Vertex AI is analyzing the document context.</p>
                </div>
              ) : activeDoc.status === 'failed' ? (
                <div className="flex flex-col gap-4 p-5 rounded-md border border-red-200 bg-red-50">
                  <div className="flex items-center gap-2 text-[14px] font-semibold text-[var(--danger)]">
                    <AlertCircle size={16} />
                    AI Analysis Failed
                  </div>
                  <p className="text-[14px] text-red-900 leading-relaxed">
                    {activeDoc.suggestion_reason || 'An unknown error occurred during AI extraction.'}
                  </p>
                  <p className="text-[12px] text-red-700 font-medium">
                    You can still assign this document manually using the "Take Action" button.
                  </p>
                </div>
              ) : !hasExtractedMetadata ? (
                <div className="flex flex-col items-center justify-center p-12 rounded-md bg-surface border border-border shadow-[var(--shadow-sm)] text-center">
                  <AlertCircle size={32} className="text-[var(--text-muted)] mb-3" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">AI could not extract data from this document</h3>
                  <Button onClick={() => setIsActionModalOpen(true)} variant="secondary" className="mt-4">
                    Assign Manually
                  </Button>
                </div>
              ) : (
                /* Extracted Metadata Card */
                <div className="flex flex-col gap-5 p-6 rounded-md border border-border bg-surface shadow-[var(--shadow-sm)]">
                  <div className="flex items-center gap-2 text-[14px] font-semibold text-[var(--text-primary)]">
                    <Info size={16} className="text-[var(--accent)]" />
                    AI-Extracted Metadata
                  </div>

                  <dl className="grid grid-cols-2 gap-x-6 gap-y-4 text-[14px]">
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">Client Name</dt>
                      <dd className="font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.client_name || '-'}</dd>
                    </div>
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">GSTIN / PAN</dt>
                      <dd className="font-mono text-[var(--text-primary)]">
                        {activeDoc.raw_metadata?.gstin || '-'} 
                        {activeDoc.raw_metadata?.pan && ` / ${activeDoc.raw_metadata.pan}`}
                      </dd>
                    </div>
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">Document Type</dt>
                      <dd className="font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.doc_type || '-'}</dd>
                    </div>
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">Ref / Case Number</dt>
                      <dd className="font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.reference_number || '-'}</dd>
                    </div>
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">Financial Year</dt>
                      <dd className="font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.financial_year || '-'}</dd>
                    </div>
                    <div>
                      <dt className="text-[var(--text-muted)] text-[12px] font-semibold uppercase mb-1">Tax Period</dt>
                      <dd className="font-medium text-[var(--text-primary)]">{activeDoc.raw_metadata?.tax_period || '-'}</dd>
                    </div>
                  </dl>

                  {/* Summary */}
                  {activeDoc.raw_metadata?.summary && (
                    <div className="border-t border-[var(--border-subtle)] pt-4 mt-1">
                      <h4 className="text-[12px] font-semibold text-[var(--text-muted)] uppercase mb-2">AI Synopsis</h4>
                      <p className="text-[14px] text-[var(--text-secondary)] leading-relaxed">
                        {activeDoc.raw_metadata.summary}
                      </p>
                    </div>
                  )}

                  {/* Extracted Amounts */}
                  {activeDoc.raw_metadata?.extracted_amounts && Object.values(activeDoc.raw_metadata.extracted_amounts).some(v => v !== null) && (
                    <div className="border-t border-[var(--border-subtle)] pt-4 mt-1">
                      <h4 className="text-[12px] font-semibold text-[var(--text-muted)] uppercase mb-3">Financials</h4>
                      <div className="grid grid-cols-2 gap-3 text-[14px] font-mono">
                        {Object.entries(activeDoc.raw_metadata.extracted_amounts).map(([key, val]) => {
                          if (val === null || val === undefined) return null
                          return (
                            <div key={key} className="flex justify-between border-b border-[var(--border-subtle)] pb-1">
                              <span className="text-[var(--text-secondary)] text-[12px]">{humanizeKey(key)}</span>
                              <span className="text-[var(--text-primary)] font-medium">
                                ₹{Number(val).toLocaleString('en-IN')}
                              </span>
                            </div>
                          )
                        })}
                      </div>
                    </div>
                  )}
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
                <div className="p-4 bg-green-50 border border-green-200 rounded-md flex flex-col gap-2">
                  <span className="text-[12px] font-semibold text-[var(--success)] uppercase flex items-center gap-1.5">
                    <span className="h-1.5 w-1.5 rounded-full bg-[var(--success)]" />
                    Recommended Match
                  </span>
                  <div className="text-[14px] text-green-900 font-medium">
                    Client: {activeDoc.suggested_client.name}
                  </div>
                  <div className="text-[14px] text-green-900">
                    Matter: {activeDoc.suggested_matter.title} ({activeDoc.suggested_matter.matter_code})
                  </div>
                </div>
              )}

              {/* Dropdown search manual assignment */}
              <div className="flex flex-col gap-2">
                <label className="text-[12px] font-semibold text-[var(--text-secondary)] uppercase">
                  Select Matter
                </label>
                <select 
                  className="w-full bg-surface border border-border-strong rounded-md px-3 py-2.5 text-[14px] text-[var(--text-primary)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)] focus:border-transparent transition-shadow"
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
                  onClick={handleDiscard}
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
    </div>
  )
}
