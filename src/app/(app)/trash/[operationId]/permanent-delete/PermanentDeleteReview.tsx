'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { AlertTriangle, ArrowLeft, CheckCircle2, HardDrive, Loader2, LockKeyhole, ShieldAlert, Trash2 } from 'lucide-react'

import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { confirmTrashPurgeAction, reauthenticateTrashPurgeAction, retryTrashPurgeAction } from '@/lib/actions/trash-purge'
import type { TrashPurgeImpact } from '@/lib/trash/purge-model'

function formatBytes(value: number) {
  if (!Number.isFinite(value) || value <= 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const exponent = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
  return `${new Intl.NumberFormat('en-IN', { maximumFractionDigits: 1 }).format(value / (1024 ** exponent))} ${units[exponent]}`
}

function resourceLabel(type: TrashPurgeImpact['rootResourceType']) {
  return type === 'client' ? 'Client' : type === 'matter' ? 'Matter' : 'Document'
}

function OperationalStatus({ impact }: { impact: TrashPurgeImpact }) {
  const complete = impact.operationState === 'purged'
  const failed = impact.operationState === 'purge_failed' || impact.jobState === 'retryable'
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 sm:p-5" aria-live="polite">
      <div className="flex items-start gap-3">
        {complete ? <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-[var(--success)]" aria-hidden="true" />
          : failed ? <ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" aria-hidden="true" />
            : <Loader2 className="mt-0.5 size-5 shrink-0 animate-spin text-[var(--primary)] motion-reduce:animate-none" aria-hidden="true" />}
        <div>
          <h1 className="text-section-heading">{complete ? 'Permanent deletion complete' : failed ? 'Permanent deletion needs attention' : 'Permanent deletion is running'}</h1>
          <p className="mt-1 text-sm leading-6 text-[var(--text-muted)]">
            {complete
              ? 'Only content-free audit receipts and opaque identifiers remain. This Trash group cannot be restored.'
              : failed
                ? 'The hierarchy remains fenced and inaccessible. An Owner or Admin can safely resume durable reconciliation after review.'
                : 'The hierarchy is fenced. Dependency cleanup and verified storage deletion resume safely after interruption.'}
          </p>
          {impact.safeErrorCode && <p className="mt-2 font-mono text-xs text-[var(--text-muted)]">Status code: {impact.safeErrorCode}</p>}
        </div>
      </div>
    </section>
  )
}

function RetryControl({ impact }: { impact: TrashPurgeImpact }) {
  const router = useRouter()
  const [password, setPassword] = useState('')
  const [verified, setVerified] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const idempotencyKey = useMemo(() => `purge.retry.${crypto.randomUUID()}`, [])

  return (
    <form className="space-y-3" onSubmit={(event) => {
      event.preventDefault()
      setMessage(null)
      startTransition(async () => {
        if (!verified) {
          const result = await reauthenticateTrashPurgeAction(password)
          if (!result.success) { setMessage(result.error ?? 'Identity verification failed.'); return }
          setPassword('')
          setVerified(true)
          return
        }
        const result = await retryTrashPurgeAction({
          operationId: impact.operationId,
          impactFingerprint: impact.impactFingerprint,
          idempotencyKey,
        })
        if (!result.success) { setMessage(result.error ?? 'Permanent deletion could not be retried.'); return }
        router.refresh()
      })
    }}>
      <h2 className="text-section-heading">Retry permanent deletion</h2>
      <p className="text-sm leading-6 text-[var(--text-muted)]">A fresh identity check binds the retry to this current operational impact. Completed storage effects are not repeated.</p>
      {!verified && <>
        <Label htmlFor="purge-retry-password">Current password</Label>
        <Input id="purge-retry-password" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required />
      </>}
      {message && <p className="text-sm text-[var(--danger)]" role="alert">{message}</p>}
      <Button className="w-full" type="submit" disabled={isPending}>
        {isPending && <Loader2 className="size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />}
        {verified ? 'Retry permanent deletion' : 'Verify identity'}
      </Button>
    </form>
  )
}

export function PermanentDeleteReview({ impact }: { impact: TrashPurgeImpact }) {
  const router = useRouter()
  const [step, setStep] = useState<'review' | 'reauth' | 'confirm'>('review')
  const [password, setPassword] = useState('')
  const [typedValue, setTypedValue] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const idempotencyKey = useMemo(() => `purge.manual.${crypto.randomUUID()}`, [])
  const operational = impact.operationState === 'purging' || impact.operationState === 'purge_failed' || impact.operationState === 'purged'
  const exactMatch = Boolean(impact.confirmationText && typedValue === impact.confirmationText)

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Organisation utilities' }, { label: 'Trash', href: '/trash' }, { label: 'Permanent deletion' }]} />
      <div className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] px-3 sm:px-4">
        <Button variant="ghost" size="sm" onClick={() => router.push('/trash')}><ArrowLeft className="size-4" aria-hidden="true" />Back to Trash</Button>
        <div className="min-w-0 border-l border-[var(--border-subtle)] pl-3">
          <p className="truncate text-sm font-semibold">{impact.rootName ?? 'Deleted Trash group'}</p>
          <p className="text-xs text-[var(--text-muted)]">{resourceLabel(impact.rootResourceType)} root · permanent deletion</p>
        </div>
        <Badge className="ml-auto" variant={operational ? 'warning' : 'danger'} fixedWidth="lg">
          {impact.operationState === 'purged' ? 'Deleted' : operational ? 'Processing' : 'Irreversible'}
        </Badge>
      </div>

      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain">
        <div className="mx-auto grid w-full max-w-5xl gap-4 p-3 sm:p-4 lg:grid-cols-[minmax(0,1fr)_320px] lg:p-5">
          <div className="space-y-4">
            {operational ? <OperationalStatus impact={impact} /> : (
              <>
                <section className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4" role="note">
                  <div className="flex items-start gap-3">
                    <AlertTriangle className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" aria-hidden="true" />
                    <div><h1 className="text-section-heading">Permanent deletion cannot be undone</h1><p className="mt-1 text-sm leading-6 text-[var(--text-secondary)]">The whole root Trash group is deleted together. Inherited children never receive a separate action.</p></div>
                  </div>
                </section>
                <section className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
                  <h2 className="border-b border-[var(--border-subtle)] px-4 py-2 text-sm font-semibold">Current verified impact</h2>
                  <dl className="grid grid-cols-2 gap-px bg-[var(--border-subtle)] sm:grid-cols-5">
                    {[
                      ['Clients', impact.clients], ['Matters', impact.matters], ['Documents', impact.documents],
                      ['Storage deleted', formatBytes(impact.uniqueBytes)], ['Shared storage kept', formatBytes(impact.sharedBytesRetained)],
                    ].map(([label, value]) => <div key={label} className="bg-[var(--bg)] px-3 py-2"><dt className="text-xs text-[var(--text-muted)]">{label}</dt><dd className="mt-1 font-mono text-sm font-semibold">{value}</dd></div>)}
                  </dl>
                </section>
                <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] p-4">
                  <h2 className="text-sm font-semibold">Consequences</h2>
                  <ul className="mt-2 list-disc space-y-1 pl-5 text-sm leading-6 text-[var(--text-muted)]">
                    <li>Notes, citations, deadlines, financial and derived records owned by this group are removed.</li>
                    <li>Search, embeddings, processing and delivery projections are disabled before content cleanup.</li>
                    <li>Shared assets remain when any surviving document, Intake, export, backup or hold still references them.</li>
                  </ul>
                </section>
                <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] p-4">
                  <div className="flex items-center gap-2"><LockKeyhole className="size-4 text-[var(--text-muted)]" aria-hidden="true" /><h2 className="text-sm font-semibold">Safety checks</h2></div>
                  <p className="mt-2 text-sm text-[var(--text-muted)]">{impact.blockerCount === 0 ? 'No legal hold, active export, backup or platform dependency currently blocks this operation.' : `${impact.blockerCount} blocker${impact.blockerCount === 1 ? '' : 's'} prevent deletion of the whole group.`}</p>
                  {impact.blockers.length > 0 && <ul className="mt-2 space-y-1 text-xs text-[var(--text-muted)]">{impact.blockers.map((blocker) => <li key={`${blocker.code}:${blocker.resourceId}`}><span className="font-medium text-[var(--text-primary)]">{blocker.code.replaceAll('_', ' ')}</span> · {resourceLabel(blocker.resourceType)}</li>)}</ul>}
                </section>
              </>
            )}
          </div>

          {!operational && <aside className="h-fit rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] p-4 sm:p-5">
            {!impact.canPurge ? <><h2 className="text-section-heading">Permanent deletion unavailable</h2><p className="mt-2 text-sm leading-6 text-[var(--text-muted)]">Only an Owner or Admin can permanently delete an eligible direct root. Holds and active exports block the whole operation.</p></> : step === 'review' ? <>
              <h2 className="text-section-heading">Review this decision</h2><p className="mt-2 text-sm leading-6 text-[var(--text-muted)]">Continue only after checking the current impact. Identity verification and exact typed confirmation follow.</p>
              <Button variant="destructive" className="mt-4 w-full" onClick={() => setStep('reauth')}><Trash2 className="size-4" aria-hidden="true" />Continue permanent deletion</Button>
            </> : step === 'reauth' ? <form onSubmit={(event) => { event.preventDefault(); setMessage(null); startTransition(async () => { const result = await reauthenticateTrashPurgeAction(password); if (result.success) { setPassword(''); setStep('confirm') } else setMessage(result.error ?? 'Identity verification failed.') }) }}>
              <h2 className="text-section-heading">Verify your identity</h2><p className="mt-2 text-sm leading-6 text-[var(--text-muted)]">Enter your current password. Verification must be recent when the command is confirmed.</p>
              <Label htmlFor="purge-password" className="mt-4 block">Current password</Label><Input id="purge-password" className="mt-1.5" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required />
              {message && <p className="mt-2 text-sm text-[var(--danger)]" role="alert">{message}</p>}
              <Button className="mt-4 w-full" type="submit" disabled={isPending}>{isPending && <Loader2 className="size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />}Verify identity</Button>
              <Button className="mt-2 w-full" type="button" variant="ghost" onClick={() => setStep('review')}>Back</Button>
            </form> : <form onSubmit={(event) => { event.preventDefault(); setMessage(null); startTransition(async () => { const result = await confirmTrashPurgeAction({ operationId: impact.operationId, impactFingerprint: impact.impactFingerprint, confirmationText: typedValue, idempotencyKey }); if (result.success) { router.refresh() } else setMessage(result.error ?? 'Permanent deletion could not be queued.') }) }}>
              <h2 className="text-section-heading">Type the exact {impact.rootResourceType === 'document' ? 'name' : 'name or code'}</h2><p className="mt-2 break-words text-sm leading-6 text-[var(--text-muted)]">Type <span className="font-mono font-semibold text-[var(--text-primary)]">{impact.confirmationText}</span> exactly.</p>
              <Label htmlFor="purge-confirmation" className="mt-4 block">Exact confirmation</Label><Input id="purge-confirmation" className="mt-1.5 font-mono" autoComplete="off" value={typedValue} onChange={(event) => setTypedValue(event.target.value)} aria-describedby="purge-confirmation-status" />
              <p id="purge-confirmation-status" className="mt-2 text-sm text-[var(--text-muted)]">{exactMatch ? 'Exact match. The final action is available.' : 'The value must match character for character.'}</p>
              {message && <p className="mt-2 text-sm text-[var(--danger)]" role="alert">{message}</p>}
              <Button variant="destructive" className="mt-4 w-full" type="submit" disabled={!exactMatch || isPending}>{isPending && <Loader2 className="size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />}Delete permanently</Button>
              <Button className="mt-2 w-full" type="button" variant="ghost" onClick={() => setStep('review')}>Cancel confirmation</Button>
            </form>}
          </aside>}
          {operational && <aside className="h-fit rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4">
            {impact.operationState === 'purge_failed' && impact.canPurge
              ? <RetryControl impact={impact} />
              : <div className="flex items-start gap-2"><HardDrive className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" /><p className="text-sm leading-6 text-[var(--text-muted)]">Completed database and storage effects are receipt-fenced. Retries do not restore content or repeat confirmed external outcomes.</p></div>}
          </aside>}
        </div>
      </div>
    </div>
  )
}
