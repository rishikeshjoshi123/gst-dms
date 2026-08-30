'use client'

import { useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { Loader2, RotateCcw } from 'lucide-react'

import { restoreTrashOperationAction } from '@/lib/actions/trash'
import { restoreBlockerMessage, type TrashRestorePreflight } from '@/lib/trash/restore-model'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

function createRestoreKey() {
  return `restore.operation.${crypto.randomUUID()}`
}

export function RestoreTrashOperationControl({
  operationId,
  operationName,
  impact,
  preflight,
  successPath,
  compact = false,
}: {
  operationId: string
  operationName: string
  impact: string
  preflight: TrashRestorePreflight
  successPath: string
  compact?: boolean
}) {
  const router = useRouter()
  const keyRef = useRef<string | null>(null)
  const [open, setOpen] = useState(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [blocked, setBlocked] = useState<TrashRestorePreflight | null>(null)
  const effectivePreflight = blocked ?? preflight

  if (effectivePreflight.status === 'restore_blocked') {
    return (
      <div className="w-full text-xs leading-5 text-[var(--text-secondary)]" role="status">
        <p>{restoreBlockerMessage(effectivePreflight)}</p>
        {effectivePreflight.blockingOperationId && (
          <Link
            href={`/trash?selected=${encodeURIComponent(effectivePreflight.blockingOperationId)}`}
            className="mt-1 inline-flex min-h-11 items-center font-medium text-[var(--primary)] underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
          >
            View blocking parent group
          </Link>
        )}
      </div>
    )
  }
  if (!effectivePreflight.canRestore || effectivePreflight.status !== 'ready') return null

  const close = () => {
    if (pending) return
    setOpen(false)
    setError(null)
    keyRef.current = null
  }
  const restore = async () => {
    keyRef.current ??= createRestoreKey()
    setPending(true)
    setError(null)
    const result = await restoreTrashOperationAction(operationId, keyRef.current)
    setPending(false)
    if (result.success) {
      keyRef.current = null
      setOpen(false)
      if (successPath) router.push(successPath)
      router.refresh()
      return
    }
    if (result.code === 'restore_blocked') {
      keyRef.current = null
      setOpen(false)
      setBlocked({
        status: 'restore_blocked',
        canRestore: false,
        blockerCode: result.blockerCode ?? null,
        blockingOperationId: result.blockingOperationId ?? null,
      })
      router.refresh()
      return
    }
    setError(result.error ?? 'This Trash group could not be restored. Please try again.')
  }

  return (
    <>
      <Button size={compact ? 'sm' : 'md'} onClick={() => setOpen(true)} className="shrink-0">
        <RotateCcw className="size-4" aria-hidden="true" />
        Restore group
      </Button>
      <Dialog open={open} onOpenChange={(next) => next ? setOpen(true) : close()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Restore this Trash group?</DialogTitle>
            <DialogDescription>
              Restoring returns the selected root and only the items moved to Trash with this operation.
            </DialogDescription>
          </DialogHeader>
          <dl className="grid grid-cols-2 gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-xs">
            <div className="col-span-2">
              <dt className="text-[var(--text-muted)]">Trash group</dt>
              <dd className="mt-1 break-words font-medium text-[var(--text-primary)]">{operationName}</dd>
            </div>
            <div className="col-span-2">
              <dt className="text-[var(--text-muted)]">Restore impact</dt>
              <dd className="mt-1 text-[var(--text-primary)]">{impact}</dd>
            </div>
          </dl>
          <p className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-3 text-sm leading-6 text-[var(--text-secondary)]">
            Independently trashed descendants stay in their original Trash groups. Search and future schedules are re-evaluated from durable restore intents; missed reminders are not sent automatically.
          </p>
          {error && <p role="alert" className="text-sm text-[var(--danger)]">{error}</p>}
          <DialogFooter>
            <Button variant="outline" onClick={close} disabled={pending}>Cancel</Button>
            <Button onClick={restore} disabled={pending}>
              {pending ? <><Loader2 className="size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />Restoring…</> : <><RotateCcw className="size-4" aria-hidden="true" />Restore group</>}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
