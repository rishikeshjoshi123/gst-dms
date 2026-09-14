'use client'

import { useState } from 'react'
import { Check, CircleCheck } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

export function DecisionDialogSpecimen() {
  const [open, setOpen] = useState(false)

  return (
    <>
      <Button variant="outline" onClick={() => setOpen(true)}>Open confirmation specimen</Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="overflow-hidden p-0 sm:max-w-[30rem]">
          <DialogHeader className="mb-0 border-b border-[var(--border)] px-5 py-4 pr-14">
            <div className="flex items-start gap-3">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]" aria-hidden="true"><CircleCheck className="size-5" /></span>
              <div className="min-w-0">
                <DialogTitle>Apply this decision?</DialogTitle>
                <DialogDescription className="mt-1 leading-6">Confirm the selected outcome and its effect before changing the record.</DialogDescription>
              </div>
            </div>
          </DialogHeader>
          <div className="p-5">
            <p className="text-caption text-[var(--text-muted)]">Selected outcome</p>
            <div className="mt-2 rounded-[var(--radius-sm)] border border-[var(--accent)] bg-[var(--accent-muted)] p-3"><p className="text-sm font-semibold">Use the verified source value</p><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Supported by the cited document page.</p></div>
            <h3 className="mt-5 text-sm font-semibold">When confirmed</h3>
            <p className="mt-2 flex items-start gap-2 text-sm leading-6 text-[var(--text-secondary)]"><Check className="mt-1 size-4 shrink-0 text-[var(--success)]" aria-hidden="true" />The record changes, evidence remains attached, and the decision enters history.</p>
          </div>
          <DialogFooter className="mt-0 bg-[var(--bg)] px-5 py-4"><DialogClose asChild><Button variant="outline">Go back</Button></DialogClose><Button onClick={() => setOpen(false)}>Apply decision</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
