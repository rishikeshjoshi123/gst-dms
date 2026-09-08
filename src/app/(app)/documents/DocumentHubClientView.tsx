'use client'

import { useEffect, useMemo, useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  AlertCircle,
  ArrowLeft,
  Check,
  Copy,
  ExternalLink,
  FileSearch,
  FileText,
  Inbox,
  Loader2,
  RefreshCw,
  Search,
  Trash2,
  Upload,
  X,
} from 'lucide-react'
import { toast } from 'sonner'

import { UploadModal } from '../inbox/UploadModal'
import { useBreadcrumbs } from '@/components/nav/BreadcrumbContext'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { canonicalDocumentPath } from '@/lib/canonical-document-route'
import { documentHubPath } from '@/lib/document-hub-route'
import {
  assignCanonicalIntakeToMatter,
  discardCanonicalIntake,
  getCanonicalDuplicateResolution,
  getStagedDocuments,
  type InboxQueueDocument,
} from '@/lib/actions/inbox'
import { getIntakeItemSignedUrl } from '@/lib/actions/document'
import { canonicalIntakeActions } from '@/lib/inbox-compat'
import { reconcileInboxQueue } from '@/lib/inbox-queue-read'
import { cn } from '@/lib/utils'

type MatterOption = {
  id: string
  title: string | null
  matter_code: string | null
  financial_year: string | null
  clients: { name: string | null } | null
}

type DetailTab = 'overview' | 'placement'

type DocumentHubClientViewProps = {
  initialDocuments: InboxQueueDocument[]
  initialQueueError: string | null
  matters: MatterOption[]
  preselectedMatterId?: string
  preselectedIntakeId?: string
}

type StatusPresentation = {
  label: string
  variant: 'default' | 'success' | 'warning' | 'danger' | 'muted'
  icon: typeof FileText
}

function uniqueDocuments(documents: InboxQueueDocument[]) {
  return Array.from(new Map(documents.map((document) => [document.id, document])).values())
}

function fileName(document: InboxQueueDocument) {
  return document.storage_path.split('/').pop() || 'Untitled PDF'
}

function statusPresentation(document: InboxQueueDocument): StatusPresentation {
  switch (document.canonical_intake_state) {
    case 'uploaded':
    case 'validating':
    case 'processing':
      return { label: 'Processing', variant: 'default', icon: Loader2 }
    case 'ready':
      return { label: 'Ready', variant: 'success', icon: Check }
    case 'duplicate':
      return { label: 'Duplicate', variant: 'warning', icon: Copy }
    case 'failed':
      return { label: 'Failed', variant: 'danger', icon: AlertCircle }
    default:
      return { label: 'Queued', variant: 'muted', icon: Inbox }
  }
}

function StatusBadge({ document }: { document: InboxQueueDocument }) {
  const status = statusPresentation(document)
  const Icon = status.icon

  return (
    <Badge variant={status.variant} fixedWidth="xl">
      <Icon
        className={cn(
          'size-3.5',
          status.label === 'Processing' && 'animate-spin motion-reduce:animate-none',
        )}
        aria-hidden="true"
      />
      {status.label}
    </Badge>
  )
}

function formatReceivedAt(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'Date unavailable'

  return new Intl.DateTimeFormat('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Asia/Kolkata',
    timeZoneName: 'short',
  }).format(date)
}

function matterLabel(matter: MatterOption | undefined) {
  if (!matter) return 'Matter unavailable'
  const identity = [matter.clients?.name, matter.title].filter(Boolean).join(' · ')
  return matter.matter_code ? `${identity} · ${matter.matter_code}` : identity || 'Untitled matter'
}

function intakeStateCopy(document: InboxQueueDocument) {
  switch (document.canonical_intake_state) {
    case 'awaiting_upload':
      return {
        heading: 'Waiting for the PDF',
        body: 'The upload has been reserved but its file transfer is not yet complete.',
      }
    case 'uploaded':
      return {
        heading: 'Upload received',
        body: 'The PDF is waiting for validation in the private document pipeline.',
      }
    case 'validating':
      return {
        heading: 'Validating the PDF',
        body: 'The file is being checked before document processing continues.',
      }
    case 'processing':
      return {
        heading: 'Processing the document',
        body: 'Document processing is running in the background. No action is required yet.',
      }
    case 'ready':
      return {
        heading: 'Ready for placement',
        body: 'The PDF is available to preview and can be assigned to an existing matter.',
      }
    case 'duplicate':
      return {
        heading: 'Identical PDF found',
        body: document.suggestion_reason || 'This PDF already exists and was not added again.',
      }
    case 'failed':
      return {
        heading: 'Intake could not finish',
        body: document.suggestion_reason || 'This intake could not be completed.',
      }
    default:
      return {
        heading: 'Queued for intake',
        body: 'The document is waiting for the canonical intake pipeline to begin.',
      }
  }
}

export function DocumentHubClientView({
  initialDocuments,
  initialQueueError,
  matters,
  preselectedMatterId,
  preselectedIntakeId,
}: DocumentHubClientViewProps) {
  const [documents, setDocuments] = useState(() => uniqueDocuments(initialDocuments))
  const [selectedId, setSelectedId] = useState<string | null>(() =>
    initialDocuments.some((document) => document.id === preselectedIntakeId)
      ? preselectedIntakeId ?? null
      : null,
  )
  const [selectedMatterId, setSelectedMatterId] = useState('')
  const [detailTab, setDetailTab] = useState<DetailTab>('overview')
  const [query, setQuery] = useState('')
  const [sourceUrl, setSourceUrl] = useState<string | null>(null)
  const [isSourcePending, setIsSourcePending] = useState(false)
  const [sourceError, setSourceError] = useState<string | null>(null)
  const [refreshError, setRefreshError] = useState<string | null>(initialQueueError)
  const [actionError, setActionError] = useState<string | null>(null)
  const [isRefreshing, setIsRefreshing] = useState(false)
  const [isUploadOpen, setIsUploadOpen] = useState(false)
  const [isDiscardOpen, setIsDiscardOpen] = useState(false)
  const [renderedQueueProps, setRenderedQueueProps] = useState({ initialDocuments, initialQueueError })
  const [isActionPending, startActionTransition] = useTransition()
  const uploadButtonRef = useRef<HTMLButtonElement>(null)
  const sourceButtonRef = useRef<HTMLButtonElement>(null)
  const selectedIdRef = useRef(selectedId)
  const sourceRequestGeneration = useRef(0)
  const actionKeys = useRef(new Map<string, string>())
  const router = useRouter()
  const { setBreadcrumbs } = useBreadcrumbs()

  const matterById = useMemo(
    () => new Map(matters.map((matter) => [matter.id, matter])),
    [matters],
  )
  const selectedDocument = documents.find((document) => document.id === selectedId) ?? null
  const selectedActions = canonicalIntakeActions(selectedDocument?.canonical_intake_state ?? '')
  const selectedMatterContext = preselectedMatterId
    ? matterById.get(preselectedMatterId)
    : undefined

  useEffect(() => {
    selectedIdRef.current = selectedId
  }, [selectedId])

  if (
    renderedQueueProps.initialDocuments !== initialDocuments
    || renderedQueueProps.initialQueueError !== initialQueueError
  ) {
    setRenderedQueueProps({ initialDocuments, initialQueueError })
    if (initialQueueError) {
      setRefreshError(`${initialQueueError} Showing the last loaded documents.`)
    } else {
      setRefreshError(null)
      setDocuments(uniqueDocuments(initialDocuments))
    }
  }

  useEffect(() => {
    if (preselectedMatterId && selectedMatterContext) {
      setBreadcrumbs([
        { label: 'Matters', href: '/matters' },
        { label: selectedMatterContext.title || 'Matter', href: `/matters/${preselectedMatterId}` },
        { label: 'Document Hub' },
      ])
      return
    }
    setBreadcrumbs([{ label: 'Document Hub' }])
  }, [preselectedMatterId, selectedMatterContext, setBreadcrumbs])

  useEffect(() => {
    if (preselectedIntakeId && documents.some((document) => document.id === preselectedIntakeId)) {
      // Synchronize URL-owned selection after an RSC navigation.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setSelectedId(preselectedIntakeId)
      return
    }
    if (preselectedIntakeId && !documents.some((document) => document.id === preselectedIntakeId)) {
      setSelectedId(null)
    }
  }, [documents, preselectedIntakeId])

  useEffect(() => {
    if (!selectedDocument) {
      // Clear the dependent form control when the selected subject disappears.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setSelectedMatterId('')
      return
    }
    const intendedMatter = selectedDocument.intake_matter_id
    setSelectedMatterId(intendedMatter && matterById.has(intendedMatter) ? intendedMatter : '')
  }, [matterById, selectedDocument])

  const filteredDocuments = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase()
    if (!normalizedQuery) return documents

    return documents.filter((document) => {
      const intendedMatter = document.intake_matter_id
        ? matterLabel(matterById.get(document.intake_matter_id))
        : 'Not set'
      return [fileName(document), intendedMatter, document.suggestion_reason, formatReceivedAt(document.created_at)]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(normalizedQuery)
    })
  }, [documents, matterById, query])

  function actionKey(kind: 'assign' | 'discard', intakeId: string) {
    const mapKey = `${kind}:${intakeId}`
    const existing = actionKeys.current.get(mapKey)
    if (existing) return existing
    const next = crypto.randomUUID()
    actionKeys.current.set(mapKey, next)
    return next
  }

  function updateSelectionInUrl(intakeId?: string) {
    router.replace(documentHubPath({ matterId: preselectedMatterId, intakeId }), { scroll: false })
  }

  function selectDocument(document: InboxQueueDocument) {
    sourceRequestGeneration.current += 1
    selectedIdRef.current = document.id
    setIsSourcePending(false)
    setSelectedId(document.id)
    setDetailTab('overview')
    setSourceUrl(null)
    setSourceError(null)
    setActionError(null)
    updateSelectionInUrl(document.id)
  }

  function closeDetails() {
    sourceRequestGeneration.current += 1
    selectedIdRef.current = null
    setIsSourcePending(false)
    setSelectedId(null)
    setDetailTab('overview')
    setSourceUrl(null)
    setSourceError(null)
    setActionError(null)
    updateSelectionInUrl()
  }

  function closeSource() {
    sourceRequestGeneration.current += 1
    setIsSourcePending(false)
    setSourceUrl(null)
    setSourceError(null)
    window.requestAnimationFrame(() => sourceButtonRef.current?.focus())
  }

  async function refreshQueue() {
    setIsRefreshing(true)
    setRefreshError(null)
    try {
      const result = await getStagedDocuments()
      const reconciled = reconcileInboxQueue(documents, result)
      setRefreshError(reconciled.error)
      setDocuments(reconciled.documents)
      if (result.ok && selectedId && !reconciled.documents.some((document) => document.id === selectedId)) {
        closeDetails()
      }
    } catch (error) {
      setRefreshError(
        error instanceof Error
          ? error.message
          : 'The queue could not be refreshed. Showing the last loaded documents.',
      )
    } finally {
      setIsRefreshing(false)
    }
  }

  async function openSource() {
    if (!selectedDocument || !selectedActions.canPreview) return
    const subjectId = selectedDocument.id
    const generation = sourceRequestGeneration.current + 1
    sourceRequestGeneration.current = generation
    setIsSourcePending(true)
    setSourceError(null)
    try {
      const result = await getIntakeItemSignedUrl(selectedDocument.id)
      if (sourceRequestGeneration.current !== generation || selectedIdRef.current !== subjectId) return
      if (result.error || !result.url) {
        setSourceError(result.error || 'The PDF could not be opened.')
        return
      }
      setSourceUrl(result.url)
    } catch (error) {
      if (sourceRequestGeneration.current !== generation || selectedIdRef.current !== subjectId) return
      setSourceError(error instanceof Error ? error.message : 'The PDF could not be opened.')
    } finally {
      if (sourceRequestGeneration.current === generation) setIsSourcePending(false)
    }
  }

  function assignDocument() {
    if (!selectedDocument || !selectedMatterId || !selectedActions.canAssign) return
    const intakeId = selectedDocument.id
    setActionError(null)
    startActionTransition(async () => {
      const result = await assignCanonicalIntakeToMatter(
        intakeId,
        selectedMatterId,
        actionKey('assign', intakeId),
      )
      if (result.error) {
        setActionError(result.error)
        return
      }

      actionKeys.current.delete(`assign:${intakeId}`)
      const remainingDocuments = documents.filter((document) => document.id !== intakeId)
      setDocuments(remainingDocuments)
      closeDetails()
      toast.success('Document assigned to the matter')

      try {
        const result = await getStagedDocuments()
        const reconciled = reconcileInboxQueue(remainingDocuments, result)
        if (reconciled.error) {
          setRefreshError(`Assignment completed. ${reconciled.error}`)
          return
        }
        setDocuments(reconciled.documents)
      } catch {
        setRefreshError('Assignment completed. The remaining queue could not be refreshed, so the last loaded items are still shown.')
      }
      router.refresh()
    })
  }

  function discardDocument() {
    if (!selectedDocument || !selectedActions.canDiscard) return
    const intakeId = selectedDocument.id
    setActionError(null)
    startActionTransition(async () => {
      const result = await discardCanonicalIntake(intakeId, actionKey('discard', intakeId))
      if (result.error) {
        setActionError(result.error)
        setIsDiscardOpen(false)
        return
      }

      actionKeys.current.delete(`discard:${intakeId}`)
      setDocuments((current) => current.filter((document) => document.id !== intakeId))
      setIsDiscardOpen(false)
      closeDetails()
      toast.success('Upload discarded')
      router.refresh()
    })
  }

  function openDuplicate() {
    if (!selectedDocument || selectedDocument.canonical_intake_state !== 'duplicate') return
    setActionError(null)
    startActionTransition(async () => {
      const result = await getCanonicalDuplicateResolution(selectedDocument.id)
      if (result.code === 'ok') {
        router.push(canonicalDocumentPath(result.documentId))
        return
      }
      if (result.code === 'intake') {
        updateSelectionInUrl(result.intakeId)
        return
      }

      const message = result.code === 'in_trash'
        ? 'The matching document is in Trash and must be restored before it can be used.'
        : result.code === 'restricted'
          ? 'A matching document exists, but its details are not available to you.'
          : 'The matching document is not available. Refresh the queue and try again.'
      setActionError(message)
    })
  }

  const queueWorkbar = (
    <header className="flex min-h-14 shrink-0 flex-col gap-2 border-b border-[var(--border)] bg-[var(--surface)] p-3 sm:flex-row sm:items-center">
      <div className="relative min-w-0 flex-1">
        <Label htmlFor="document-hub-search" className="sr-only">Search document queue</Label>
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
        <Input
          id="document-hub-search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search documents"
          className="h-11 pl-9 sm:h-9"
        />
      </div>
      <p className="shrink-0 text-xs text-[var(--text-muted)]" aria-live="polite">
        {filteredDocuments.length} of {documents.length} documents
      </p>
      <div className="flex shrink-0 items-center gap-2">
        <Button type="button" variant="outline" onClick={refreshQueue} loading={isRefreshing}>
          {!isRefreshing && <RefreshCw className="size-4" aria-hidden="true" />}
          Refresh queue
        </Button>
        <Button ref={uploadButtonRef} type="button" onClick={() => setIsUploadOpen(true)}>
          <Upload className="size-4" aria-hidden="true" />
          Upload PDFs
        </Button>
      </div>
    </header>
  )

  const queueTable = (
    <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain" style={{ scrollbarGutter: 'stable' }}>
      {refreshError && (
        <div role="alert" className="m-3 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--warning)_28%,transparent)] bg-[var(--warning-muted)] p-3 text-sm text-[var(--text-secondary)]">
          <AlertCircle className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" aria-hidden="true" />
          <span>{refreshError}</span>
        </div>
      )}
      {filteredDocuments.length === 0 ? (
        <div className="flex min-h-64 items-center justify-center p-6 text-center">
          <div>
            <Search className="mx-auto size-6 text-[var(--text-muted)]" aria-hidden="true" />
            <h2 className="mt-3 text-section-heading">No matching documents</h2>
            <p className="mt-1 text-body text-[var(--text-muted)]">Clear the search to return to the full queue.</p>
            <Button type="button" variant="outline" className="mt-4" onClick={() => setQuery('')}>Clear search</Button>
          </div>
        </div>
      ) : (
        <>
          <div className="hidden lg:block">
            <Table>
              <TableCaption>Accessible document intake queue.</TableCaption>
              <TableHeader sticky>
                <TableRow>
                  <TableHead>Document</TableHead>
                  <TableHead className="w-36">Status</TableHead>
                  <TableHead className={cn('min-w-48', selectedDocument && 'hidden')}>Intended matter</TableHead>
                  <TableHead className={cn('min-w-56', selectedDocument && 'hidden')}>Reason</TableHead>
                  <TableHead className={cn('w-44', selectedDocument && 'hidden')}>Received</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredDocuments.map((document) => {
                  const isSelected = document.id === selectedId
                  const intendedMatter = document.intake_matter_id
                    ? matterLabel(matterById.get(document.intake_matter_id))
                    : 'Not set'
                  return (
                    <TableRow key={document.id} interactive selected={isSelected}>
                      <TableCell className="min-w-0">
                        <button
                          type="button"
                          onClick={() => selectDocument(document)}
                          className="touch-target block min-w-0 max-w-full rounded-[var(--radius-sm)] text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
                          aria-label={`View details for ${fileName(document)}`}
                        >
                          <span className="block truncate font-medium text-[var(--text-primary)]" title={fileName(document)}>{fileName(document)}</span>
                          {selectedDocument && (
                            <span className="mt-1 block truncate text-xs text-[var(--text-muted)]" title={intendedMatter}>{intendedMatter}</span>
                          )}
                        </button>
                      </TableCell>
                      <TableCell><StatusBadge document={document} /></TableCell>
                      <TableCell className={cn('text-sm text-[var(--text-secondary)]', selectedDocument && 'hidden')}>
                        <span className="block max-w-72 truncate" title={intendedMatter}>{intendedMatter}</span>
                      </TableCell>
                      <TableCell className={cn('text-sm text-[var(--text-secondary)]', selectedDocument && 'hidden')}>
                        <span className="line-clamp-2">{document.suggestion_reason || '—'}</span>
                      </TableCell>
                      <TableCell className={cn('whitespace-nowrap text-xs text-[var(--text-muted)]', selectedDocument && 'hidden')}>
                        {formatReceivedAt(document.created_at)}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div className="divide-y divide-[var(--border-subtle)] lg:hidden">
            {filteredDocuments.map((document) => {
              const intendedMatter = document.intake_matter_id
                ? matterLabel(matterById.get(document.intake_matter_id))
                : 'Not set'
              return (
                <button
                  key={document.id}
                  type="button"
                  onClick={() => selectDocument(document)}
                  className="flex min-h-24 w-full items-start gap-3 bg-[var(--surface)] p-4 text-left transition-colors duration-[var(--duration-fast)] ease-[var(--ease-smooth)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]"
                  aria-label={`View details for ${fileName(document)}`}
                >
                  <span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]">
                    <FileText className="size-5" aria-hidden="true" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium text-[var(--text-primary)]">{fileName(document)}</span>
                    <span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{intendedMatter}</span>
                    <span className="mt-1 block text-xs text-[var(--text-muted)]">{formatReceivedAt(document.created_at)}</span>
                    {document.suggestion_reason && <span className="mt-1 line-clamp-2 block text-xs text-[var(--text-secondary)]">{document.suggestion_reason}</span>}
                  </span>
                  <StatusBadge document={document} />
                </button>
              )
            })}
          </div>
        </>
      )}
    </div>
  )

  const sourcePane = selectedDocument && sourceUrl ? (
    <section aria-label={`Original PDF for ${fileName(selectedDocument)}`} className="flex h-full min-h-0 flex-col bg-[var(--surface)]">
      <header className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border)] px-3">
        <Button type="button" variant="ghost" onClick={closeSource} className="lg:hidden">
          <ArrowLeft className="size-4" aria-hidden="true" />
          Back to details
        </Button>
        <div className="hidden min-w-0 flex-1 items-center gap-2 lg:flex">
          <FileText className="size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
          <span className="truncate text-sm font-medium">{fileName(selectedDocument)}</span>
        </div>
        <Button type="button" variant="ghost" onClick={closeSource} className="ml-auto hidden lg:inline-flex">
          <X className="size-4" aria-hidden="true" />
          Close PDF
        </Button>
      </header>
      <div className="min-h-0 flex-1 overflow-hidden bg-[var(--bg-overlay)]">
        <PdfViewer url={sourceUrl} />
      </div>
    </section>
  ) : null

  const detailPane = selectedDocument ? (
    <aside aria-label={`Details for ${fileName(selectedDocument)}`} className={cn(
      'min-h-0 flex-1 flex-col overflow-hidden border-[var(--border)] bg-[var(--surface)]',
      sourceUrl ? 'hidden lg:flex' : 'flex',
      'lg:w-2/5 lg:flex-none lg:border-l',
    )}>
      <div className="flex min-h-12 shrink-0 items-center border-b border-[var(--border)] px-2 lg:hidden">
        <Button type="button" variant="ghost" onClick={closeDetails}>
          <ArrowLeft className="size-4" aria-hidden="true" />
          Back to documents
        </Button>
      </div>
      <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
        <div className="flex min-h-16 items-center gap-3 px-3">
          <span className="flex size-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]">
            <FileText className="size-5" aria-hidden="true" />
          </span>
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-section-heading text-[var(--text-primary)]" title={fileName(selectedDocument)}>
              {fileName(selectedDocument)}
            </h2>
            <p className="mt-0.5 text-caption text-[var(--text-muted)]">Canonical intake</p>
          </div>
          <StatusBadge document={selectedDocument} />
          <Button type="button" variant="ghost" onClick={closeDetails} className="hidden shrink-0 lg:inline-flex">
            <X className="size-4" aria-hidden="true" />
            Close details
          </Button>
        </div>
      </header>
      <div role="tablist" aria-label="Document detail sections" className="flex min-h-12 shrink-0 items-stretch border-b border-[var(--border)] bg-[var(--surface)]">
        <button
          type="button"
          role="tab"
          aria-selected={detailTab === 'overview'}
          onClick={() => setDetailTab('overview')}
          className={cn(
            'relative min-h-11 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]',
            detailTab === 'overview'
              ? 'text-[var(--text-primary)] after:absolute after:inset-x-4 after:bottom-0 after:h-0.5 after:bg-[var(--primary)]'
              : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]',
          )}
        >
          Overview
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={detailTab === 'placement'}
          onClick={() => setDetailTab('placement')}
          className={cn(
            'relative min-h-11 px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]',
            detailTab === 'placement'
              ? 'text-[var(--text-primary)] after:absolute after:inset-x-4 after:bottom-0 after:h-0.5 after:bg-[var(--primary)]'
              : 'text-[var(--text-muted)] hover:text-[var(--text-primary)]',
          )}
        >
          Placement
        </button>
      </div>

      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain p-4" style={{ scrollbarGutter: 'stable' }}>
        {detailTab === 'overview' ? (
          <div className="space-y-5">
            <section className="border-l-2 border-[var(--border-strong)] pl-4">
              <p className="text-caption uppercase tracking-[0.08em] text-[var(--text-muted)]">
                {['ready', 'duplicate', 'failed'].includes(selectedDocument.canonical_intake_state)
                  ? 'Decision required'
                  : 'No action needed'}
              </p>
              <h3 className="mt-1 text-sm font-semibold text-[var(--text-primary)]">{intakeStateCopy(selectedDocument).heading}</h3>
              <p className="mt-1 text-body text-[var(--text-secondary)]">{intakeStateCopy(selectedDocument).body}</p>
            </section>

            <section>
              <h3 className="text-caption uppercase tracking-[0.08em] text-[var(--text-muted)]">Intake details</h3>
              <dl className="mt-2 divide-y divide-[var(--border-subtle)] rounded-[var(--radius-md)] border border-[var(--border)]">
                <div className="grid gap-1 p-3 sm:grid-cols-[8rem_minmax(0,1fr)]">
                  <dt className="text-xs text-[var(--text-muted)]">Intended matter</dt>
                  <dd className="break-words text-sm text-[var(--text-primary)]">
                    {selectedDocument.intake_matter_id
                      ? matterLabel(matterById.get(selectedDocument.intake_matter_id))
                      : 'Not set'}
                  </dd>
                </div>
                <div className="grid gap-1 p-3 sm:grid-cols-[8rem_minmax(0,1fr)]">
                  <dt className="text-xs text-[var(--text-muted)]">Received</dt>
                  <dd className="text-sm text-[var(--text-primary)]">{formatReceivedAt(selectedDocument.created_at)}</dd>
                </div>
                <div className="grid gap-1 p-3 sm:grid-cols-[8rem_minmax(0,1fr)]">
                  <dt className="text-xs text-[var(--text-muted)]">Reason</dt>
                  <dd className="text-sm text-[var(--text-primary)]">{selectedDocument.suggestion_reason || 'No issue reported'}</dd>
                </div>
              </dl>
            </section>

            {selectedDocument.canonical_intake_state === 'duplicate' && (
              <Button type="button" variant="outline" onClick={openDuplicate} loading={isActionPending}>
                {!isActionPending && <ExternalLink className="size-4" aria-hidden="true" />}
                Find matching document
              </Button>
            )}

            {selectedActions.canDiscard && (
              <section className="border-t border-[var(--border)] pt-4">
                <h3 className="text-sm font-semibold text-[var(--text-primary)]">Remove from intake</h3>
                <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Discard this upload only if it should not be placed in a matter.</p>
                <Button type="button" variant="destructive" className="mt-2" onClick={() => setIsDiscardOpen(true)}>
                  <Trash2 className="size-4" aria-hidden="true" />
                  Discard upload
                </Button>
              </section>
            )}
          </div>
        ) : (
          <section className="space-y-4">
            <div>
              <h2 className="text-section-heading">Place in a matter</h2>
              <p className="mt-1 text-body text-[var(--text-secondary)]">
                Choose an existing accessible matter. The source PDF is not copied during placement.
              </p>
            </div>
            {selectedActions.canAssign ? (
              <div className="space-y-2">
                <Label htmlFor="document-hub-matter">Matter</Label>
                <select
                  id="document-hub-matter"
                  value={selectedMatterId}
                  onChange={(event) => setSelectedMatterId(event.target.value)}
                  className="min-h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-sm text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
                >
                  <option value="">Choose a matter</option>
                  {matters.map((matter) => (
                    <option key={matter.id} value={matter.id}>{matterLabel(matter)}</option>
                  ))}
                </select>
                {matters.length === 0 && (
                  <p className="text-xs leading-5 text-[var(--text-muted)]">No accessible active matters are available for assignment.</p>
                )}
              </div>
            ) : (
              <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-4">
                <p className="text-sm font-medium text-[var(--text-primary)]">Placement is not available yet</p>
                <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The current intake state does not allow assignment.</p>
              </div>
            )}
          </section>
        )}

        {(actionError || sourceError) && (
          <div role="alert" className="mt-4 flex items-start gap-2 rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--danger)_28%,transparent)] bg-[var(--danger-muted)] p-3 text-sm text-[var(--text-secondary)]">
            <AlertCircle className="mt-0.5 size-4 shrink-0 text-[var(--danger)]" aria-hidden="true" />
            <span>{actionError || sourceError}</span>
          </div>
        )}
      </div>

      <footer className="shrink-0 border-t border-[var(--border)] bg-[var(--surface)] p-3">
        <div className="flex flex-col gap-2 sm:flex-row sm:justify-end">
          {selectedActions.canPreview && (
            <Button ref={sourceButtonRef} type="button" variant="outline" onClick={openSource} loading={isSourcePending}>
              {!isSourcePending && <FileSearch className="size-4" aria-hidden="true" />}
              View original PDF
            </Button>
          )}
          {selectedActions.canAssign && (
            <Button type="button" onClick={assignDocument} loading={isActionPending} disabled={!selectedMatterId}>
              {!isActionPending && <Check className="size-4" aria-hidden="true" />}
              Assign document
            </Button>
          )}
        </div>
      </footer>
    </aside>
  ) : null

  return (
    <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      {selectedMatterContext && (
        <div className="mb-3 flex shrink-0 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-sm">
          <span className="text-[var(--text-muted)]">Upload destination</span>
          <span className="min-w-0 truncate font-medium">{matterLabel(selectedMatterContext)}</span>
          <Button
            type="button"
            variant="ghost"
            className="ml-auto shrink-0"
            onClick={() => router.replace(documentHubPath({ intakeId: selectedId ?? undefined }))}
          >
            <X className="size-4" aria-hidden="true" />
            Remove destination
          </Button>
        </div>
      )}

      {documents.length === 0 ? (
        <section className="flex min-h-0 flex-1 items-center justify-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6 text-center">
          <div className="max-w-md">
            <span className="mx-auto flex size-14 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)] text-[var(--primary)]">
              <Inbox className="size-6" aria-hidden="true" />
            </span>
            <h1 className="mt-4 text-page-title">No documents in intake</h1>
            <p className="mt-2 text-body text-[var(--text-muted)]">
              Upload PDF documents to start validation and place ready files in an existing matter.
            </p>
            <Button ref={uploadButtonRef} type="button" className="mt-5" onClick={() => setIsUploadOpen(true)}>
              <Upload className="size-4" aria-hidden="true" />
              Upload PDFs
            </Button>
          </div>
        </section>
      ) : (
        <div className="flex min-h-0 flex-1 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <section
            aria-label={sourceUrl && selectedDocument ? `PDF workspace for ${fileName(selectedDocument)}` : 'Document queue'}
            className={cn(
              'min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--surface)]',
              selectedDocument && !sourceUrl ? 'hidden lg:flex' : 'flex',
              selectedDocument ? 'lg:w-3/5 lg:flex-none' : 'lg:w-full lg:flex-1',
            )}
          >
            {sourcePane || <>{queueWorkbar}{queueTable}</>}
          </section>
          {detailPane}
        </div>
      )}

      {isUploadOpen && (
        <UploadModal
          onClose={() => setIsUploadOpen(false)}
          matterId={preselectedMatterId}
          matterName={selectedMatterContext?.title || undefined}
          returnFocusRef={uploadButtonRef}
        />
      )}

      <ConfirmDialog
        isOpen={isDiscardOpen}
        onClose={() => setIsDiscardOpen(false)}
        onConfirm={discardDocument}
        title="Discard upload?"
        description="This removes the unassigned intake item and schedules its private source file for secure cleanup."
        confirmText="Discard upload"
        variant="destructive"
        isPending={isActionPending}
      />
    </div>
  )
}
