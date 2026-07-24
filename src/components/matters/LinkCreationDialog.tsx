'use client'

import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Loader2, ArrowDown } from 'lucide-react'
import { createManualLink } from '@/lib/actions/document'
import { toast } from 'sonner'
import type { Database } from '@/lib/supabase/database.types'
import { useRouter } from 'next/navigation'

type LinkType = Database['public']['Enums']['link_type']

// Relationship types are always described from the child's perspective towards the parent.
// e.g. "Child responds_to Parent" means the child document is a response to the parent document.
const LINK_TYPES: { value: LinkType; label: string; description: string }[] = [
  { value: 'responds_to', label: 'Responds To', description: 'Child is a reply or response to the parent (e.g. Reply to SCN)' },
  { value: 'challenges', label: 'Challenges', description: 'Child appeals or challenges the parent (e.g. APL-01 challenges OIO)' },
  { value: 'arises_from', label: 'Arises From', description: 'Child originates as a consequence of the parent (e.g. OIO arises from SCN)' },
  { value: 'summarizes', label: 'Summarizes', description: 'Child is a summary or demand statement of the parent (e.g. DRC-07 summarizes OIO)' },
]

export function LinkCreationDialog({
  isOpen,
  onClose,
  sourceDoc,  // ReactFlow source = node where drag started = bottom handle = PARENT
  targetDoc,  // ReactFlow target = node where drag ended = top handle = CHILD
  onSuccess
}: {
  isOpen: boolean
  onClose: () => void
  sourceDoc: any | null  // This is the PARENT document
  targetDoc: any | null  // This is the CHILD document
  onSuccess: () => void
}) {
  const [selectedType, setSelectedType] = useState<LinkType | ''>('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const router = useRouter()

  if (!sourceDoc || !targetDoc) return null

  // Convention: sourceDoc = drag start = bottom handle = PARENT
  //             targetDoc = drag end = top handle = CHILD
  const parentDoc = sourceDoc
  const childDoc = targetDoc

  const handleCreate = async () => {
    if (!selectedType) return
    setIsSubmitting(true)
    
    // DB convention: from_doc_id = CHILD, to_doc_id = PARENT
    // The link_type describes what the child does to the parent.
    const res = await createManualLink(childDoc.id, parentDoc.id, selectedType as LinkType)
    
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

  const selectedTypeInfo = LINK_TYPES.find(t => t.value === selectedType)

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[460px] bg-[var(--surface)] border border-[var(--border)]">
        <DialogHeader>
          <DialogTitle className="text-[var(--text-primary)]">Create Document Link</DialogTitle>
          <DialogDescription className="text-[var(--text-muted)]">
            Specify the relationship between these two documents. The child document&apos;s relationship points toward the parent.
          </DialogDescription>
        </DialogHeader>
        
        <div className="py-4 flex flex-col gap-4">
          {/* Visual parent → child diagram */}
          <div className="flex flex-col items-stretch gap-1">
            {/* Parent */}
            <div className="flex flex-col p-3 bg-[var(--bg)] rounded-lg border border-[var(--border)] relative">
              <span className="text-[10px] font-bold text-[var(--primary)] uppercase tracking-wider mb-1">Parent Document</span>
              <span className="text-sm font-semibold text-[var(--text-primary)] truncate">{parentDoc.doc_type || 'Document'}</span>
              <span className="text-xs text-[var(--text-muted)] truncate font-mono">{parentDoc.reference_number || parentDoc.id}</span>
            </div>

            {/* Arrow with relationship label */}
            <div className="flex items-center justify-center gap-2 py-1">
              <div className="flex-1 h-px bg-[var(--border)]" />
              <div className="flex flex-col items-center gap-0.5">
                <ArrowDown size={16} className="text-[var(--primary)]" />
                {selectedTypeInfo && (
                  <span className="text-[10px] font-bold text-[var(--primary)] uppercase tracking-wider whitespace-nowrap">
                    {childDoc.doc_type || 'Child'} {selectedTypeInfo.label}
                  </span>
                )}
              </div>
              <div className="flex-1 h-px bg-[var(--border)]" />
            </div>

            {/* Child */}
            <div className="flex flex-col p-3 bg-[var(--bg)] rounded-lg border border-[var(--border)]">
              <span className="text-[10px] font-bold text-emerald-600 dark:text-emerald-400 uppercase tracking-wider mb-1">Child Document</span>
              <span className="text-sm font-semibold text-[var(--text-primary)] truncate">{childDoc.doc_type || 'Document'}</span>
              <span className="text-xs text-[var(--text-muted)] truncate font-mono">{childDoc.reference_number || childDoc.id}</span>
            </div>
          </div>

          <div className="flex flex-col gap-2 mt-1">
            <label className="text-xs font-semibold text-[var(--text-secondary)] uppercase tracking-wider">
              Relationship Type <span className="text-[var(--text-muted)] normal-case font-normal">(how child relates to parent)</span>
            </label>
            <select 
              value={selectedType} 
              onChange={(e) => setSelectedType(e.target.value as LinkType)}
              className="w-full text-sm font-medium text-[var(--text-primary)] bg-[var(--bg)] border border-[var(--border-strong)] focus:ring-2 focus:ring-[var(--primary)] outline-none rounded-md px-3 py-2 shadow-sm cursor-pointer"
            >
              <option value="" disabled>Select a relationship...</option>
              {LINK_TYPES.map(type => (
                <option key={type.value} value={type.value}>
                  {type.label} — {type.description}
                </option>
              ))}
            </select>
            {selectedTypeInfo && (
              <p className="text-xs text-[var(--text-muted)] italic pl-1">{selectedTypeInfo.description}</p>
            )}
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={isSubmitting} className="text-[var(--text-secondary)]">Cancel</Button>
          <Button onClick={handleCreate} disabled={!selectedType || isSubmitting}>
            {isSubmitting ? <Loader2 size={16} className="animate-spin mr-2" /> : null}
            Create Link
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
