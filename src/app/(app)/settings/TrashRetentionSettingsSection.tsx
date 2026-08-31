'use client'

import { useState, useTransition } from 'react'
import {
  ArchiveRestore,
  BellRing,
  CalendarClock,
  Check,
  ChevronDown,
  CircleAlert,
  UserCog,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

import { updateTrashRetentionPolicy } from '@/lib/actions/trash-retention'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import type { TrashRetentionPolicy } from '@/lib/trash/retention-policy'

type RetentionDays = TrashRetentionPolicy['retentionDays']

const options: Array<{ value: RetentionDays; label: string }> = [
  { value: 30, label: '30 days' },
  { value: 60, label: '60 days' },
  { value: 90, label: '90 days' },
]

export function TrashRetentionSettingsSection({
  initialPolicy,
  loadError,
}: {
  initialPolicy: TrashRetentionPolicy | null
  loadError: boolean
}) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [retentionDays, setRetentionDays] = useState<RetentionDays>(initialPolicy?.retentionDays ?? 90)
  const [savedDays, setSavedDays] = useState<RetentionDays>(initialPolicy?.retentionDays ?? 90)
  const [policyVersion, setPolicyVersion] = useState(initialPolicy?.policyVersion ?? 1)
  const [message, setMessage] = useState<string | null>(null)
  const canManage = initialPolicy?.canManage === true
  const dirty = retentionDays !== savedDays

  if (loadError || !initialPolicy) {
    return (
      <section className="grid min-h-64 place-items-center rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6 text-center" role="alert" aria-labelledby="trash-retention-error-title">
        <div>
          <CircleAlert className="mx-auto size-8 text-[var(--danger)]" aria-hidden="true" />
          <h2 id="trash-retention-error-title" className="mt-3 text-section-heading">Trash retention could not be displayed</h2>
          <p className="mx-auto mt-2 max-w-md text-sm leading-6 text-[var(--text-muted)]">The current organisation policy was not loaded, so the setting remains unavailable.</p>
          <Button variant="outline" className="mt-4" onClick={() => router.refresh()}>Try again</Button>
        </div>
      </section>
    )
  }

  function save() {
    setMessage(null)
    startTransition(async () => {
      const result = await updateTrashRetentionPolicy(retentionDays, policyVersion)
      if (result.retentionDays && result.policyVersion) {
        setRetentionDays(result.retentionDays)
        setSavedDays(result.retentionDays)
        setPolicyVersion(result.policyVersion)
      }
      if (result.error) {
        setMessage(result.error)
        toast.error(result.error)
        return
      }
      setMessage('Trash retention policy saved. Existing Trash groups keep their current deletion date.')
      toast.success('Trash retention policy saved.')
    })
  }

  const selectedLabel = options.find((option) => option.value === retentionDays)?.label ?? '90 days'

  return (
    <section aria-labelledby="trash-retention-title" className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] shadow-xs">
      <div className="flex items-start gap-3 border-b border-[var(--border-subtle)] px-4 py-3">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]">
          <ArchiveRestore className="size-4" aria-hidden="true" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 id="trash-retention-title" className="text-sm font-semibold text-[var(--text-primary)]">Trash retention</h2>
            {!canManage && <Badge variant="muted">Read only</Badge>}
          </div>
          <p className="mt-0.5 break-words text-xs leading-5 text-[var(--text-muted)]">Choose when new items moved to Trash are scheduled for permanent deletion.</p>
        </div>
      </div>

      <div className="space-y-5 p-4">
        {!canManage && (
          <div className="flex items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3" role="status">
            <UserCog className="mt-0.5 size-4 shrink-0 text-[var(--text-muted)]" aria-hidden="true" />
            <p className="text-xs leading-5 text-[var(--text-muted)]">Only an Owner or Admin can change this organisation policy. Your role can review the current period.</p>
          </div>
        )}

        <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_18rem] sm:items-start">
          <div className="min-w-0">
            <div className="text-sm font-medium text-[var(--text-primary)]">Permanently delete after</div>
            <p id="trash-retention-help" className="mt-0.5 break-words text-xs leading-5 text-[var(--text-muted)]">Applies prospectively when a root item is moved to Trash. Existing Trash groups do not change.</p>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" className="min-h-11 w-full justify-start px-3 text-left" disabled={!canManage || isPending} aria-describedby="trash-retention-help">
                <CalendarClock className="size-4 shrink-0" aria-hidden="true" />
                <span className="min-w-0 flex-1 truncate">{selectedLabel}</span>
                <ChevronDown className="size-4 shrink-0" aria-hidden="true" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-[min(22rem,calc(100vw-2rem))]">
              <DropdownMenuLabel>Trash retention period</DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuRadioGroup value={String(retentionDays)} onValueChange={(value) => setRetentionDays(Number(value) as RetentionDays)}>
                {options.map((option) => (
                  <DropdownMenuRadioItem key={option.value} value={String(option.value)}>{option.label}</DropdownMenuRadioItem>
                ))}
              </DropdownMenuRadioGroup>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <div className="flex items-start gap-2 border-t border-[var(--border-subtle)] pt-4 text-xs leading-5 text-[var(--text-muted)]">
          <BellRing className="mt-0.5 size-4 shrink-0 text-[var(--primary)]" aria-hidden="true" />
          <span>CaseChain adds one item to <strong className="font-semibold text-[var(--text-primary)]">Today → Team attention</strong> 24 hours before scheduled permanent deletion. Until deletion begins, authorised users can restore the group or use the separately governed permanent-delete flow from Trash.</span>
        </div>

        <div className="flex min-h-11 flex-col gap-2 border-t border-[var(--border-subtle)] pt-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="min-w-0 break-words text-xs leading-5 text-[var(--text-muted)]" aria-live="polite">{message}</p>
          {canManage && (
            <Button onClick={save} disabled={!dirty || isPending} loading={isPending} className="shrink-0 self-end sm:self-auto">
              <Check className="size-4" aria-hidden="true" />
              Save changes
            </Button>
          )}
        </div>
      </div>
    </section>
  )
}
