'use client'

import { useState } from 'react'
import { useTheme } from 'next-themes'
import {
  ArchiveRestore,
  BellRing,
  CalendarClock,
  Check,
  ChevronDown,
  ChevronRight,
  CircleAlert,
  Gavel,
  Info,
  Moon,
  Settings,
  Sun,
  UserCog,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { Skeleton } from '@/components/ui/skeleton'

type PreviewRole = 'owner-admin' | 'associate' | 'viewer'
type PreviewState = 'default' | 'loading' | 'error' | 'long-content'
type RetentionTerm = 30 | 60 | 90

const retentionTerms: Array<{ value: RetentionTerm; label: string }> = [
  { value: 30, label: '30 days' },
  { value: 60, label: '60 days' },
  { value: 90, label: '90 days' },
]

const roleLabels: Record<PreviewRole, string> = {
  'owner-admin': 'Owner / Admin',
  associate: 'Associate',
  viewer: 'Viewer',
}

function PreviewMenu({
  role,
  state,
  onRoleChange,
  onStateChange,
  onAppearanceChange,
  onShowBoundary,
}: {
  role: PreviewRole
  state: PreviewState
  onRoleChange: (role: PreviewRole) => void
  onStateChange: (state: PreviewState) => void
  onAppearanceChange: (appearance: 'light' | 'dark') => void
  onShowBoundary: () => void
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          Preview
          <ChevronDown className="size-3.5" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-64">
        <DropdownMenuLabel>Access preview</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={role} onValueChange={(value) => onRoleChange(value as PreviewRole)}>
          {(['owner-admin', 'associate', 'viewer'] as PreviewRole[]).map((option) => (
            <DropdownMenuRadioItem key={option} value={option}>{roleLabels[option]}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Content state</DropdownMenuLabel>
        <DropdownMenuRadioGroup value={state} onValueChange={(value) => onStateChange(value as PreviewState)}>
          {(['default', 'loading', 'error', 'long-content'] as PreviewState[]).map((option) => (
            <DropdownMenuRadioItem key={option} value={option} className="capitalize">{option.replace('-', ' ')}</DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Appearance preview</DropdownMenuLabel>
        <DropdownMenuItem onSelect={() => onAppearanceChange('light')}><Sun className="size-4" aria-hidden="true" />Preview light</DropdownMenuItem>
        <DropdownMenuItem onSelect={() => onAppearanceChange('dark')}><Moon className="size-4" aria-hidden="true" />Preview dark</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem onSelect={onShowBoundary}><Info className="size-4" aria-hidden="true" />About this concept</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function ConceptHeader({
  canEdit,
  dirty,
  onReviewChanges,
  previewMenu,
}: {
  canEdit: boolean
  dirty: boolean
  onReviewChanges: () => void
  previewMenu: React.ReactNode
}) {
  return (
    <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
      <div className="hidden min-h-12 items-center gap-2 border-b border-[var(--border-subtle)] px-4 text-xs text-[var(--text-muted)] sm:flex">
        <span>Apex Tax Advocates</span>
        <ChevronRight className="size-3.5" aria-hidden="true" />
        <span>Settings</span>
        <ChevronRight className="size-3.5" aria-hidden="true" />
        <span className="text-[var(--text-primary)]">Operations</span>
        <Badge variant="muted" className="ml-2">Concept only</Badge>
      </div>

      <div className="flex min-h-14 items-center gap-3 px-3 sm:hidden">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]">
          <Settings className="size-4" aria-hidden="true" />
        </span>
        <div className="min-w-0">
          <h1 className="truncate text-base font-semibold">Organisation settings</h1>
          <p className="truncate text-xs text-[var(--text-muted)]">Apex Tax Advocates · Operations</p>
        </div>
        <Badge variant="muted" className="ml-auto">Concept</Badge>
      </div>

      <div className="flex min-h-14 flex-wrap items-center gap-2 px-3 py-1.5 sm:flex-nowrap sm:px-4 sm:py-0">
        <div className="flex min-h-11 items-center gap-2 text-sm font-medium sm:min-h-9">
          <ArchiveRestore className="size-4 text-[var(--accent)]" aria-hidden="true" />
          <span>Operations</span>
        </div>
        <span className="hidden min-w-0 flex-1 truncate text-xs text-[var(--text-muted)] lg:block">
          Organisation policy · Owner/Admin only
        </span>
        <div className="ml-auto flex items-center gap-2">
          {previewMenu}
          <Button size="sm" disabled={!canEdit || !dirty} onClick={onReviewChanges}>
            <Check className="size-4" aria-hidden="true" />
            Save changes
          </Button>
        </div>
      </div>
    </header>
  )
}

function ReadOnlyNotice({ role }: { role: Exclude<PreviewRole, 'owner-admin'> }) {
  return (
    <div className="flex items-start gap-3 rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4" role="status">
      <UserCog className="mt-0.5 size-5 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-sm font-semibold">Trash retention is read only</h2>
          <Badge variant="muted">{roleLabels[role]}</Badge>
        </div>
        <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">
          Only an Owner or Admin can change organisation retention policy. You can review the current policy, but its controls are unavailable for your role.
        </p>
      </div>
    </div>
  )
}

function RetentionMenu({
  value,
  disabled,
  onChange,
}: {
  value: RetentionTerm
  disabled: boolean
  onChange: (value: RetentionTerm) => void
}) {
  const selected = retentionTerms.find((term) => term.value === value) ?? retentionTerms[0]

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          className="min-h-11 w-full justify-start px-3 text-left sm:w-72"
          disabled={disabled}
          aria-describedby="retention-help"
        >
          <CalendarClock className="size-4 shrink-0" aria-hidden="true" />
          <span className="min-w-0 flex-1 truncate">{selected.label}</span>
          <ChevronDown className="size-4 shrink-0" aria-hidden="true" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-[min(22rem,calc(100vw-2rem))]">
        <DropdownMenuLabel>Trash retention period</DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuRadioGroup value={String(value)} onValueChange={(nextValue) => onChange(Number(nextValue) as RetentionTerm)}>
          {retentionTerms.map((term) => (
            <DropdownMenuRadioItem key={term.value} value={String(term.value)}>
              {term.label}
            </DropdownMenuRadioItem>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function RetentionPanel({
  role,
  retention,
  onRetentionChange,
}: {
  role: PreviewRole
  retention: RetentionTerm
  onRetentionChange: (value: RetentionTerm) => void
}) {
  const canEdit = role === 'owner-admin'

  return (
    <section aria-labelledby="retention-title" className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <div className="flex items-start gap-3 border-b border-[var(--border-subtle)] px-4 py-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]">
          <ArchiveRestore className="size-4" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <h2 id="retention-title" className="text-sm font-semibold">Trash retention</h2>
          <p className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">Choose when items in Trash are permanently deleted.</p>
        </div>
      </div>

      <div className="space-y-5 p-4">
        <div className="grid gap-2 sm:grid-cols-[190px_minmax(0,1fr)] sm:items-start">
          <div>
            <div className="text-sm font-medium">Permanently delete after</div>
            <p id="retention-help" className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">Applies when an item is moved to Trash.</p>
          </div>
          <div className="sm:justify-self-end">
            <RetentionMenu value={retention} disabled={!canEdit} onChange={onRetentionChange} />
          </div>
        </div>

        <div className="flex items-start gap-2 border-t border-[var(--border-subtle)] pt-4 text-xs leading-5 text-[var(--text-muted)]">
          <BellRing className="mt-0.5 size-4 shrink-0 text-[var(--accent)]" aria-hidden="true" />
          <span>CaseChain adds an item to <strong className="font-semibold text-[var(--text-primary)]">Today → Team attention</strong> 24 hours before permanent deletion. Until then, an item can be restored or deleted permanently from Trash.</span>
        </div>
      </div>
    </section>
  )
}

function LoadingState() {
  return (
    <div aria-busy="true" aria-live="polite" className="space-y-3">
      <p className="sr-only">Loading Trash retention policy…</p>
      <div className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
        <div className="flex items-center gap-3 border-b border-[var(--border-subtle)] p-4">
          <Skeleton className="size-9 shrink-0" />
          <div className="min-w-0 flex-1"><Skeleton className="h-4 w-36" /><Skeleton className="mt-2 h-3 w-4/5" /></div>
        </div>
        <div className="space-y-5 p-4">
          <div className="grid gap-3 sm:grid-cols-[190px_minmax(0,1fr)]"><div><Skeleton className="h-4 w-36" /><Skeleton className="mt-2 h-3 w-40" /></div><Skeleton className="h-11 w-full sm:ml-auto sm:w-72" /></div>
          <div className="flex items-start gap-3 border-t border-[var(--border-subtle)] pt-4"><Skeleton className="size-4 shrink-0" /><div className="flex-1"><Skeleton className="h-3 w-4/5" /><Skeleton className="mt-2 h-3 w-3/5" /></div></div>
        </div>
      </div>
    </div>
  )
}

function ErrorState({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="grid min-h-[360px] place-items-center rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-6 text-center" role="alert">
      <div>
        <CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" />
        <h2 className="mt-3 text-section-heading">Trash retention could not be displayed</h2>
        <p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[var(--text-muted)]">The current policy was not loaded, so every setting remains unavailable. Try the concept state again without changing any organisation data.</p>
        <Button variant="outline" className="mt-4" onClick={onRetry}>Try concept again</Button>
      </div>
    </div>
  )
}

function LongContentProbe() {
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4" aria-labelledby="long-content-title">
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="long-content-title" className="text-sm font-semibold">Long-content and scroll check</h2>
        <Badge variant="outline">Fixture</Badge>
      </div>
      <p className="mt-2 break-words text-sm leading-6 text-[var(--text-secondary)]">
        Organisation: Apex Tax Advocates, Indirect Tax Litigation, Classification Appeals, Cross-Border Advisory and Multi-Jurisdictional Record Preservation Practice LLP.
      </p>
      <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">
        Future policy summaries may contain long legal-workspace names and translations. They must wrap without widening the page, moving the policy controls, or creating a second scroll owner. The stable Settings context remains outside this body while this single content region scrolls.
      </p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {['Prospective snapshot', 'Existing-entry boundary', 'Unstarted schedule cancellation', 'Permanent-delete exclusion'].map((title) => (
          <div key={title} className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3">
            <h3 className="text-xs font-semibold">{title}</h3>
            <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">This deliberately verbose fixture confirms that explanatory policy language remains readable at phone width and 200% zoom.</p>
          </div>
        ))}
      </div>
    </section>
  )
}

function ConceptBoundaryDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Retention settings concept</DialogTitle>
          <DialogDescription>This page is a fixture-only visual review. Its controls change local preview state and never change organisation data.</DialogDescription>
        </DialogHeader>
        <div className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-sm leading-6 text-[var(--text-secondary)]">
          <Info className="mt-1 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
          <span>There are no API calls, server actions, policy writes, schedules, permanent-deletion actions, or fabricated eligibility results in this concept.</span>
        </div>
        <DialogFooter><Button onClick={() => onOpenChange(false)}>Close</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ReviewPolicyDialog({
  open,
  retention,
  onOpenChange,
}: {
  open: boolean
  retention: RetentionTerm
  onOpenChange: (open: boolean) => void
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Review retention policy changes</DialogTitle>
          <DialogDescription>This is the production save pattern. The concept cannot save or schedule anything.</DialogDescription>
        </DialogHeader>
        <dl className="grid gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-xs sm:grid-cols-2">
          <div><dt className="text-[var(--text-muted)]">Permanently delete after</dt><dd className="mt-1 font-semibold text-[var(--text-primary)]">{retention} days</dd></div>
          <div><dt className="text-[var(--text-muted)]">Attention reminder</dt><dd className="mt-1 font-semibold text-[var(--text-primary)]">24 hours before deletion</dd></div>
        </dl>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Close preview</Button>
          <Button disabled>Save changes</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

export function TrashRetentionSettingsConcept() {
  const [role, setRole] = useState<PreviewRole>('owner-admin')
  const [previewState, setPreviewState] = useState<PreviewState>('default')
  const [retention, setRetention] = useState<RetentionTerm>(90)
  const [conceptBoundaryOpen, setConceptBoundaryOpen] = useState(false)
  const [reviewPolicyOpen, setReviewPolicyOpen] = useState(false)
  const { setTheme } = useTheme()
  const canEdit = role === 'owner-admin'
  const dirty = retention !== 90

  return (
    <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <aside aria-label="Application context" className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] lg:flex">
        <span className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Gavel className="size-5" aria-hidden="true" /></span>
        <span className="mt-auto flex size-10 items-center justify-center rounded-[var(--radius-full)] border border-[var(--sidebar-border,var(--border))] text-xs font-semibold" aria-label="Account">RJ</span>
      </aside>

      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <ConceptHeader
          canEdit={canEdit}
          dirty={dirty && previewState !== 'loading' && previewState !== 'error'}
          onReviewChanges={() => setReviewPolicyOpen(true)}
          previewMenu={(
            <PreviewMenu
              role={role}
              state={previewState}
              onRoleChange={setRole}
              onStateChange={setPreviewState}
              onAppearanceChange={setTheme}
              onShowBoundary={() => setConceptBoundaryOpen(true)}
            />
          )}
        />

        <div aria-label="Trash retention settings content" className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 sm:p-4">
          <div className="mx-auto max-w-4xl space-y-3 pb-8">
            {role !== 'owner-admin' && <ReadOnlyNotice role={role} />}

            {previewState === 'loading' ? (
              <LoadingState />
            ) : previewState === 'error' ? (
              <ErrorState onRetry={() => setPreviewState('default')} />
            ) : (
              <>
                <RetentionPanel
                  role={role}
                  retention={retention}
                  onRetentionChange={setRetention}
                />
                {previewState === 'long-content' && <LongContentProbe />}
              </>
            )}
          </div>
        </div>
      </main>

      <ConceptBoundaryDialog open={conceptBoundaryOpen} onOpenChange={setConceptBoundaryOpen} />
      <ReviewPolicyDialog open={reviewPolicyOpen} retention={retention} onOpenChange={setReviewPolicyOpen} />
    </div>
  )
}
