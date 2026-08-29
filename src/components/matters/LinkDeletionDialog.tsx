'use client'

import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Loader2, ArrowRight, Link2Off, Trash2 } from 'lucide-react'
import { deleteDocumentLink } from '@/lib/actions/document'
import { toast } from 'sonner'
import type { DocumentInspectorMetadata } from '@/lib/documents/inspector-metadata-shape'
import { relationshipDocumentPresentation } from '@/lib/documents/document-inspector-identity'

type LinkDialogDocument = {
  id: string
  display_title?: string | null
  storage_path?: string | null
}

export function LinkDeletionDialog({
  isOpen,
  onClose,
  linkId,
  edgeId,
  sourceDoc,
  targetDoc,
  linkType,
  sourceEffectiveMetadata,
  targetEffectiveMetadata,
  onOptimisticDelete,
  onSuccess
}: {
  isOpen: boolean
  onClose: () => void
  linkId: string | null
  edgeId: string | null
  sourceDoc: LinkDialogDocument | null
  targetDoc: LinkDialogDocument | null
  linkType?: string | null
  sourceEffectiveMetadata?: DocumentInspectorMetadata
  targetEffectiveMetadata?: DocumentInspectorMetadata
  /** Called immediately when user confirms deletion — removes edge from graph before server responds */
  onOptimisticDelete?: (edgeId: string) => void
  onSuccess?: () => void
}) {
  const [isDeleting, setIsDeleting] = useState(false)

  if (!isOpen || !sourceDoc || !targetDoc) return null

  const sourcePresentation = relationshipDocumentPresentation(sourceDoc, sourceEffectiveMetadata)
  const targetPresentation = relationshipDocumentPresentation(targetDoc, targetEffectiveMetadata)

  const handleDelete = async () => {
    if (!linkId) {
      toast.error('Cannot delete: link ID not available.')
      return
    }

    // Optimistic: remove edge immediately, before server responds
    if (edgeId && onOptimisticDelete) {
      onOptimisticDelete(edgeId)
    }
    onClose()

    // Fire server action in background
    setIsDeleting(true)
    const toastId = toast.loading('Removing document link...')
    const res = await deleteDocumentLink(linkId)
    setIsDeleting(false)

    if (res.error) {
      // Server failed — the revalidatePath in deleteDocumentLink won't fire,
      // so the edge will reappear on the next realtime/server sync automatically.
      toast.error(res.error, { id: toastId })
    } else {
      toast.success('Document link deleted successfully', { id: toastId })
      onSuccess?.()
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[440px] bg-[var(--surface)] border border-[var(--border)] shadow-xl p-0 overflow-hidden text-[var(--text-primary)]">
        <DialogHeader className="p-6 pb-2 border-b border-[var(--border)]">
          <div className="flex items-center gap-3 text-[var(--danger)] mb-1">
            <div className="p-2 bg-[var(--danger-muted)] rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--danger)_30%,transparent)]">
              <Link2Off size={20} className="text-[var(--danger)]" />
            </div>
            <DialogTitle className="text-[18px] font-semibold text-[var(--text-primary)]">
              Link Already Exists
            </DialogTitle>
          </div>
          <DialogDescription className="text-[14px] text-[var(--text-secondary)] pt-1">
            A relationship link is already established between these two documents. Would you like to delete this link?
          </DialogDescription>
        </DialogHeader>
        
        <div className="p-6 flex flex-col gap-4">
          {/* Document Relationship Card */}
          <div className="flex items-center justify-between gap-3 p-4 bg-[var(--bg)] rounded-lg border border-[var(--border)]">
            <div className="flex flex-col flex-1 overflow-hidden">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider mb-0.5">
                From
              </span>
              <span className="text-[14px] font-semibold text-[var(--text-primary)] truncate">
                {sourcePresentation.documentType}
              </span>
              <span className="text-[12px] text-[var(--text-secondary)] truncate font-mono">
                {sourcePresentation.reference}
              </span>
            </div>
            
            <div className="flex flex-col items-center justify-center shrink-0 px-2">
              {linkType && (
                <span className="text-[9px] font-bold uppercase tracking-wider bg-[var(--border-subtle)] text-[var(--text-secondary)] border border-[var(--border)] px-1.5 py-0.5 rounded mb-1">
                  {linkType.replace('_', ' ')}
                </span>
              )}
              <ArrowRight className="text-[var(--text-muted)]" size={16} />
            </div>
            
            <div className="flex flex-col flex-1 overflow-hidden items-end text-right">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider mb-0.5">
                To
              </span>
              <span className="text-[14px] font-semibold text-[var(--text-primary)] truncate">
                {targetPresentation.documentType}
              </span>
              <span className="text-[12px] text-[var(--text-secondary)] truncate font-mono">
                {targetPresentation.reference}
              </span>
            </div>
          </div>
        </div>

        <DialogFooter className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
          <Button
            type="button"
            variant="ghost"
            onClick={onClose}
            disabled={isDeleting}
            className="text-[14px] font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]"
          >
            Cancel
          </Button>
          <Button
            type="button"
            onClick={handleDelete}
            disabled={isDeleting || !linkId}
            className="inline-flex items-center justify-center text-[14px] font-semibold bg-[var(--danger)] hover:opacity-90 text-white shadow-sm gap-2 rounded-[var(--radius-sm)] px-4"
          >
            {isDeleting ? (
              <>
                <Loader2 size={16} className="animate-spin" />
                Deleting Link...
              </>
            ) : (
              <>
                <Trash2 size={15} />
                Delete Link
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
