'use client'

import { useState, useTransition } from 'react'
import { assignStagedDocument, discardStagedDocument } from '@/lib/actions/inbox'
import { Button } from '@/components/ui/button'
import { Check, X, Loader2 } from 'lucide-react'
import { useRouter } from 'next/navigation'

export function InboxActions({ stagedId, suggestedMatterId }: { stagedId: string, suggestedMatterId?: string }) {
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  function handleAssign() {
    if (!suggestedMatterId) return
    startTransition(async () => {
      await assignStagedDocument(stagedId, suggestedMatterId)
      router.refresh()
    })
  }

  function handleDiscard() {
    if (!confirm('Are you sure you want to discard this document? It will be deleted permanently.')) return
    startTransition(async () => {
      await discardStagedDocument(stagedId)
      router.refresh()
    })
  }

  return (
    <div className="flex items-center gap-2">
      <Button 
        variant="ghost" 
        className="text-[--danger] hover:text-[--danger] hover:bg-[--danger-muted]" 
        onClick={handleDiscard}
        disabled={isPending}
      >
        <X size={14} className="mr-1.5" />
        Discard
      </Button>

      {suggestedMatterId ? (
        <Button onClick={handleAssign} loading={isPending}>
          <Check size={14} className="mr-1.5" />
          Assign to Matter
        </Button>
      ) : (
        <Button variant="default" disabled title="Select a matter first">
          Assign...
        </Button>
      )}
    </div>
  )
}
