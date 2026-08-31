'use client'

import { useState } from 'react'

import {
  AlertTriangle,
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  FileText,
  FolderOpen,
  Loader2,
  RefreshCw,
  ShieldAlert,
  ShieldCheck,
  Trash2,
  Users,
  WalletCards,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { cn } from '@/lib/utils'

type ReviewState = 'ready' | 'confirm' | 'deleting' | 'done' | 'error'

const confirmationCode = 'KAVERI-OP-418'

const rootOperation = {
  id: 'OP-418',
  type: 'Client root',
  name: 'Kaveri Components Private Limited',
  deletedBy: 'Rishikesh Joshi',
  deletedOn: '30 Aug 2026 · 10:32',
  scheduledFor: '28 Nov 2026 · 10:32',
  descendants: {
    clients: 1,
    matters: 4,
    documents: 28,
    bytes: '44.2 MB',
    sharedBytes: '4.4 MB',
  },
  included: [
    { type: 'Matter', label: 'FY 2024–25 ITC reconciliation', detail: '18 documents' },
    { type: 'Matter', label: 'Classification advisory', detail: '10 documents' },
    { type: 'Document', label: 'Supplier confirmations — consolidated ledger and annexures for Q4 FY 2024–25.pdf', detail: 'Inherited child · no separate action' },
  ],
}

function ImpactSummaryCard() {
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <div className="border-b border-[var(--border-subtle)] px-3 py-1.5 sm:px-4 sm:py-2">
        <h2 className="text-sm font-semibold">What will be permanently lost</h2>
      </div>

      <dl className="grid grid-cols-2 gap-px divide-x divide-[var(--border-subtle)] bg-[var(--border-subtle)] sm:grid-cols-3 lg:grid-cols-5">
        <div className="bg-[var(--bg)] px-2 py-1.5 sm:px-2.5 sm:py-1.5">
          <dt className="text-xs leading-4 text-[var(--text-muted)]">Clients</dt>
          <dd className="mt-0.5 text-sm font-mono font-semibold">{rootOperation.descendants.clients}</dd>
        </div>
        <div className="bg-[var(--bg)] px-2 py-1.5 sm:px-2.5 sm:py-1.5">
          <dt className="text-xs leading-4 text-[var(--text-muted)]">Matters</dt>
          <dd className="mt-0.5 text-sm font-mono font-semibold">{rootOperation.descendants.matters}</dd>
        </div>
        <div className="bg-[var(--bg)] px-2 py-1.5 sm:px-2.5 sm:py-1.5">
          <dt className="text-xs leading-4 text-[var(--text-muted)]">Documents</dt>
          <dd className="mt-0.5 text-sm font-mono font-semibold">{rootOperation.descendants.documents}</dd>
        </div>
        <div className="bg-[var(--bg)] px-2 py-1.5 sm:px-2.5 sm:py-1.5">
          <dt className="text-xs leading-4 text-[var(--text-muted)]">Deleted storage</dt>
          <dd className="mt-0.5 text-sm font-mono font-semibold">{rootOperation.descendants.bytes}</dd>
        </div>
        <div className="bg-[var(--bg)] px-2 py-1.5 sm:px-2.5 sm:py-1.5">
          <dt className="text-xs leading-4 text-[var(--text-muted)]">Protected shared storage</dt>
          <dd className="mt-0.5 text-sm font-mono font-semibold">{rootOperation.descendants.sharedBytes}</dd>
        </div>
      </dl>
    </section>
  )
}

function IncludedItemsCard() {
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <div className="px-4 py-3 sm:px-5 sm:py-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-section-heading">Items included with this group</h2>
          <Badge variant="muted" fixedWidth="md">
            Direct root operation
          </Badge>
        </div>

        <ul className="mt-3 space-y-2">
          {rootOperation.included.map((item) => {
            const Icon = item.type === 'Matter' ? FolderOpen : FileText
            return (
              <li
                key={item.label}
                className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3"
              >
                <div className="flex items-start gap-2">
                  <Icon className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
                  <div className="min-w-0">
                    <p className="text-body font-medium text-[var(--text-primary)]">{item.label}</p>
                    <p className="mt-0.5 text-caption text-[var(--text-muted)]">{item.type} · {item.detail}</p>
                  </div>
                </div>
              </li>
            )
          })}
        </ul>
      </div>
    </section>
  )
}

function IdentityCard() {
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <dl className="grid gap-3 px-4 py-3 sm:grid-cols-2 sm:gap-4 sm:px-5 sm:py-4">
        <div className="flex flex-wrap items-start gap-2 sm:col-span-2">
          <Users className="mt-0.5 size-4 text-[var(--text-muted)]" aria-hidden="true" />
          <div>
            <dt className="text-caption text-[var(--text-muted)]">Root operation</dt>
            <dd className="text-body font-semibold">{rootOperation.id} · {rootOperation.name}</dd>
          </div>
        </div>

        <div>
          <dt className="text-caption text-[var(--text-muted)]">Deleted by</dt>
          <dd className="mt-1 font-medium text-body text-[var(--text-primary)]">{rootOperation.deletedBy}</dd>
        </div>
        <div>
          <dt className="text-caption text-[var(--text-muted)]">Scheduled purge</dt>
          <dd className="mt-1 font-mono text-body text-[var(--text-primary)]">{rootOperation.scheduledFor}</dd>
        </div>
        <div>
          <dt className="text-caption text-[var(--text-muted)]">Deleted on</dt>
          <dd className="mt-1 font-mono text-body text-[var(--text-primary)]">{rootOperation.deletedOn}</dd>
        </div>
        <div>
          <dt className="text-caption text-[var(--text-muted)]">Retention policy</dt>
          <dd className="mt-1 font-semibold text-body text-[var(--text-primary)]">90 days</dd>
        </div>
      </dl>
    </section>
  )
}

function DeletionDecisionPanel({
  state,
  typedValue,
  onTypedValueChange,
  onStateChange,
}: {
  state: ReviewState
  typedValue: string
  onTypedValueChange: (value: string) => void
  onStateChange: (state: ReviewState) => void
}) {
  const exactMatch = typedValue === confirmationCode

  if (state === 'deleting') {
    return (
      <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 sm:p-5">
        <h2 className="text-section-heading">Permanent delete is running</h2>
        <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--accent)] bg-[var(--accent-muted)] p-3 leading-5 text-body">
          <Loader2 className="mr-2 inline size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />
          Durable stages are locked and will resume safely after interruption.
        </div>

        <ol className="mt-4 space-y-2 text-body text-[var(--text-muted)]">
          <li className="flex min-h-11 items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] px-3 py-2">
            <CheckCircle2 className="size-4 text-[var(--success)]" aria-hidden="true" />
            <span className="min-w-0 flex-1">Search and dependency mapping completed</span>
            <span>Complete</span>
          </li>
          <li className="flex min-h-11 items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] px-3 py-2">
            <ShieldAlert className="size-4 text-[var(--warning)]" aria-hidden="true" />
            <span className="min-w-0 flex-1">Storage impact verification</span>
            <span>Running</span>
          </li>
          <li className="flex min-h-11 items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] px-3 py-2">
            <WalletCards className="size-4 text-[var(--text-muted)]" aria-hidden="true" />
            <span className="min-w-0 flex-1">Final deletion and tombstone write</span>
            <span>Queued</span>
          </li>
        </ol>
      </section>
    )
  }

  if (state === 'done') {
    return (
      <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 sm:p-5">
        <h2 className="text-section-heading">No preview data is recoverable</h2>
        <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--success)] bg-[var(--success-muted)] p-3 leading-5 text-body text-[var(--text-secondary)]">
          <CheckCircle2 className="mr-2 inline size-4 text-[var(--success)]" aria-hidden="true" />
          Minimal content-free receipt keeps only audit metadata. The operation remains final in this concept.
        </div>
      </section>
    )
  }

  if (state === 'error') {
    return (
      <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 sm:p-5">
        <h2 className="text-section-heading">Impact check failed</h2>
        <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--danger)] bg-[var(--danger-muted)] p-3 leading-5 text-body text-[var(--text-secondary)]">
          <RefreshCw className="mr-2 inline size-4 text-[var(--danger)]" aria-hidden="true" />
          A dependency lock was not confirmed. Retry this concept state after reloading impact.
        </div>
        <Button className="mt-3 w-full" onClick={() => onStateChange('ready')}>
          <ShieldCheck className="size-4" aria-hidden="true" />
          Retry impact
        </Button>
      </section>
    )
  }

  if (state === 'confirm') {
    return (
      <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 sm:p-5">
        <h2 className="text-section-heading">Type exact operation code</h2>
        <p className="mt-1 leading-5 text-body text-[var(--text-muted)]">
          To perform this permanent delete, type <span className="font-mono font-semibold text-[var(--text-primary)]">{confirmationCode}</span>.
        </p>
        <label htmlFor="permanent-delete-code" className="mt-3 block text-caption font-medium">
          Confirmation code
        </label>
        <Input
          id="permanent-delete-code"
          className="mt-1.5 font-mono"
          value={typedValue}
          onChange={(event) => onTypedValueChange(event.target.value)}
          autoComplete="off"
          aria-describedby="permanent-delete-hint"
        />
        <p
          id="permanent-delete-hint"
          className={cn('mt-1.5 text-body', exactMatch ? 'text-[var(--success)]' : 'text-[var(--text-muted)]')}
        >
          {exactMatch ? 'Code matched. Permanent deletion is available.' : 'Code must match exactly.'}
        </p>
        <div className="mt-4 grid gap-2">
          <Button
            variant="destructive"
            disabled={!exactMatch}
            onClick={() => onStateChange('deleting')}
            className="w-full"
          >
            <Trash2 className="size-4" aria-hidden="true" />
            Delete client root permanently
          </Button>
          <Button variant="outline" onClick={() => onStateChange('ready')} className="w-full">
            <ArrowLeft className="size-4" aria-hidden="true" />
            Back
          </Button>
        </div>
      </section>
    )
  }

  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 sm:p-5">
      <h2 className="text-section-heading">Review before you confirm</h2>
      <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 leading-5 text-body text-[var(--text-secondary)]">
        <ShieldCheck className="mr-2 inline size-4 text-[var(--success)]" aria-hidden="true" />
        Legal hold, exports, blockers, and dependent-domain safety checks are represented as plain status here. This can become the production preflight panel in the approval flow.
      </div>
      <div className="mt-3 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 leading-5 text-body text-[var(--text-secondary)]">
        <AlertTriangle className="mr-2 inline size-4 text-[var(--warning)]" aria-hidden="true" />
        Permanent delete removes legal content and dependent records for this whole operation. Restoring is not possible once it is applied.
      </div>

      <Button className="mt-4 w-full" onClick={() => onStateChange('confirm')}>
        <CalendarDays className="size-4" aria-hidden="true" />
        Continue to identity confirmation
      </Button>
    </section>
  )
}

export function TrashPermanentDeleteConcept() {
  const [state, setState] = useState<ReviewState>('ready')
  const [typedValue, setTypedValue] = useState('')

  return (
    <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <aside
        aria-label="Application context"
        className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] lg:flex"
      >
        <span className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]">
          <FolderOpen className="size-5" aria-hidden="true" />
        </span>
        <span
          className="mt-auto flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"
          aria-label="Trash"
        >
          <Trash2 className="size-5" aria-hidden="true" />
        </span>
      </aside>

      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)]">
          <div className="border-b border-[var(--border-subtle)] px-4 py-3 text-caption text-[var(--text-muted)]">
            Apex Tax Advocates · Utilities ·{' '}
            <a href="/dev/trash-workspace-concept" className="font-medium text-[var(--text-primary)] hover:underline">
              Trash
            </a>{' '}
            · Permanent deletion
          </div>
          <div className="border-b border-[var(--danger)] bg-[var(--danger-muted)] px-3 py-2.5 sm:px-4" role="note">
            <p className="leading-5 text-body text-[var(--text-primary)]">
              <span className="font-semibold">Permanent delete is irreversible.</span> If this is confirmed, nothing can restore this group or its members.
            </p>
          </div>
        </header>

        <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain">
          <div className="mx-auto w-full max-w-6xl space-y-4 p-3 sm:p-4 lg:grid lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start lg:gap-5 lg:space-y-0 lg:p-5">
            <section className="space-y-4">
              <IdentityCard />
              <ImpactSummaryCard />
              <IncludedItemsCard />
            </section>
            <section className="space-y-4">
              <DeletionDecisionPanel
                state={state}
                typedValue={typedValue}
                onTypedValueChange={(value) => setTypedValue(value)}
                onStateChange={(next) => {
                  setState(next)
                  if (next === 'ready') {
                    setTypedValue('')
                  }
                  if (next === 'deleting') {
                    window.setTimeout(() => setState('done'), 1200)
                  }
                }}
              />
              <p className="text-body leading-5 text-[var(--text-muted)]">
                Production flows also include holder resolution, idempotent execution recovery, and operation receipt creation in one durable batch.
              </p>
            </section>
          </div>
        </div>
      </main>
    </div>
  )
}
