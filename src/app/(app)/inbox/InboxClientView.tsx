'use client'

import { useState, useTransition, useEffect, useMemo, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import {
  FileText, AlertCircle, X, Check, Loader2, Plus, ExternalLink,
  RotateCcw, ChevronDown, ChevronUp, Sparkles, Search,
  FolderOpen, Zap, ArrowRight, Trash2, RefreshCw, Bot,
  FolderPlus, Copy, AlertTriangle, Inbox
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { createClient } from '@/lib/supabase/client'
import {
  assignStagedDocument, discardStagedDocument,
  autoCreateClientAndMatterForStagedDocument,
  getStagedDocuments
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

function uniqueDocumentsById<T extends { id: string }>(documents: T[]) {
  return Array.from(new Map(documents.map(document => [document.id, document])).values())
}

function StatusBadge({ doc }: { doc: any }) {
  const isAnalyzing = doc.status === 'analyzing'
  const isPending = doc.status === 'pending_assignment'
  const hasSuggestion = doc.suggested_client && doc.suggested_matter

  if (isAnalyzing) return <Badge variant="default" fixedWidth="lg"><Loader2 size={11} className="animate-spin" />Processing</Badge>
  if (isPending) return <Badge variant="muted" fixedWidth="lg">Queued</Badge>
  if (doc.status === 'failed') return <Badge variant="danger" fixedWidth="lg"><AlertCircle size={11} />Failed</Badge>
  if (doc.suggestion_reason?.toLowerCase().startsWith('duplicate')) return <Badge variant="warning" fixedWidth="lg"><Copy size={11} />Duplicate</Badge>
  if (hasSuggestion) return <Badge variant="success" fixedWidth="lg"><Check size={11} />Ready</Badge>
  return <Badge variant="warning" fixedWidth="lg"><AlertCircle size={11} />Review</Badge>
}

function processingCopy(status: string) {
  if (status === 'pending_assignment') {
    return { title: 'Queued for analysis', detail: 'Waiting for a worker to begin extraction and matching.' }
  }
  if (status === 'analyzing') {
    return { title: 'AI analysis in progress', detail: 'Extracting metadata, classifying the document, and checking existing records.' }
  }
  return null
}

function ProcessingProgress({ status, compact = false }: { status: string; compact?: boolean }) {
  const currentStep = status === 'analyzing' ? 1 : 0
  const steps = ['Queued', 'Extracting', 'Matching', 'Ready']

  return (
    <div className={cn('grid w-full grid-cols-4 gap-1.5', compact ? 'mt-2' : 'mt-5 max-w-md')} aria-label={`Processing stage: ${steps[currentStep]}`}>
      {steps.map((step, index) => (
        <div key={step} className="min-w-0">
          <span className={cn(
            'block h-1 rounded-full bg-[var(--border-strong)]',
            index < currentStep && 'bg-[var(--success)]',
            index === currentStep && 'bg-[var(--primary)] ring-2 ring-[color-mix(in_srgb,var(--primary)_18%,transparent)]'
          )} />
          {!compact && <span className={cn('mt-1.5 block truncate text-[10px]', index === currentStep ? 'font-medium text-[var(--primary)]' : 'text-[var(--text-muted)]')}>{step}</span>}
        </div>
      ))}
    </div>
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
        className={`w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-xl border text-sm transition-all ${isOpen
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
                  className={`w-full text-left flex items-center justify-between px-3 py-2.5 transition-colors border-l-2 ${m.id === selectedMatterId
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

function FullPageEmptyInbox({
  onUploadClick,
  title = 'Your Hub is Empty',
  description = 'Drag and drop files or click below to start uploading tax documents, invoices, or legal filings for AI analysis.',
  actionLabel = 'Upload Document',
}: {
  onUploadClick: () => void
  title?: string
  description?: string
  actionLabel?: string
}) {
  return (
    <div className="flex flex-1 items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6">
      <div className="flex max-w-md flex-col items-center text-center">
        <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)] text-[var(--primary)]">
          <Inbox size={24} aria-hidden="true" />
        </div>
        <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--primary)]">Document intake</p>
        <h2 className="mt-2 text-xl font-semibold text-[var(--text-primary)]">{title}</h2>
        <p className="mt-2 text-sm leading-6 text-[var(--text-muted)]">{description}</p>
        <Button onClick={onUploadClick} className="mt-6">
          <Plus size={16} aria-hidden="true" /> {actionLabel}
        </Button>
      </div>
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
  const [documents, setDocuments] = useState(() => uniqueDocumentsById(initialDocuments))
  const [selectedDocId, setSelectedDocId] = useState<string | null>(
    initialDocuments.length > 0 ? initialDocuments[0].id : null
  )
  const [selectedMatterId, setSelectedMatterId] = useState<string>(preselectedMatterId || '')
  const [selectedFyToCreate, setSelectedFyToCreate] = useState<string>('')
  const [isPending, startTransition] = useTransition()
  const [isReprocessing, setIsReprocessing] = useState<string | null>(null)
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [isActionModalOpen, setIsActionModalOpen] = useState(false)
  const [isDiscardConfirmOpen, setIsDiscardConfirmOpen] = useState(false)
  const [isSynopsisExpanded, setIsSynopsisExpanded] = useState(false)
  const [viewDocumentUrl, setViewDocumentUrl] = useState<string | null>(null)
  const [intakeTab, setIntakeTab] = useState<'global' | 'matter'>(preselectedMatterId ? 'matter' : 'global')
  const router = useRouter()
  const { setBreadcrumbs } = useBreadcrumbs()

  useEffect(() => { setDocuments(uniqueDocumentsById(initialDocuments)) }, [initialDocuments])

  const preselectedMatter = matters.find(m => m.id === preselectedMatterId)
  const isMatterIntake = intakeTab === 'matter' && Boolean(preselectedMatter)

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

  const matterIntakeDocuments = useMemo(
    () => preselectedMatterId ? documents.filter(doc => doc.intake_matter_id === preselectedMatterId) : [],
    [documents, preselectedMatterId],
  )
  const globalDocuments = useMemo(() => documents.filter(doc => !doc.intake_matter_id), [documents])
  const visibleDocuments = isMatterIntake ? matterIntakeDocuments : globalDocuments
  const activeDoc = visibleDocuments.find(d => d.id === selectedDocId)

  useEffect(() => {
    if (!visibleDocuments.some(doc => doc.id === selectedDocId)) {
      setSelectedDocId(visibleDocuments[0]?.id ?? null)
    }
  }, [visibleDocuments, selectedDocId])

  useEffect(() => {
    if (preselectedMatterId) { setSelectedMatterId(preselectedMatterId); return }
    if (activeDoc?.suggested_matter?.id) {
      setSelectedMatterId(activeDoc.suggested_matter.id)
    } else {
      setSelectedMatterId('')
    }
  }, [activeDoc, preselectedMatterId])

  const discardedDocIds = useRef<Set<string>>(new Set())
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  // A matter tab is an active intake session, not a permanent alternate view.
  // Keep an empty tab open initially so a user can add files, then return to
  // the global hub after a queue that contained files has fully cleared.
  const hadMatterQueueRef = useRef(Boolean(
    preselectedMatterId && initialDocuments.some(doc => doc.intake_matter_id === preselectedMatterId),
  ))

  // Use refs to access latest state inside the websocket callback without causing reconnects
  const docsRef = useRef(documents)
  const selectedIdRef = useRef(selectedDocId)

  useEffect(() => {
    docsRef.current = documents
    selectedIdRef.current = selectedDocId
  }, [documents, selectedDocId])

  useEffect(() => {
    if (matterIntakeDocuments.length > 0) hadMatterQueueRef.current = true
  }, [matterIntakeDocuments.length])

  useEffect(() => {
    if (
      preselectedMatterId &&
      hadMatterQueueRef.current &&
      matterIntakeDocuments.length === 0
    ) {
      setIntakeTab('global')
      router.replace('/inbox')
    }
  }, [matterIntakeDocuments.length, preselectedMatterId, router])

  useEffect(() => {
    const supabase = createClient()
    let disposed = false
    const channel = supabase.channel('staged_docs_changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'staged_documents' }, (payload) => {
        if (payload.eventType === 'UPDATE') {
          const updatedId = payload.new.id
          const newStatus = payload.new.status

          setDocuments(currentDocs => {
            // If it became auto_assigned, remove it from the list and show a toast
            if (newStatus === 'auto_assigned') {
              if (!discardedDocIds.current.has(updatedId)) {
                const oldDoc = currentDocs.find(d => d.id === updatedId)
                if (oldDoc) {
                  toast.success(`Automated Processing Complete`, {
                    description: `${oldDoc.storage_path.split('/').pop()} was successfully assigned.`,
                  })
                }
              }
              return currentDocs.filter(d => d.id !== updatedId)
            }

            // Otherwise, update the document in the list with the new data
            return currentDocs.map(d => d.id === updatedId ? { ...d, ...payload.new } : d)
          })

          // Handle selected document changing or disappearing
          if (selectedIdRef.current === updatedId && newStatus === 'auto_assigned') {
            setSelectedDocId(null) // It's gone, so deselect it
          }
        } else if (payload.eventType === 'INSERT') {
          // If a new document is staged, add it to the list
          setDocuments(currentDocs => {
            const existingIndex = currentDocs.findIndex(document => document.id === payload.new.id)
            if (existingIndex === -1) return [...currentDocs, payload.new]
            return currentDocs.map((document, index) => index === existingIndex ? { ...document, ...payload.new } : document)
          })
        } else if (payload.eventType === 'DELETE') {
          // If a document is deleted, remove it from the list
          setDocuments(currentDocs => currentDocs.filter(d => d.id !== payload.old.id))
          if (selectedIdRef.current === payload.old.id) {
            setSelectedDocId(null)
          }
        }

        // Realtime payloads contain only staged_documents columns. Refresh the
        // authoritative query so new/updated cards also get client and matter
        // joins, rather than briefly rendering as an incomplete "unknown" item.
        if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current)
        refreshTimerRef.current = setTimeout(() => {
          void getStagedDocuments().then(latestDocuments => setDocuments(uniqueDocumentsById(latestDocuments)))
          router.refresh()
        }, 250)
      })
    // Realtime RLS needs the browser session token. Hydration can run before
    // the client has loaded its auth cookie, so set it before subscribing.
    void (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (session?.access_token) await supabase.realtime.setAuth(session.access_token)
      if (disposed) return
      channel.subscribe()
    })()

    return () => {
      disposed = true
      if (refreshTimerRef.current) clearTimeout(refreshTimerRef.current)
      supabase.removeChannel(channel)
    }
  }, [router])

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
        const latestDocs = await getStagedDocuments()
        setDocuments(uniqueDocumentsById(latestDocs))
        router.refresh()
      }
    })
  }

  function handleAutoCreate() {
    if (!selectedDocId) return
    startTransition(async () => {
      const res = await autoCreateClientAndMatterForStagedDocument(selectedDocId, selectedFyToCreate)
      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Matter and client automatically created')
        setIsActionModalOpen(false)
        const latestDocs = await getStagedDocuments()
        setDocuments(uniqueDocumentsById(latestDocs))
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

  const isDuplicate = activeDoc?.suggestion_reason?.toLowerCase().startsWith('duplicate')
  const hasSuggestion = activeDoc?.suggested_client && activeDoc?.suggested_matter
  const activeProcessingCopy = activeDoc ? processingCopy(activeDoc.status) : null

  return (
    <div className="flex flex-col flex-1 overflow-hidden animate-fade-in">
      {preselectedMatter && (
        <div className="mb-4 flex items-center gap-1 overflow-x-auto border-b border-[var(--border)] pb-0 custom-scrollbar">
          <button
            onClick={() => setIntakeTab('matter')}
            aria-current={isMatterIntake ? 'page' : undefined}
            className={cn(
              'flex h-9 shrink-0 items-center gap-2 rounded-t-lg border border-b-0 px-3 text-xs font-semibold transition-colors',
              isMatterIntake
                ? 'border-[var(--border-strong)] bg-[var(--surface)] text-[var(--text-primary)] shadow-[0_-1px_5px_rgba(0,0,0,0.04)]'
                : 'border-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]',
            )}
          >
            <FolderOpen size={13} className={isMatterIntake ? 'text-[var(--primary)]' : ''} />
            <span className="max-w-44 truncate">{preselectedMatter.title}</span>
            <span className="rounded-full bg-[var(--surface-hover)] px-1.5 py-0.5 text-[10px] text-[var(--text-muted)]">{matterIntakeDocuments.length}</span>
          </button>
          <button
            onClick={() => setIntakeTab('global')}
            aria-current={!isMatterIntake ? 'page' : undefined}
            className={cn(
              'flex h-9 shrink-0 items-center gap-2 rounded-t-lg border border-b-0 px-3 text-xs font-semibold transition-colors',
              !isMatterIntake
                ? 'border-[var(--border-strong)] bg-[var(--surface)] text-[var(--text-primary)] shadow-[0_-1px_5px_rgba(0,0,0,0.04)]'
                : 'border-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]',
            )}
          >
            <Inbox size={14} /> Global inbox
            <span className="rounded-full bg-[var(--surface-hover)] px-1.5 py-0.5 text-[10px] text-[var(--text-muted)]">{globalDocuments.length}</span>
          </button>
        </div>
      )}

      {isUploadModalOpen && (
        <div className="mb-4">
          <UploadModal
            onClose={() => setIsUploadModalOpen(false)}
            matterId={isMatterIntake ? preselectedMatterId : undefined}
            matterName={isMatterIntake ? preselectedMatter?.title : undefined}
          />
        </div>
      )}
      {/* ── Body ─────────────────────────────────── */}
      {visibleDocuments.length === 0 ? (
        <FullPageEmptyInbox
          onUploadClick={() => setIsUploadModalOpen(true)}
          title={isMatterIntake ? `No files waiting for ${preselectedMatter?.title}` : 'Your Global Inbox is Empty'}
          description={isMatterIntake
            ? 'Files added here are analysed and routed only to this matter. Your global triage queue remains untouched.'
            : 'Drop tax documents, invoices, or legal filings here for AI-assisted triage across your organisation.'}
          actionLabel={isMatterIntake ? 'Add to This Matter' : 'Upload to Global Inbox'}
        />
      ) : (
        <div className="flex flex-1 flex-col gap-3 overflow-y-auto pt-2 lg:flex-row lg:gap-0 lg:overflow-hidden">

          {/* ── Left Queue Panel ──────────────────── */}
          <div className="flex w-full shrink-0 flex-col gap-2 overflow-visible py-1 lg:w-[42%] lg:overflow-y-auto lg:pr-3 custom-scrollbar">
          <div className="flex items-center justify-end gap-2">
            <button
              onClick={async () => {
                const toastId = toast.loading('Syncing queue...')
                try {
                  const latestDocs = await getStagedDocuments()
                  setDocuments(uniqueDocumentsById(latestDocs))
                  router.refresh()
                  toast.success('Queue synced', { id: toastId })
                } catch (err: any) {
                  toast.error(err.message || 'Failed to refresh', { id: toastId })
                }
              }}
              className="flex h-9 items-center justify-center gap-1.5 rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-[12px] font-medium text-[var(--text-secondary)] transition-colors hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]"
            >
              <RefreshCw size={13} />
              Sync
            </button>
            <button
              onClick={() => setIsUploadModalOpen(value => !value)}
              className="flex h-9 items-center justify-center gap-1.5 rounded-[var(--radius-sm)] bg-[var(--primary)] px-4 text-[12px] font-medium text-[var(--surface)] shadow-sm transition-colors hover:bg-[var(--primary-hover)] dark:text-[#0b1920]"
            >
              <Plus size={13} /> {isUploadModalOpen ? 'Close' : 'Upload'}
            </button>
          </div>

          <div className="text-[11px] font-bold text-[var(--text-muted)] uppercase tracking-widest px-0.5">
            {isMatterIntake ? 'Matter intake' : 'Global inbox'} · {visibleDocuments.length} document{visibleDocuments.length !== 1 ? 's' : ''}
          </div>
          {visibleDocuments.map((doc) => {
                const fileName = doc.storage_path.split('/').pop()
                const isSelected = doc.id === selectedDocId
                const isDup = doc.suggestion_reason?.toLowerCase().startsWith('duplicate')
                const isFailed = doc.status === 'failed'
                const isReady = doc.suggested_client && doc.suggested_matter
                const queueCopy = processingCopy(doc.status)

                return (
                  <div
                    key={doc.id}
                    onClick={() => handleSelectDoc(doc)}
                    className={cn(
                      'group relative cursor-pointer overflow-hidden rounded-[var(--radius-md)] border transition-colors duration-150',
                      isSelected
                        ? 'border-[var(--border-strong)] bg-[var(--accent-muted)] shadow-[inset_3px_0_var(--primary)]'
                        : 'border-[var(--border)] bg-[var(--surface)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-hover)]'
                    )}
                  >
                    <div className="flex items-center gap-3 p-3 pl-4">
                      {/* File Icon */}
                      <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] transition-colors ${isSelected ? 'bg-[var(--surface)]' : 'bg-[var(--surface-hover)]'
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

                      <ArrowRight size={12} className={`shrink-0 transition-all duration-200 ${isSelected ? 'text-[var(--primary)] translate-x-0' : 'text-[var(--text-disabled)] -translate-x-0.5 group-hover:translate-x-0 group-hover:text-[var(--text-muted)]'
                        }`} />
                    </div>

                    {/* bottom hint strip for ready docs */}
                    {isReady && !isDup && !isFailed && (
                      <div className="flex items-center gap-1 px-4 pb-2 pt-0.5 text-[10px] font-medium text-[var(--success)]">
                        <Zap size={9} /> AI matched · {doc.suggested_client?.name}
                      </div>
                    )}
                    {queueCopy && (
                      <div className="px-4 pb-3 pt-0.5 text-[10px] font-medium text-[var(--text-secondary)]">
                        <div className="flex items-center gap-1"><Loader2 size={10} className={doc.status === 'analyzing' ? 'animate-spin' : ''} /> {queueCopy.title}</div>
                        <ProcessingProgress status={doc.status} compact />
                      </div>
                    )}
                    {isDup && (
                      <div className="flex items-center gap-1 px-4 pb-2 pt-0.5 text-[10px] font-medium text-[var(--warning)]">
                        <Copy size={9} /> Duplicate detected
                      </div>
                    )}
                    {isFailed && (
                      <div className="flex items-center gap-1 px-4 pb-2 pt-0.5 text-[10px] font-medium text-[var(--danger)]">
                        <AlertCircle size={9} /> AI extraction failed · click to reprocess
                      </div>
                    )}
                  </div>
                )
              })}
        </div>

        {/* ── Vertical Divider ─── */}
        <div className="mx-2 hidden w-px shrink-0 bg-[var(--border)] lg:block" />

        {/* ── Right Detail Panel ─────────────────── */}
        <div className="flex flex-1 flex-col overflow-visible lg:overflow-y-auto lg:pl-4 custom-scrollbar">
          {activeDoc ? (
            <div className="flex flex-col gap-5">

              {/* Document title + action strip */}
              <div className="flex flex-col items-start justify-between gap-3 sm:flex-row">
                <div className="min-w-0">
                  <h2 className="text-[16px] font-bold text-[var(--text-primary)] leading-snug truncate max-w-[380px]">
                    {activeDoc.storage_path.split('/').pop()}
                  </h2>
                  <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-widest text-[var(--text-muted)]">
                    {activeProcessingCopy ? activeProcessingCopy.title : 'Ready for document review'}
                  </p>
                </div>

                {/* Action Buttons row */}
                <div className="flex shrink-0 flex-wrap items-center gap-1.5">
                  <button
                    onClick={() => handleReprocess(activeDoc.id)}
                    disabled={isReprocessing === activeDoc.id}
                    title="Re-run AI extraction"
                    className="flex h-8 w-8 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] text-[var(--text-muted)] transition-colors hover:border-[var(--border-strong)] hover:text-[var(--text-primary)] disabled:opacity-50"
                  >
                    <RotateCcw size={13} className={isReprocessing === activeDoc.id ? 'animate-spin' : ''} />
                  </button>
                  <button
                    onClick={handleViewDocument}
                    title="View original PDF"
                    className="flex h-8 items-center gap-1.5 rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-[12px] font-medium text-[var(--text-secondary)] transition-colors hover:border-[var(--border-strong)] hover:text-[var(--text-primary)]"
                  >
                    <ExternalLink size={12} /> PDF
                  </button>
                  <button
                    onClick={() => setIsActionModalOpen(true)}
                    disabled={Boolean(activeProcessingCopy)}
                    title={activeProcessingCopy ? 'Assignment is available after analysis finishes' : 'Choose how to route this document'}
                    className="flex h-8 items-center gap-1.5 rounded-[var(--radius-sm)] bg-[var(--primary)] px-4 text-[13px] font-medium text-[var(--surface)] transition-colors hover:bg-[var(--primary-hover)] disabled:opacity-50 dark:text-[#0b1920]"
                  >
                    <Zap size={13} /> Take Action
                  </button>
                </div>
              </div>

              {/* ── State panels ── */}
              {activeProcessingCopy ? (
                <div className="flex flex-col items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] px-5 py-12 text-center">
                  <div className="relative mb-5">
                    <div className="flex h-14 w-14 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)]">
                      <Bot size={24} className="text-[var(--primary)]" />
                    </div>
                    <Loader2 size={14} className="animate-spin text-[var(--primary)] absolute -bottom-1 -right-1" />
                  </div>
                  <h3 className="text-[15px] font-bold text-[var(--text-primary)]">{activeProcessingCopy.title}</h3>
                  <p className="text-[13px] text-[var(--text-secondary)] mt-1.5 max-w-xs">
                    {activeProcessingCopy.detail}
                  </p>
                  <ProcessingProgress status={activeDoc.status} />
                </div>
              ) : activeDoc.status === 'failed' ? (
                <div className="overflow-hidden rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--danger)_28%,transparent)] bg-[var(--danger-muted)]">
                  <div className="flex items-center gap-3 border-b border-[color-mix(in_srgb,var(--danger)_22%,transparent)] p-4">
                    <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface)]">
                      <AlertTriangle size={16} className="text-[var(--danger)]" />
                    </div>
                    <div>
                      <div className="text-[14px] font-semibold text-[var(--danger)]">AI extraction failed</div>
                      <div className="mt-0.5 text-[12px] text-[var(--text-secondary)]">The document could not be processed automatically</div>
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
                <div className="flex flex-col items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] py-14 text-center">
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
                    <div className="flex items-start gap-3 rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--warning)_28%,transparent)] bg-[var(--warning-muted)] p-4">
                      <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface)]">
                        <Copy size={14} className="text-[var(--warning)]" />
                      </div>
                      <div>
                        <div className="mb-1 text-[13px] font-semibold text-[var(--warning)]">Duplicate document detected</div>
                        <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                          {activeDoc.suggestion_reason?.replace('DUPLICATE: ', '')}
                        </p>
                      </div>
                    </div>
                  )}

                  {/* AI Match suggestion */}
                  {hasSuggestion && !isDuplicate && (
                    <div className="flex items-center justify-between gap-3 rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--success)_24%,transparent)] bg-[var(--success-muted)] p-3.5">
                      <div className="flex items-center gap-2.5">
                        <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface)]">
                          <Zap size={12} className="text-[var(--success)]" />
                        </div>
                        <div>
                          <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--success)]">AI recommended match</div>
                          <div className="text-[13px] font-medium text-[var(--text-primary)] mt-0.5">
                            {activeDoc.suggested_client?.name} · {activeDoc.suggested_matter?.title}
                          </div>
                        </div>
                      </div>
                      <button
                        onClick={() => setIsActionModalOpen(true)}
                        className="h-7 shrink-0 rounded-[var(--radius-sm)] bg-[var(--success)] px-3 text-[11px] font-medium text-[var(--surface)] transition-colors hover:opacity-90 dark:text-[#0b1920]"
                      >
                        Confirm
                      </button>
                    </div>
                  )}

                  {/* Metadata Card */}
                  <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] shadow-sm">
                    <div className="h-0.5 bg-[var(--primary)]" />

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
            <div className="flex h-full flex-col items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] px-6 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-[var(--radius-md)] bg-[var(--surface-hover)] text-[var(--text-muted)]">
                <FileText size={22} aria-hidden="true" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-[var(--text-primary)]">Select a document</h3>
              <p className="mt-1 max-w-sm text-sm leading-6 text-[var(--text-muted)]">Review extracted details, processing state, and routing suggestions for the selected queue item.</p>
            </div>
          )}
        </div>
      </div>
      )}

      {/* ── Action Modal ── */}
      {isActionModalOpen && activeDoc && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="relative flex w-[92%] max-w-[460px] flex-col overflow-hidden rounded-[var(--radius-lg)] border border-[var(--border)] shadow-xl"
            style={{ background: 'var(--surface)' }}
          >
            <div className="h-1 w-full shrink-0 bg-[var(--primary)]" />

            {/* Header */}
            <div className="flex items-start justify-between p-5 pb-3">
              <div className="flex items-start gap-3">
                <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)]">
                  <Zap size={18} className="text-[var(--primary)]" />
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
                <div className="flex items-center gap-2.5 rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--success)_24%,transparent)] bg-[var(--success-muted)] p-3">
                  <Check size={14} className="shrink-0 text-[var(--success)]" />
                  <div className="flex-1 min-w-0">
                    <div className="text-[10px] font-semibold uppercase tracking-wide text-[var(--success)]">AI recommended</div>
                    <div className="text-[13px] font-semibold text-[var(--text-primary)] truncate">
                      {activeDoc.suggested_client?.name} · {activeDoc.suggested_matter?.title}
                    </div>
                  </div>
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
                  className="flex h-10 w-full items-center justify-center gap-2 rounded-[var(--radius-sm)] bg-[var(--primary)] text-[14px] font-medium text-[var(--surface)] transition-colors hover:bg-[var(--primary-hover)] disabled:cursor-not-allowed disabled:opacity-50 dark:text-[#0b1920]"
                >
                  {isPending ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                  {isPending ? 'Assigning…' : 'Confirm Assignment'}
                </button>

                {/* Auto-create */}
                {activeDoc.status !== 'failed' && (!activeDoc.suggested_matter || matters.length === 0) && !preselectedMatterId && (
                  <div className="flex flex-col gap-2 mt-1">
                    {activeDoc.raw_metadata?.financial_years && activeDoc.raw_metadata.financial_years.length > 1 && (
                      <div className="flex flex-col gap-1.5 p-3 rounded-xl border border-[var(--primary)]/20 bg-[var(--primary)]/5">
                        <label className="text-[11px] font-bold text-[var(--primary)] uppercase tracking-widest flex items-center gap-1.5">
                          <AlertCircle size={12} />
                          Multiple FYs Detected
                        </label>
                        <p className="text-[12px] text-[var(--text-secondary)] mb-1">
                          This document spans multiple years. Choose which financial year to create the matter under:
                        </p>
                        <select
                          value={selectedFyToCreate}
                          onChange={(e) => setSelectedFyToCreate(e.target.value)}
                          className="w-full text-[13px] bg-[var(--surface)] border border-[var(--border-strong)] rounded-lg px-3 py-2 outline-none focus:border-[var(--primary)] text-[var(--text-primary)]"
                        >
                          <option value="">Select Financial Year...</option>
                          {activeDoc.raw_metadata.financial_years.map((fy: string) => (
                            <option key={fy} value={fy}>{fy}</option>
                          ))}
                        </select>
                      </div>
                    )}
                    <button
                      onClick={handleAutoCreate}
                      disabled={isPending || (activeDoc.raw_metadata?.financial_years?.length > 1 && !selectedFyToCreate)}
                      className="w-full h-10 flex items-center justify-center gap-2 rounded-xl text-[13px] font-semibold border border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] transition-all disabled:opacity-50"
                    >
                      {isPending ? <Loader2 size={14} className="animate-spin" /> : <FolderPlus size={14} />}
                      Auto-Create Client & Matter
                    </button>
                  </div>
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
