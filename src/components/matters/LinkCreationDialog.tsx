'use client'

import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Loader2, ArrowRight } from 'lucide-react'
import { createManualLink } from '@/lib/actions/document'
import { toast } from 'sonner'
import type { Database } from '@/lib/supabase/database.types'
import { useRouter } from 'next/navigation'

type LinkType = Database['public']['Enums']['link_type']

const LINK_TYPES: { value: LinkType; label: string; description: string }[] = [
  { value: 'responds_to', label: 'Responds to', description: 'Document is a response to the parent' },
  { value: 'challenges', label: 'Challenges', description: 'Document appeals or challenges the parent' },
  { value: 'arises_from', label: 'Arises from', description: 'Document originates from the parent (e.g. OIO from SCN)' },
  { value: 'summarizes', label: 'Summarizes', description: 'Document summarizes the parent (e.g. DRC-07 for OIO)' },
]

export function LinkCreationDialog({
  isOpen,
  onClose,
  sourceDoc,
  targetDoc,
  onSuccess
}: {
  isOpen: boolean
  onClose: () => void
  sourceDoc: any | null
  targetDoc: any | null
  onSuccess: () => void
}) {
  const [selectedType, setSelectedType] = useState<LinkType | ''>('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const router = useRouter()

  if (!sourceDoc || !targetDoc) return null

  const handleCreate = async () => {
    if (!selectedType) return
    setIsSubmitting(true)
    
    // Note: in ReactFlow, we drew edge from `source` to `target`.
    // In our DB:
    // "responds_to" means Child responds to Parent.
    // If user dragged from Parent to Child, then from_doc_id = Child, to_doc_id = Parent.
    // Wait, let's keep it simple: the node they started dragging from is `source`.
    // The node they dropped onto is `target`.
    // If they drag from Parent (older) to Child (newer), it means Child responds to Parent.
    // So from_doc = target, to_doc = source.
    // Or if they dragged from Child to Parent. Let's just assume we want:
    // target = older (parent), source = newer (child). But let's show it explicitly in the UI!
    
    // Actually we'll pass source and target directly as from_doc and to_doc 
    // depending on the semantic meaning. Let's make "from_doc_id" = Child, "to_doc_id" = Parent.
    
    // Let's assume user dragged from Child to Parent:
    const res = await createManualLink(sourceDoc.id, targetDoc.id, selectedType as LinkType)
    
    setIsSubmitting(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Link created successfully')
      onSuccess()
      router.refresh()
      onClose()
      setSelectedType('')
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Create Document Link</DialogTitle>
          <DialogDescription>
            Specify the relationship between these two documents.
          </DialogDescription>
        </DialogHeader>
        
        <div className="py-4 flex flex-col gap-4">
          <div className="flex items-center justify-between gap-2 p-3 bg-slate-50 rounded-lg border border-slate-200">
            <div className="flex flex-col flex-1 overflow-hidden">
              <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Source (Child)</span>
              <span className="text-sm font-medium text-slate-900 truncate">{sourceDoc.doc_type || 'Document'}</span>
              <span className="text-xs text-slate-500 truncate">{sourceDoc.reference_number || sourceDoc.id}</span>
            </div>
            
            <ArrowRight className="text-slate-400 shrink-0" />
            
            <div className="flex flex-col flex-1 overflow-hidden items-end text-right">
              <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Target (Parent)</span>
              <span className="text-sm font-medium text-slate-900 truncate">{targetDoc.doc_type || 'Document'}</span>
              <span className="text-xs text-slate-500 truncate">{targetDoc.reference_number || targetDoc.id}</span>
            </div>
          </div>

          <div className="flex flex-col gap-2 mt-2">
            <label className="text-sm font-medium text-slate-700">Relationship Type</label>
            <select 
              value={selectedType} 
              onChange={(e) => setSelectedType(e.target.value as LinkType)}
              className="w-full text-sm font-medium text-[--text-primary] bg-white border border-slate-300 focus:ring-2 focus:ring-blue-200 outline-none rounded-md px-3 py-2 shadow-sm"
            >
              <option value="" disabled>Select a relationship...</option>
              {LINK_TYPES.map(type => (
                <option key={type.value} value={type.value}>
                  {type.label} - {type.description}
                </option>
              ))}
            </select>
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={isSubmitting}>Cancel</Button>
          <Button onClick={handleCreate} disabled={!selectedType || isSubmitting}>
            {isSubmitting ? <Loader2 size={16} className="animate-spin mr-2" /> : null}
            Create Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
