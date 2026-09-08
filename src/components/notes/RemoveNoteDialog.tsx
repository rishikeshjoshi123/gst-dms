'use client'

import { useState } from 'react'
import { AlertTriangle, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

export function RemoveNoteDialog({
  isOpen,
  onClose,
  onRemove,
}: {
  isOpen: boolean
  onClose: () => void
  onRemove: (moderationReason?: string) => Promise<boolean>
}) {
  const [reason, setReason] = useState('')
  const [isPending, setIsPending] = useState(false)

  function handleClose() {
    setReason('')
    onClose()
  }

  async function handleRemove() {
    setIsPending(true)
    try {
      const removed = await onRemove(reason.trim() || undefined)
      if (removed) setReason('')
    } finally {
      setIsPending(false)
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && !isPending && handleClose()}>
      <DialogContent className="w-full max-w-[calc(100vw-2rem)] sm:max-w-[460px] bg-[var(--surface)] border border-[var(--border)] p-0 overflow-hidden text-[var(--text-primary)]">
        <DialogHeader className="p-6 pb-4 border-b border-[var(--border)]">
          <div className="flex items-center gap-3 text-[var(--danger)]">
            <div className="p-2 bg-[var(--danger-muted)] rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--danger)_24%,transparent)]">
              <AlertTriangle size={20} aria-hidden="true" />
            </div>
            <DialogTitle className="text-[18px] font-semibold text-[var(--text-primary)]">
              Remove note
            </DialogTitle>
          </div>
          <DialogDescription className="pt-2 text-[14px] leading-relaxed text-[var(--text-secondary)]">
            The note becomes a retained audit tombstone. Replies, linked tasks, and activity history remain.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2 px-6 py-5">
          <label htmlFor="note-moderation-reason" className="block text-[14px] font-medium text-[var(--text-primary)]">
            Moderation reason
          </label>
          <textarea
            id="note-moderation-reason"
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            placeholder="Required only when removing another member’s note"
            maxLength={500}
            disabled={isPending}
            aria-describedby="note-moderation-reason-help"
            className="min-h-24 w-full resize-y rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-[14px] text-[var(--text-primary)] outline-none transition-colors placeholder:text-[var(--text-muted)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[color-mix(in_srgb,var(--primary)_20%,transparent)] disabled:cursor-not-allowed disabled:opacity-60"
          />
          <p id="note-moderation-reason-help" className="text-[12px] text-[var(--text-muted)]">
            Leave blank for your own note. Admin and Owner moderation requires 8–500 characters.
          </p>
        </div>

        <DialogFooter className="flex flex-col-reverse gap-3 border-t border-[var(--border)] bg-[var(--bg)] px-6 py-4 sm:flex-row sm:justify-end">
          <Button type="button" variant="ghost" onClick={handleClose} disabled={isPending}>
            Cancel
          </Button>
          <Button type="button" variant="destructive" onClick={handleRemove} disabled={isPending} className="gap-2">
            {isPending && <Loader2 size={16} className="animate-spin" aria-hidden="true" />}
            {isPending ? 'Removing note…' : 'Remove note'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
