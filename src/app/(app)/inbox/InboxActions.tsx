'use client'

import { useState, useTransition } from 'react'
import { assignStagedDocument, discardStagedDocument } from '@/lib/actions/inbox'
import { Button } from '@/components/ui/button'
import { Check, X } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'

export function InboxActions({ stagedId, suggestedMatterId }: { stagedId: string, suggestedMatterId?: string }) {
  const [isPending, startTransition] = useTransition()
  const [isConfirmOpen, setIsConfirmOpen] = useState(false)
  const router = useRouter()

  function handleAssign() {
    if (!suggestedMatterId) return
    startTransition(async () => {
      await assignStagedDocument(stagedId, suggestedMatterId)
      router.refresh()
    })
  }

  function handleDiscard() {
    startTransition(async () => {
      await discardStagedDocument(stagedId)
      setIsConfirmOpen(false)
      router.refresh()
    })
  }

  return (
    <>
      <div className="flex items-center gap-2">
        <Button 
          variant="ghost" 
          className="text-red-500 hover:text-red-600 hover:bg-red-500/10" 
          onClick={() => setIsConfirmOpen(true)}
          disabled={isPending}
        >
          <X size={14} className="mr-1.5" />
          Discard
        </Button>

        {suggestedMatterId ? (
          <Button onClick={handleAssign} disabled={isPending}>
            <Check size={14} className="mr-1.5" />
            Assign to Matter
          </Button>
        ) : (
          <Button variant="default" disabled title="Select a matter first">
            Assign...
          </Button>
        )}
      </div>

      <ConfirmDialog
        isOpen={isConfirmOpen}
        onClose={() => setIsConfirmOpen(false)}
        onConfirm={handleDiscard}
        title="Discard Document?"
        description="Are you sure you want to discard this document? It will be permanently deleted."
        confirmText="Discard Document"
        variant="destructive"
        isPending={isPending}
      />
    </>
  )
}
