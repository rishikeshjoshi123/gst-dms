'use client'

import { useCallback, useEffect, useMemo, useRef, useState, useTransition } from 'react'
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
import {
  searchMatterDestinations,
  type MatterDestinationOption,
} from '@/lib/actions/matter'
import { getIntakeItemSignedUrl } from '@/lib/actions/document'
import { canonicalIntakeActions } from '@/lib/inbox-compat'
import { reconcileInboxQueue } from '@/lib/inbox-queue-read'
import { freshnessLabel } from '@/lib/freshness'
import { cn } from '@/lib/utils'

type DetailTab = 'overview' | 'placement'

type DocumentHubClientViewProps = {
  initialDocuments: InboxQueueDocument[]
  initialQueueError: string | null
  initialQueueTotal: number
  initialNextOffset: number
  initialMatters: MatterDestinationOption[]
  initialMatterLookupError: string | null
  preselectedMatterId?: string
  preselectedIntakeId?: string
  currentUserId: string
  canManageIntake: boolean
}

type StatusPresentation = {
  label: string
  variant: 'default' | 'success' | 'warning' | 'danger' | 'muted'
  icon: typeof FileText
}

function uniqueDocuments(documents: InboxQueueDocument[]) {
  return Array.from(new Map(documents.map((document) => [document.id, document])).values())
}

function uniqueMatterOptions(matters: MatterDestinationOption[]) {
  return Array.from(new Map(matters.map((matter) => [matter.id, matter])).values())
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

function matterLabel(matter: MatterDestinationOption | undefined) {
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

export function DocumentHubClientView(props: DocumentHubClientViewProps) {
  if (!props.canManageIntake) {
    return (
      <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden bg-[var(--bg)] p-4 text-[var(--text-primary)]">
        <section className="mx-auto mt-8 w-full max-w-2xl rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6">
          <div className="flex items-start gap-3">
            <span className="flex size-11 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]">
              <Inbox className="size-5" aria-hidden="true" />
            </span>
            <div>
              <h1 className="text-section-heading">Document intake is not available</h1>
              <p className="mt-1 text-body text-[var(--text-secondary)]">
                Your access does not include unplaced uploads. Documents assigned to matters remain available from those matters.
              </p>
            </div>
          </div>
        </section>
      </div>
    )
  }

  return <ManagedDocumentHubClientView {...props} />
}

function ManagedDocumentHubClientView({
  initialDocuments,
  initialQueueError,
  initialQueueTotal,
  initialNextOffset,
  initialMatters,
  initialMatterLookupError,
  preselectedMatterId,
  preselectedIntakeId,
  currentUserId,
}: DocumentHubClientViewProps) {
  const [ownershipScope, setOwnershipScope] = useState<'mine' | 'all'>('mine')
  const [documents, setDocuments] = useState(() => uniqueDocuments(initialDocuments))
  const [queueTotal, setQueueTotal] = useState(initialQueueTotal)
  const [nextOffset, setNextOffset] = useState(initialNextOffset)
  const [isLoadingMore, setIsLoadingMore] = useState(false)
  const [matterOptions, setMatterOptions] = useState(initialMatters)
  const [destinationMatches, setDestinationMatches] = useState<MatterDestinationOption[]>([])
  const [destinationQuery, setDestinationQuery] = useState('')
  const [isDestinationPending, setIsDestinationPending] = useState(false)
  const [matterLookupError, setMatterLookupError] = useState<string | null>(initialMatterLookupError)
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
  const [lastSuccessfulRefreshAt, setLastSuccessfulRefreshAt] = useState<number | null>(
    () => initialQueueError ? null : Date.now(),
  )
  const [freshnessClock, setFreshnessClock] = useState(() => Date.now())
  const [isOffline, setIsOffline] = useState(false)
  const [isUploadOpen, setIsUploadOpen] = useState(false)
  const [isDiscardOpen, setIsDiscardOpen] = useState(false)
  const [renderedQueueProps, setRenderedQueueProps] = useState({
    initialDocuments,
    initialQueueError,
    initialQueueTotal,
    initialNextOffset,
    initialMatters,
    initialMatterLookupError,
  })
  const [isActionPending, startActionTransition] = useTransition()
  const uploadButtonRef = useRef<HTMLButtonElement>(null)
  const sourceButtonRef = useRef<HTMLButtonElement>(null)
  const selectedIdRef = useRef(selectedId)
  const documentsRef = useRef(documents)
  const ownershipScopeRef = useRef<'mine' | 'all'>('mine')
  const loadedPageOffsetsRef = useRef([0])
  const sourceRequestGeneration = useRef(0)
  const queueRequestGeneration = useRef(0)
  const destinationRequestGeneration = useRef(0)
  const placementSubjectRef = useRef<string | null>(selectedId)
  const actionKeys = useRef(new Map<string, string>())
  const router = useRouter()
  const { setBreadcrumbs } = useBreadcrumbs()

  const matterById = useMemo(
    () => new Map(matterOptions.map((matter) => [matter.id, matter])),
    [matterOptions],
  )
  const selectedDocument = documents.find((document) => document.id === selectedId) ?? null
  const selectedActions = canonicalIntakeActions(selectedDocument?.canonical_intake_state ?? '')
  const selectedMatterContext = preselectedMatterId
    ? matterById.get(preselectedMatterId)
    : undefined

  useEffect(() => {
    selectedIdRef.current = selectedId
  }, [selectedId])

  useEffect(() => {
    documentsRef.current = documents
  }, [documents])

  useEffect(() => {
    ownershipScopeRef.current = ownershipScope
  }, [ownershipScope])

  if (
    renderedQueueProps.initialDocuments !== initialDocuments
    || renderedQueueProps.initialQueueError !== initialQueueError
    || renderedQueueProps.initialQueueTotal !== initialQueueTotal
    || renderedQueueProps.initialNextOffset !== initialNextOffset
    || renderedQueueProps.initialMatters !== initialMatters
    || renderedQueueProps.initialMatterLookupError !== initialMatterLookupError
  ) {
    setRenderedQueueProps({
      initialDocuments,
      initialQueueError,
      initialQueueTotal,
      initialNextOffset,
      initialMatters,
      initialMatterLookupError,
    })
    if (initialQueueError) {
      setRefreshError(`${initialQueueError} Showing the last loaded documents.`)
    } else {
      setRefreshError(null)
      setDocuments(uniqueDocuments(initialDocuments))
      setQueueTotal(initialQueueTotal)
      setNextOffset(initialNextOffset)
      setLastSuccessfulRefreshAt(freshnessClock)
    }
    setMatterOptions(initialMatters)
    setDestinationMatches([])
    setMatterLookupError(initialMatterLookupError)
  }

  useEffect(() => {
    loadedPageOffsetsRef.current = [0]
  }, [initialDocuments, initialNextOffset, initialQueueError, initialQueueTotal])

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
      placementSubjectRef.current = null
      // Clear the dependent form control when the selected subject disappears.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setSelectedMatterId('')
      return
    }
    const intendedMatter = selectedDocument.intake_matter_id
    if (placementSubjectRef.current !== selectedDocument.id) {
      placementSubjectRef.current = selectedDocument.id
      setSelectedMatterId(intendedMatter && matterById.has(intendedMatter) ? intendedMatter : '')
      return
    }
    if (!selectedMatterId && intendedMatter && matterById.has(intendedMatter)) {
      setSelectedMatterId(intendedMatter)
    }
  }, [matterById, selectedDocument, selectedMatterId])

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

  const hydrateMatterOptions = useCallback(async (queueDocuments: readonly InboxQueueDocument[]) => {
    const includeIds = queueDocuments.flatMap((document) =>
      document.intake_matter_id ? [document.intake_matter_id] : [])
    if (includeIds.length === 0) return

    try {
      const result = await searchMatterDestinations({ includeIds })
      if (!result.ok) return
      setMatterOptions((current) => uniqueMatterOptions([...current, ...result.matters]))
    } catch {
      // Queue rows remain usable with an explicit unavailable destination label.
    }
  }, [])

  useEffect(() => {
    const generation = destinationRequestGeneration.current + 1
    destinationRequestGeneration.current = generation
    if (!selectedActions.canAssign) return
    const timer = window.setTimeout(async () => {
      setIsDestinationPending(true)
      try {
        const result = await searchMatterDestinations({
          query: destinationQuery,
          includeIds: selectedMatterId ? [selectedMatterId] : [],
        })
        if (destinationRequestGeneration.current !== generation) return
        if (!result.ok) {
          setMatterLookupError(result.error)
          return
        }

        setMatterOptions((current) => uniqueMatterOptions([...current, ...result.matters]))
        setDestinationMatches(result.matters)
        setMatterLookupError(null)
        if (selectedMatterId && !result.matters.some((matter) => matter.id === selectedMatterId)) {
          setSelectedMatterId('')
        }
      } catch (error) {
        if (destinationRequestGeneration.current !== generation) return
        setMatterLookupError(error instanceof Error ? error.message : 'Matter destinations could not be loaded.')
      } finally {
        if (destinationRequestGeneration.current === generation) setIsDestinationPending(false)
      }
    }, destinationQuery ? 250 : 0)

    return () => window.clearTimeout(timer)
  }, [destinationQuery, selectedActions.canAssign, selectedMatterId])

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

  const refreshQueue = useCallback(async () => {
    const generation = queueRequestGeneration.current + 1
    queueRequestGeneration.current = generation
    setIsLoadingMore(false)
    try {
      const offsets = [...loadedPageOffsetsRef.current]
      const results = await Promise.all(offsets.map((offset, index) => getStagedDocuments({
        offset,
        includeId: index === 0 ? selectedIdRef.current ?? undefined : undefined,
        ownershipScope: ownershipScopeRef.current,
      })))
      if (queueRequestGeneration.current !== generation) return

      const failedResult = results.find((result) => !result.ok)
      if (failedResult && !failedResult.ok) {
        const reconciled = reconcileInboxQueue(documentsRef.current, failedResult)
        setRefreshError(reconciled.error)
        return
      }

      const successfulResults = results.filter((result) => result.ok)
      const firstResult = successfulResults[0]
      if (!firstResult) return
      const reconciled = reconcileInboxQueue(documentsRef.current, {
        ...firstResult,
        documents: successfulResults.flatMap((result) => result.documents),
      })
      for (const result of successfulResults) void hydrateMatterOptions(result.documents)
      setRefreshError(reconciled.error)
      documentsRef.current = reconciled.documents
      setDocuments(reconciled.documents)
      setQueueTotal(firstResult.total)
      const retainedOffsets = offsets.filter((offset) => offset === 0 || offset < firstResult.total)
      loadedPageOffsetsRef.current = retainedOffsets
      setNextOffset(Math.max(...retainedOffsets) + firstResult.limit)
      setLastSuccessfulRefreshAt(Date.now())
      const selectedId = selectedIdRef.current
      if (selectedId && !reconciled.documents.some((document) => document.id === selectedId)) {
        sourceRequestGeneration.current += 1
        selectedIdRef.current = null
        setIsSourcePending(false)
        setSelectedId(null)
        setDetailTab('overview')
        setSourceUrl(null)
        setSourceError(null)
        setActionError(null)
        router.replace(documentHubPath({ matterId: preselectedMatterId }), { scroll: false })
      }
    } catch (error) {
      setRefreshError(
        error instanceof Error
          ? error.message
          : 'The queue could not be refreshed. Showing the last loaded documents.',
      )
    }
  }, [hydrateMatterOptions, preselectedMatterId, router])

  async function loadMoreDocuments() {
    if (isLoadingMore || nextOffset >= queueTotal) return
    const generation = queueRequestGeneration.current + 1
    queueRequestGeneration.current = generation
    setIsLoadingMore(true)
    try {
      const result = await getStagedDocuments({ offset: nextOffset, ownershipScope })
      if (queueRequestGeneration.current !== generation) return
      if (!result.ok) {
        setRefreshError(`${result.error} Showing the last loaded documents.`)
        return
      }

      const mergedDocuments = uniqueDocuments([...documentsRef.current, ...result.documents])
      void hydrateMatterOptions(result.documents)
      documentsRef.current = mergedDocuments
      setDocuments(mergedDocuments)
      setQueueTotal(result.total)
      loadedPageOffsetsRef.current = [...loadedPageOffsetsRef.current, result.offset]
      setNextOffset(result.offset + result.limit)
      setRefreshError(null)
      setLastSuccessfulRefreshAt(Date.now())
    } catch (error) {
      if (queueRequestGeneration.current !== generation) return
      setRefreshError(error instanceof Error ? error.message : 'More documents could not be loaded.')
    } finally {
      if (queueRequestGeneration.current === generation) setIsLoadingMore(false)
    }
  }

  const changeOwnershipScope = useCallback(async (nextScope: 'mine' | 'all') => {
    if (nextScope === ownershipScopeRef.current) return
    const generation = queueRequestGeneration.current + 1
    queueRequestGeneration.current = generation
    const result = await getStagedDocuments({ ownershipScope: nextScope })
    if (queueRequestGeneration.current !== generation) return
    if (!result.ok) {
      setRefreshError(result.error)
      window.localStorage.setItem(
        `casechain:document-hub-scope:${currentUserId}`,
        ownershipScopeRef.current,
      )
      return
    }
    ownershipScopeRef.current = nextScope
    setOwnershipScope(nextScope)
    window.localStorage.setItem(`casechain:document-hub-scope:${currentUserId}`, nextScope)
    setSelectedId(null)
    selectedIdRef.current = null
    setSourceUrl(null)
    setActionError(null)
    setRefreshError(null)
    documentsRef.current = result.documents
    setDocuments(result.documents)
    setQueueTotal(result.total)
    setNextOffset(result.offset + result.limit)
    loadedPageOffsetsRef.current = [0]
    setLastSuccessfulRefreshAt(Date.now())
    router.replace(documentHubPath({ matterId: preselectedMatterId }), { scroll: false })
  }, [currentUserId, preselectedMatterId, router])

  useEffect(() => {
    const remembered = window.localStorage.getItem(`casechain:document-hub-scope:${currentUserId}`)
    if (remembered !== 'all') return
    const timer = window.setTimeout(() => void changeOwnershipScope('all'), 0)
    return () => window.clearTimeout(timer)
  }, [changeOwnershipScope, currentUserId])

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined
    let cancelled = false

    const schedule = () => {
      if (timer) clearTimeout(timer)
      if (document.visibilityState === 'hidden') return
      const jitteredDelay = 55_000 + Math.floor(Math.random() * 10_001)
      timer = setTimeout(async () => {
        if (navigator.onLine) await refreshQueue()
        if (!cancelled) schedule()
      }, jitteredDelay)
    }
    const reconcileOnFocus = () => {
      setIsOffline(!navigator.onLine)
      if (document.visibilityState === 'visible' && navigator.onLine) void refreshQueue()
      schedule()
    }

    queueMicrotask(() => {
      if (!cancelled) setIsOffline(!navigator.onLine)
    })
    schedule()
    window.addEventListener('focus', reconcileOnFocus)
    window.addEventListener('online', reconcileOnFocus)
    window.addEventListener('offline', reconcileOnFocus)
    document.addEventListener('visibilitychange', reconcileOnFocus)
    return () => {
      cancelled = true
      if (timer) clearTimeout(timer)
      window.removeEventListener('focus', reconcileOnFocus)
      window.removeEventListener('online', reconcileOnFocus)
      window.removeEventListener('offline', reconcileOnFocus)
      document.removeEventListener('visibilitychange', reconcileOnFocus)
    }
  }, [refreshQueue])

  useEffect(() => {
    const timer = window.setInterval(() => setFreshnessClock(Date.now()), 60_000)
    return () => window.clearInterval(timer)
  }, [])

  async function openSource(): Promise<string | null> {
    if (!selectedDocument || !selectedActions.canPreview) return null
    const subjectId = selectedDocument.id
    const generation = sourceRequestGeneration.current + 1
    sourceRequestGeneration.current = generation
    setIsSourcePending(true)
    setSourceError(null)
    try {
      const result = await getIntakeItemSignedUrl(selectedDocument.id)
      if (sourceRequestGeneration.current !== generation || selectedIdRef.current !== subjectId) return null
      if (result.error || !result.url) {
        setSourceError(result.error || 'The PDF could not be opened.')
        return null
      }
      setSourceUrl(result.url)
      return result.url
    } catch {
      if (sourceRequestGeneration.current !== generation || selectedIdRef.current !== subjectId) return null
      setSourceError('PDF source access is temporarily unavailable.')
      return null
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
      documentsRef.current = remainingDocuments
      setDocuments(remainingDocuments)
      setQueueTotal((current) => Math.max(0, current - 1))
      closeDetails()
      toast.success('Document assigned to the matter')

      try {
        await refreshQueue()
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
      const remainingDocuments = documents.filter((document) => document.id !== intakeId)
      documentsRef.current = remainingDocuments
      setDocuments(remainingDocuments)
      setQueueTotal((current) => Math.max(0, current - 1))
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
      <fieldset className="flex shrink-0 items-center rounded-[var(--radius-sm)] border border-[var(--border)] p-0.5">
        <legend className="sr-only">Upload ownership</legend>
        {(['mine', 'all'] as const).map((scope) => (
          <Button
            key={scope}
            type="button"
            variant={ownershipScope === scope ? 'secondary' : 'ghost'}
            size="sm"
            className="min-h-11 sm:min-h-9"
            aria-pressed={ownershipScope === scope}
            onClick={() => void changeOwnershipScope(scope)}
          >
            {scope === 'mine' ? 'My uploads' : 'All uploads'}
          </Button>
        ))}
      </fieldset>
      <div className="relative min-w-0 flex-1">
        <Label htmlFor="document-hub-search" className="sr-only">Search document queue</Label>
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
        <Input
          id="document-hub-search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search loaded documents"
          className="h-11 pl-9 sm:h-9"
        />
      </div>
      <p className="shrink-0 text-xs text-[var(--text-muted)]" aria-live="polite">
        {query.trim()
          ? `${filteredDocuments.length} matches in ${documents.length} loaded · ${queueTotal} total`
          : `${documents.length} of ${queueTotal} documents`}
      </p>
      <p
        className="shrink-0 text-xs text-[var(--text-muted)]"
        title="Live updates are unavailable. This foreground view periodically checks the authoritative queue."
      >
        {freshnessLabel(lastSuccessfulRefreshAt, freshnessClock, isOffline)}
      </p>
      <div className="flex shrink-0 items-center gap-2">
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
            {query.trim()
              ? <Search className="mx-auto size-6 text-[var(--text-muted)]" aria-hidden="true" />
              : <Inbox className="mx-auto size-6 text-[var(--text-muted)]" aria-hidden="true" />}
            <h2 className="mt-3 text-section-heading">
              {query.trim()
                ? 'No matches in loaded documents'
                : ownershipScope === 'mine' ? 'No uploads from you' : 'No uploads in intake'}
            </h2>
            <p className="mt-1 text-body text-[var(--text-muted)]">
              {query.trim() && nextOffset < queueTotal
                ? 'Load more documents to extend this search, or clear it to return to the loaded queue.'
                : query.trim()
                  ? 'Clear the search to return to the full queue.'
                  : ownershipScope === 'mine'
                    ? 'Upload PDFs here, or choose All uploads to review shared organisation intake.'
                    : 'Upload PDFs to add documents for organisation triage.'}
            </p>
            <div className="mt-4 flex flex-wrap justify-center gap-2">
              {query.trim() ? (
                <Button type="button" variant="outline" onClick={() => setQuery('')}>Clear search</Button>
              ) : (
                <Button type="button" onClick={() => setIsUploadOpen(true)}>
                  <Upload className="size-4" aria-hidden="true" />
                  Upload PDFs
                </Button>
              )}
              {query.trim() && nextOffset < queueTotal && (
                <Button type="button" variant="outline" onClick={loadMoreDocuments} loading={isLoadingMore}>
                  Load more documents
                </Button>
              )}
            </div>
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
          {nextOffset < queueTotal && (
            <div className="flex justify-center border-t border-[var(--border)] p-3">
              <Button type="button" variant="outline" onClick={loadMoreDocuments} loading={isLoadingMore}>
                Load more documents
              </Button>
            </div>
          )}
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
        <PdfViewer url={sourceUrl} onRequestSourceRefresh={openSource} />
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
                <Label htmlFor="document-hub-matter-search">Matter</Label>
                <div className="relative">
                  <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" aria-hidden="true" />
                  <Input
                    id="document-hub-matter-search"
                    value={destinationQuery}
                    onChange={(event) => setDestinationQuery(event.target.value)}
                    placeholder="Search by client, matter, code, or financial year"
                    className="h-11 pl-9"
                    aria-controls="document-hub-matter-results"
                  />
                </div>
                <div
                  id="document-hub-matter-results"
                  role="listbox"
                  aria-label="Matter destinations"
                  aria-busy={isDestinationPending}
                  className="custom-scrollbar max-h-56 overflow-y-auto rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)]"
                >
                  {destinationMatches.map((matter) => {
                    const isSelected = matter.id === selectedMatterId
                    return (
                      <button
                        key={matter.id}
                        type="button"
                        role="option"
                        aria-selected={isSelected}
                        onClick={() => setSelectedMatterId(matter.id)}
                        className={cn(
                          'flex min-h-11 w-full items-center gap-2 border-b border-[var(--border-subtle)] px-3 py-2 text-left last:border-b-0 hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]',
                          isSelected && 'bg-[var(--accent-muted)]',
                        )}
                      >
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-sm font-medium text-[var(--text-primary)]">{matter.title || 'Untitled matter'}</span>
                          <span className="block truncate text-xs text-[var(--text-muted)]">
                            {[matter.clients?.name, matter.matter_code, matter.financial_year].filter(Boolean).join(' · ') || 'Matter details unavailable'}
                          </span>
                        </span>
                        {isSelected && <Check className="size-4 shrink-0 text-[var(--primary)]" aria-hidden="true" />}
                      </button>
                    )
                  })}
                  {!isDestinationPending && destinationMatches.length === 0 && (
                    <p className="p-4 text-center text-xs text-[var(--text-muted)]">No accessible active matters match this search.</p>
                  )}
                  {isDestinationPending && destinationMatches.length === 0 && (
                    <p className="p-4 text-center text-xs text-[var(--text-muted)]">Searching matters…</p>
                  )}
                </div>
                {destinationQuery && destinationMatches.length > 0 && (
                  <p className="text-xs leading-5 text-[var(--text-muted)]">
                    Showing the current selection, when present, and up to 20 matches. Refine the search to narrow the list.
                  </p>
                )}
                {matterLookupError && <p role="alert" className="text-xs leading-5 text-[var(--danger)]">{matterLookupError}</p>}
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
