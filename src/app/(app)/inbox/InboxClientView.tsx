'use client'

import { useState, useTransition, useEffect, useMemo, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import {
  FileText, AlertCircle, Check, Loader2, Plus, ExternalLink,
  ChevronDown, ChevronUp, Sparkles, Search,
  FolderOpen, Zap, ArrowRight, Trash2, RefreshCw, Bot,
  FolderPlus, Copy, AlertTriangle, Inbox
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { createClient } from '@/lib/supabase/client'
import {
  assignCanonicalIntakeToMatter, assignStagedDocument, discardCanonicalIntake, discardStagedDocument, getCanonicalDuplicateResolution,
  autoCreateClientAndMatterForStagedDocument,
  getStagedDocuments
} from '@/lib/actions/inbox'
import { getDocumentSignedUrl, getIntakeItemSignedUrl } from '@/lib/actions/document'
import { canonicalIntakeActions } from '@/lib/inbox-compat'
import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'
import { UploadModal } from './UploadModal'
import { DocumentViewerModal } from './DocumentViewerModal'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog'

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
  const isPlacementReady = doc.status === 'ready_for_placement'
  const isDuplicate = doc.status === 'duplicate' || doc.suggestion_reason?.toLowerCase().startsWith('duplicate')
  const hasSuggestion = doc.suggested_client && doc.suggested_matter

  if (isAnalyzing) return <Badge variant="default" fixedWidth="xl"><Loader2 size={11} className="animate-spin" />Processing</Badge>
  if (isPending) return <Badge variant="muted" fixedWidth="xl">Queued</Badge>
  if (isDuplicate) return <Badge variant="warning" fixedWidth="xl"><Copy size={11} />Duplicate</Badge>
  if (doc.status === 'failed') return <Badge variant="danger" fixedWidth="xl"><AlertCircle size={11} />Failed</Badge>
  if (isPlacementReady) return <Badge variant="success" fixedWidth="xl"><Check size={11} />Ready to place</Badge>
  if (hasSuggestion) return <Badge variant="success" fixedWidth="xl"><Check size={11} />Ready</Badge>
  return <Badge variant="warning" fixedWidth="xl"><AlertCircle size={11} />Review</Badge>
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

function documentStatusLabel(doc: {
  status?: string
  suggestion_reason?: string | null
  suggested_client?: unknown
  suggested_matter?: unknown
}) {
  if (doc.status === 'analyzing') return 'Processing'
  if (doc.status === 'pending_assignment') return 'Queued'
  if (doc.status === 'ready_for_placement') return 'Ready to place'
  if (doc.status === 'duplicate' || doc.suggestion_reason?.toLowerCase().startsWith('duplicate')) return 'Duplicate'
  if (doc.status === 'failed') return 'Failed'
  if (doc.suggested_client && doc.suggested_matter) return 'Ready'
  return 'Review'
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
        className={`w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-[var(--radius-md)] border text-sm transition-all ${isOpen
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
        <div className="absolute z-50 top-full mt-1 w-full bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)] shadow-2xl overflow-hidden animate-in fade-in slide-in-from-top-2 duration-150">
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
  uploadButtonRef,
  title = 'Your Hub is Empty',
  description = 'Drag and drop files or click below to start uploading tax documents, invoices, or legal filings for AI analysis.',
  actionLabel = 'Upload Document',
}: {
  onUploadClick: () => void
  uploadButtonRef?: React.RefObject<HTMLButtonElement | null>
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
        <Button ref={uploadButtonRef} onClick={onUploadClick} className="mt-6">
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
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false)
  const [isActionModalOpen, setIsActionModalOpen] = useState(false)
  const [isDiscardConfirmOpen, setIsDiscardConfirmOpen] = useState(false)
  const [isSynopsisExpanded, setIsSynopsisExpanded] = useState(false)
  const [viewDocumentUrl, setViewDocumentUrl] = useState<string | null>(null)
  const [intakeTab, setIntakeTab] = useState<'global' | 'matter'>(preselectedMatterId ? 'matter' : 'global')
  const uploadTriggerRef = useRef<HTMLButtonElement>(null)
  const viewPdfButtonRef = useRef<HTMLButtonElement>(null)
  const takeActionButtonRef = useRef<HTMLButtonElement>(null)
  const canonicalActionKeys = useRef(new Map<string, string>())
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
  const isCanonicalIntake = activeDoc?.source_kind === 'canonical_intake'
  const activeCanonicalActions = canonicalIntakeActions(activeDoc?.canonical_intake_state ?? '')

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
    // `intake_items` is deliberately absent from the Realtime publication:
    // its compatibility projection uses a privileged, org-scoped server read.
    // Subscribe only to legacy staged rows; the visible Refresh queue control
    // below is the explicit, safe freshness path for canonical intake updates.
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
      const res = isCanonicalIntake
        ? await assignCanonicalIntakeToMatter(selectedDocId, selectedMatterId, canonicalActionKeys.current.get(`assign:${selectedDocId}`) ?? (() => { const key = crypto.randomUUID(); canonicalActionKeys.current.set(`assign:${selectedDocId}`, key); return key })())
        : await assignStagedDocument(selectedDocId, selectedMatterId)
      if (res.error) {
        toast.error(res.error)
      } else {
        if (isCanonicalIntake) canonicalActionKeys.current.delete(`assign:${selectedDocId}`)
        toast.success('Document assigned successfully')
        setIsActionModalOpen(false)
        const latestDocs = await getStagedDocuments()
        setDocuments(uniqueDocumentsById(latestDocs))
        router.refresh()
      }
    })
  }

  function handleAutoCreate() {
    if (isCanonicalIntake) return
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
      const res = isCanonicalIntake
        ? await discardCanonicalIntake(selectedDocId, canonicalActionKeys.current.get(`discard:${selectedDocId}`) ?? (() => { const key = crypto.randomUUID(); canonicalActionKeys.current.set(`discard:${selectedDocId}`, key); return key })())
        : await discardStagedDocument(selectedDocId)
      if (res.error) {
        toast.error(res.error)
      } else {
        if (isCanonicalIntake) canonicalActionKeys.current.delete(`discard:${selectedDocId}`)
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
    if (isCanonicalIntake) {
      const res = await getIntakeItemSignedUrl(activeDoc.id)
      if (res.error || !res.url) toast.error(res.error || 'Failed to generate signed URL')
      else setViewDocumentUrl(res.url)
      return
    }
    const res = await getDocumentSignedUrl('staging', activeDoc.storage_path)
    if (res.error || !res.url) {
      toast.error(res.error || 'Failed to generate signed url')
    } else {
      setViewDocumentUrl(res.url)
    }
  }

  async function handleOpenCanonicalDuplicate() {
    if (!activeDoc) return
    const result = await getCanonicalDuplicateResolution(activeDoc.id)
    if (result.code === 'ok') {
      router.push(`/matters/${result.matterId}/documents/${result.documentId}`)
      return
    }
    if (result.code === 'in_trash') {
      toast.error('The matching document is in your organisation Trash and must be restored before it can be used.')
      return
    }
    toast.error('The matching document is not available. Refresh the queue or contact support.')
  }

  const hasExtractedMetadata = activeDoc && activeDoc.raw_metadata && Object.keys(activeDoc.raw_metadata).length > 0 && (
    activeDoc.raw_metadata.client_name ||
    activeDoc.raw_metadata.gstin ||
    activeDoc.raw_metadata.reference_number ||
    activeDoc.raw_metadata.doc_type ||
    activeDoc.raw_metadata.financial_year ||
    activeDoc.raw_metadata.tax_period
  )

  const isDuplicate = activeDoc?.status === 'duplicate' || activeDoc?.suggestion_reason?.toLowerCase().startsWith('duplicate')
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
              'flex min-h-11 shrink-0 items-center gap-2 rounded-t-[var(--radius-md)] border border-b-0 px-3 text-xs font-semibold transition-colors',
              isMatterIntake
                ? 'border-[var(--border-strong)] bg-[var(--surface)] text-[var(--text-primary)] shadow-[0_-1px_5px_rgba(0,0,0,0.04)]'
                : 'border-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]',
            )}
          >
            <FolderOpen size={13} className={isMatterIntake ? 'text-[var(--primary)]' : ''} />
            <span className="max-w-44 truncate">{preselectedMatter.title}</span>
            <span className="rounded-[var(--radius-sm)] bg-[var(--surface-hover)] px-1.5 py-0.5 text-[10px] text-[var(--text-muted)]">{matterIntakeDocuments.length}</span>
          </button>
          <button
            onClick={() => setIntakeTab('global')}
            aria-current={!isMatterIntake ? 'page' : undefined}
            className={cn(
              'flex min-h-11 shrink-0 items-center gap-2 rounded-t-[var(--radius-md)] border border-b-0 px-3 text-xs font-semibold transition-colors',
              !isMatterIntake
                ? 'border-[var(--border-strong)] bg-[var(--surface)] text-[var(--text-primary)] shadow-[0_-1px_5px_rgba(0,0,0,0.04)]'
                : 'border-transparent text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]',
            )}
          >
            <Inbox size={14} /> Global inbox
            <span className="rounded-[var(--radius-sm)] bg-[var(--surface-hover)] px-1.5 py-0.5 text-[10px] text-[var(--text-muted)]">{globalDocuments.length}</span>
          </button>
        </div>
      )}

      {isUploadModalOpen && (
        <div className="mb-4">
          <UploadModal
            onClose={() => setIsUploadModalOpen(false)}
            matterId={isMatterIntake ? preselectedMatterId : undefined}
            matterName={isMatterIntake ? preselectedMatter?.title : undefined}
            returnFocusRef={uploadTriggerRef}
          />
        </div>
      )}
      {/* ── Body ─────────────────────────────────── */}
      {visibleDocuments.length === 0 ? (
        <FullPageEmptyInbox
          onUploadClick={() => setIsUploadModalOpen(true)}
          uploadButtonRef={uploadTriggerRef}
          title={isMatterIntake ? `No files waiting for ${preselectedMatter?.title}` : 'Your Global Inbox is Empty'}
          description={isMatterIntake
            ? 'Files added here are analysed and routed only to this matter. Your global triage queue remains untouched.'
            : 'Drop tax documents, invoices, or legal filings here for AI-assisted triage across your organisation.'}
          actionLabel={isMatterIntake ? 'Add to This Matter' : 'Upload to Global Inbox'}
        />
      ) : (
        <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto pt-2 custom-scrollbar lg:flex-row lg:gap-0 lg:overflow-hidden">

          {/* ── Left Queue Panel ──────────────────── */}
          <section className="flex w-full shrink-0 flex-col overflow-visible py-1 lg:min-h-0 lg:w-[42%] lg:overflow-hidden lg:pr-3">
          <header className="shrink-0 border-b border-[var(--border)] pb-2">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="min-w-0 text-[11px] font-bold uppercase tracking-widest text-[var(--text-muted)]">
              {isMatterIntake ? 'Matter intake' : 'Global inbox'} · {visibleDocuments.length} document{visibleDocuments.length !== 1 ? 's' : ''}
            </div>
            <div className="flex shrink-0 items-center gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={async () => {
                const toastId = toast.loading('Refreshing queue...')
                try {
                  const latestDocs = await getStagedDocuments()
                  setDocuments(uniqueDocumentsById(latestDocs))
                  router.refresh()
                  toast.success('Queue refreshed', { id: toastId })
                } catch (err: any) {
                  toast.error(err.message || 'Failed to refresh', { id: toastId })
                }
              }}
            >
              <RefreshCw size={13} aria-hidden="true" />
              Refresh queue
            </Button>
            <Button
              type="button"
              size="sm"
              ref={uploadTriggerRef}
              onClick={() => setIsUploadModalOpen(value => !value)}
            >
              <Plus size={13} aria-hidden="true" /> {isUploadModalOpen ? 'Close upload' : 'Upload'}
            </Button>
            </div>
          </div>
          </header>
          <div className="min-h-0 flex-1 overflow-visible lg:overflow-y-auto custom-scrollbar">
          <div className="flex flex-col gap-2 py-2">
          {visibleDocuments.map((doc) => {
                const fileName = doc.storage_path.split('/').pop()
                const isSelected = doc.id === selectedDocId
                const isDup = doc.status === 'duplicate' || doc.suggestion_reason?.toLowerCase().startsWith('duplicate')
                const isFailed = doc.status === 'failed'
                const isReady = doc.status === 'ready_for_placement' || (doc.suggested_client && doc.suggested_matter)
                const queueCopy = processingCopy(doc.status)

                return (
                  <button
                    type="button"
                    key={doc.id}
                    onClick={() => handleSelectDoc(doc)}
                    aria-pressed={isSelected}
                    aria-label={`${fileName || 'Untitled document'}, ${documentStatusLabel(doc)}${isSelected ? ', selected' : ''}`}
                    className={cn(
                      'group relative block w-full cursor-pointer appearance-none overflow-hidden rounded-[var(--radius-md)] border bg-transparent p-0 text-left font-[inherit] transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-1 focus-visible:ring-offset-[var(--bg)]',
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
                        {doc.status === 'ready_for_placement'
                          ? <><Check size={9} /> Ready for placement</>
                          : <><Zap size={9} /> AI matched · {doc.suggested_client?.name}</>}
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
                        <AlertCircle size={9} /> {doc.suggestion_reason || 'Processing failed'}
                      </div>
                    )}
                  </button>
                )
              })}
          </div>
          </div>
        </section>

        {/* ── Vertical Divider ─── */}
        <div className="mx-2 hidden w-px shrink-0 bg-[var(--border)] lg:block" />

        {/* ── Right Detail Panel ─────────────────── */}
        <section className="flex min-w-0 flex-1 flex-col overflow-visible lg:min-h-0 lg:overflow-hidden lg:pl-4">
          {activeDoc ? (
            <>

              {/* Document title + action strip */}
              <header className="sticky top-0 z-10 flex shrink-0 flex-col items-start justify-between gap-3 border-b border-[var(--border)] bg-[var(--bg)] py-2 sm:flex-row sm:items-center">
                <div className="min-w-0 max-w-full">
                  <h2 className="max-w-full truncate text-[16px] font-bold leading-snug text-[var(--text-primary)] sm:max-w-[380px]">
                    {activeDoc.storage_path.split('/').pop()}
                  </h2>
                  <p className="mt-0.5 text-[11px] font-semibold uppercase tracking-widest text-[var(--text-muted)]">
                    {activeProcessingCopy ? activeProcessingCopy.title : 'Ready for document review'}
                  </p>
                </div>

                {/* Action Buttons row */}
                <div className="flex w-full shrink-0 flex-wrap items-center gap-2 sm:w-auto">
                  {isCanonicalIntake ? (
                    <>
                      <Badge variant="muted" fixedWidth="lg">Canonical intake</Badge>
                      {activeCanonicalActions.canPreview && (
                        <Button type="button" variant="outline" size="sm" ref={viewPdfButtonRef} onClick={handleViewDocument}>
                          <ExternalLink size={12} aria-hidden="true" /> View PDF
                        </Button>
                      )}
                      {activeCanonicalActions.canAssign && (
                        <Button type="button" size="sm" ref={takeActionButtonRef} onClick={() => setIsActionModalOpen(true)}>
                          <Zap size={13} aria-hidden="true" /> Assign to matter
                        </Button>
                      )}
                      {activeCanonicalActions.canDiscard && !activeCanonicalActions.canAssign && (
                        <Button type="button" variant="destructive" size="sm" onClick={() => setIsDiscardConfirmOpen(true)}>
                          <Trash2 size={13} aria-hidden="true" /> Discard intake
                        </Button>
                      )}
                    </>
                  ) : (
                    <>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    ref={viewPdfButtonRef}
                    onClick={handleViewDocument}
                  >
                    <ExternalLink size={12} aria-hidden="true" /> View PDF
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    ref={takeActionButtonRef}
                    onClick={() => setIsActionModalOpen(true)}
                    disabled={Boolean(activeProcessingCopy)}
                  >
                    <Zap size={13} aria-hidden="true" /> Take Action
                  </Button>
                    </>
                  )}
                </div>
              </header>

              <div className="min-h-0 flex-1 overflow-visible py-3 lg:overflow-y-auto custom-scrollbar">
              <div className="flex flex-col gap-5">
              {/* ── State panels ── */}
              {isCanonicalIntake ? (
                <div className={cn(
                  'flex flex-col items-center justify-center rounded-[var(--radius-md)] border px-5 py-12 text-center',
                  activeDoc.status === 'failed'
                    ? 'border-[color-mix(in_srgb,var(--danger)_28%,transparent)] bg-[var(--danger-muted)]'
                    : isDuplicate
                    ? 'border-[color-mix(in_srgb,var(--warning)_28%,transparent)] bg-[var(--warning-muted)]'
                    : 'border-[var(--border)] bg-[var(--surface)]',
                )}>
                  <div className={cn(
                    'flex h-14 w-14 items-center justify-center rounded-[var(--radius-md)]',
                    activeDoc.status === 'failed'
                      ? 'bg-[var(--surface)] text-[var(--danger)]'
                      : isDuplicate
                      ? 'bg-[var(--surface)] text-[var(--warning)]'
                      : 'bg-[var(--accent-muted)] text-[var(--primary)]',
                  )}>
                    {activeDoc.status === 'failed'
                      ? <AlertTriangle size={24} />
                      : isDuplicate
                      ? <Copy size={24} />
                      : <Inbox size={24} />}
                  </div>
                  <h3 className="mt-4 text-[15px] font-bold text-[var(--text-primary)]">
                    {activeDoc.status === 'failed'
                      ? 'Canonical intake failed'
                      : isDuplicate
                      ? 'Duplicate PDF'
                      : activeDoc.canonical_intake_state === 'ready'
                      ? 'Ready for placement'
                      : 'Processing canonical intake'}
                  </h3>
                  <p className="mt-1.5 max-w-sm text-[13px] text-[var(--text-secondary)]">
                    {activeDoc.status === 'failed' || isDuplicate
                      ? activeDoc.suggestion_reason
                      : activeDoc.canonical_intake_state === 'ready'
                      ? 'This PDF passed validation. Preview it or assign it to an existing matter without copying the source file.'
                      : 'This PDF is being processed through the canonical private asset pipeline. Use Refresh queue to check for an updated state.'}
                  </p>
                  {activeCanonicalActions.canAssign && (
                    <Button type="button" className="mt-5" onClick={() => setIsActionModalOpen(true)}>
                      <Zap size={14} aria-hidden="true" /> Assign to matter
                    </Button>
                  )}
                  {activeCanonicalActions.canDiscard && (
                    <Button type="button" variant="destructive" className="mt-5" onClick={() => setIsDiscardConfirmOpen(true)}>
                      <Trash2 size={14} aria-hidden="true" /> Discard intake
                    </Button>
                  )}
                  {isDuplicate && (
                    <Button type="button" variant="outline" className="mt-5" onClick={handleOpenCanonicalDuplicate}>
                      <ExternalLink size={14} aria-hidden="true" /> Find matching document
                    </Button>
                  )}
                  {activeDoc.status === 'failed' && (
                    <Button type="button" variant="outline" className="mt-5" onClick={() => { router.refresh(); toast.info('Refreshing the queue for the latest recovery state.') }}>
                      <RefreshCw size={14} aria-hidden="true" /> Refresh queue
                    </Button>
                  )}
                </div>
              ) : activeProcessingCopy ? (
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
                      <div className="mt-0.5 text-[12px] text-[var(--text-secondary)]">Retrying this legacy staging item is unavailable. Assign it manually or use the canonical intake workflow.</div>
                    </div>
                  </div>
                  <div className="p-4 flex flex-col gap-3">
                    <p className="text-[13px] text-[var(--text-secondary)] leading-relaxed">
                      {activeDoc.suggestion_reason || 'An unknown error occurred during extraction.'}
                    </p>
                    <div className="flex flex-wrap gap-2">
                      <Button
                        type="button"
                        variant="default"
                        size="sm"
                        onClick={() => setIsActionModalOpen(true)}
                      >
                        <FolderPlus size={12} aria-hidden="true" />
                        Assign Manually
                      </Button>
                    </div>
                  </div>
                </div>
              ) : !hasExtractedMetadata ? (
                <div className="flex flex-col items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] py-14 text-center">
                  <AlertCircle size={28} className="text-[var(--text-muted)] mb-3" />
                  <h3 className="text-[14px] font-semibold text-[var(--text-primary)]">No data could be extracted</h3>
                  <p className="text-[13px] text-[var(--text-muted)] mt-1 max-w-xs">AI could not identify key fields from this document. Assign it manually.</p>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() => setIsActionModalOpen(true)}
                    className="mt-4"
                  >
                    Assign Manually
                  </Button>
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
                        className="h-7 shrink-0 rounded-[var(--radius-sm)] bg-[var(--success)] px-3 text-[11px] font-medium text-[var(--on-success)] transition-colors hover:opacity-90"
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
                          <span className="ml-auto text-[10px] font-bold px-2 py-0.5 rounded-[var(--radius-sm)] bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] text-[var(--primary)]">
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
                          <div key={label} className="flex flex-col gap-1 p-2.5 rounded-[var(--radius-md)] bg-[var(--surface-hover)]">
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
                              <Sparkles size={13} className="text-[var(--accent)] shrink-0" />
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
                            <div className="mt-3 text-[13px] text-[var(--text-secondary)] leading-relaxed bg-[var(--surface-hover)] p-4 rounded-[var(--radius-md)] border border-[var(--border)] animate-in fade-in duration-150">
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
                                <div key={key} className="flex flex-col p-3 rounded-[var(--radius-md)] bg-[var(--surface-hover)] border border-[var(--border)]">
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
            </div>
            </>
          ) : (
            <div className="flex h-full flex-col items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] px-6 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-[var(--radius-md)] bg-[var(--surface-hover)] text-[var(--text-muted)]">
                <FileText size={22} aria-hidden="true" />
              </div>
              <h3 className="mt-4 text-base font-semibold text-[var(--text-primary)]">Select a document</h3>
              <p className="mt-1 max-w-sm text-sm leading-6 text-[var(--text-muted)]">Review extracted details, processing state, and routing suggestions for the selected queue item.</p>
            </div>
          )}
        </section>
      </div>
      )}

      {/* ── Assignment dialog ── */}
      <Dialog
        open={isActionModalOpen && Boolean(activeDoc)}
        onOpenChange={(open) => {
          if (open) {
            setIsActionModalOpen(true)
          } else if (!isPending) {
            setIsActionModalOpen(false)
          }
        }}
      >
        {activeDoc && (
          <DialogContent
            showClose={false}
            className="max-h-[calc(100dvh-2rem)] w-full max-w-[calc(100vw-2rem)] overflow-y-auto custom-scrollbar p-0 sm:max-w-[460px]"
            onEscapeKeyDown={(event) => {
              if (isPending) event.preventDefault()
            }}
            onPointerDownOutside={(event) => {
              if (isPending) event.preventDefault()
            }}
            onCloseAutoFocus={(event) => {
              event.preventDefault()
              takeActionButtonRef.current?.focus()
            }}
          >
            <div className="h-1 w-full shrink-0 bg-[var(--primary)]" />

            <DialogHeader className="mb-0 flex-row items-start gap-3 p-5 pb-3">
              <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)]">
                <Zap size={18} className="text-[var(--primary)]" aria-hidden="true" />
              </div>
              <div className="min-w-0">
                <DialogTitle className="text-[17px] leading-none">Assign Document</DialogTitle>
                <DialogDescription className="mt-1 text-[13px]">Route this document to a matter timeline</DialogDescription>
              </div>
            </DialogHeader>

            <div className="flex flex-col gap-4 px-5 pb-5">
              {/* Document name chip */}
              <div className="flex items-center gap-2 px-3 py-2 rounded-[var(--radius-md)] bg-[var(--surface-hover)] border border-[var(--border)]">
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
              <div className="flex flex-col gap-2">
                {/* Primary: Confirm Assignment */}
                <Button
                  type="button"
                  variant="default"
                  size="md"
                  onClick={handleAssign}
                  disabled={!selectedMatterId || isPending}
                  loading={isPending}
                  className="w-full"
                >
                  {!isPending && <Check size={16} aria-hidden="true" />}
                  Confirm Assignment
                </Button>

                {/* Auto-create */}
                {!isCanonicalIntake && activeDoc.status !== 'failed' && (!activeDoc.suggested_matter || matters.length === 0) && !preselectedMatterId && (
                  <div className="flex flex-col gap-2 mt-1">
                    {activeDoc.raw_metadata?.financial_years && activeDoc.raw_metadata.financial_years.length > 1 && (
                      <div className="flex flex-col gap-1.5 p-3 rounded-[var(--radius-md)] border border-[var(--primary)]/20 bg-[var(--primary)]/5">
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
                    <Button
                      type="button"
                      variant="outline"
                      size="md"
                      onClick={handleAutoCreate}
                      disabled={isPending || (activeDoc.raw_metadata?.financial_years?.length > 1 && !selectedFyToCreate)}
                      loading={isPending}
                      className="w-full"
                    >
                      {!isPending && <FolderPlus size={14} aria-hidden="true" />}
                      Auto-Create Client & Matter
                    </Button>
                  </div>
                )}

                {(!isCanonicalIntake || activeCanonicalActions.canDiscard) && (
                  <Button
                    type="button"
                    variant="destructive"
                    size="md"
                    onClick={() => setIsDiscardConfirmOpen(true)}
                    disabled={isPending}
                    className="w-full"
                  >
                    <Trash2 size={13} aria-hidden="true" /> {isCanonicalIntake ? 'Discard intake' : 'Discard Document'}
                  </Button>
                )}
              </div>

              <DialogFooter className="mt-0 flex-col gap-2 border-t border-[var(--border)] p-0 pt-4 sm:flex-row sm:justify-end">
                <Button
                  type="button"
                  variant="ghost"
                  size="md"
                  onClick={() => setIsActionModalOpen(false)}
                  disabled={isPending}
                  className="w-full sm:w-auto"
                >
                  Cancel
                </Button>
              </DialogFooter>
            </div>
          </DialogContent>
        )}
      </Dialog>

      <ConfirmDialog
        isOpen={isDiscardConfirmOpen}
        onClose={() => setIsDiscardConfirmOpen(false)}
        onConfirm={handleDiscard}
        title={isCanonicalIntake ? 'Discard intake?' : 'Discard Document?'}
        description={isCanonicalIntake
          ? 'This will remove the unassigned intake from the Inbox and schedule its private source file for secure cleanup.'
          : 'Are you sure you want to discard this document? It will be permanently deleted from the staging queue.'}
        confirmText={isCanonicalIntake ? 'Discard intake' : 'Discard Document'}
        variant="destructive"
        isPending={isPending}
      />

      {viewDocumentUrl && activeDoc && (
        <DocumentViewerModal
          url={viewDocumentUrl}
          title={activeDoc.storage_path.split('/').pop()}
          onClose={() => setViewDocumentUrl(null)}
          returnFocusRef={viewPdfButtonRef}
        />
      )}
    </div>
  )
}
