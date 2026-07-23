'use client'

import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Loader2, ArrowRight, Link2Off, Trash2 } from 'lucide-react'
import { deleteDocumentLink } from '@/lib/actions/document'
import { toast } from 'sonner'
import { useRouter } from 'next/navigation'

export function LinkDeletionDialog({
  isOpen,
  onClose,
  linkId,
  sourceDoc,
  targetDoc,
  linkType,
  onSuccess
}: {
  isOpen: boolean
  onClose: () => void
  linkId: string | null
  sourceDoc: any | null
  targetDoc: any | null
  linkType?: string | null
  onSuccess?: () => void
}) {
  const [isDeleting, setIsDeleting] = useState(false)
  const router = useRouter()

  if (!isOpen || !sourceDoc || !targetDoc || !linkId) return null

  const handleDelete = async () => {
    setIsDeleting(true)
    const toastId = toast.loading('Removing document link...')
    const res = await deleteDocumentLink(linkId)
    setIsDeleting(false)

    if (res.error) {
      toast.error(res.error, { id: toastId })
    } else {
      toast.success('Document link deleted successfully', { id: toastId })
      onSuccess?.()
      router.refresh()
      onClose()
    }
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[440px] bg-white border border-[#E5E2DC] shadow-xl p-0 overflow-hidden">
        <DialogHeader className="p-6 pb-2 border-b border-[#E5E2DC]">
          <div className="flex items-center gap-3 text-red-600 mb-1">
            <div className="p-2 bg-red-50 rounded-md border border-red-100">
              <Link2Off size={20} className="text-red-600" />
            </div>
            <DialogTitle className="text-[18px] font-semibold text-[#1C1917]">
              Link Already Exists
            </DialogTitle>
          </div>
          <DialogDescription className="text-[14px] text-[#78716C] pt-1">
            A relationship link is already established between these two documents. Would you like to delete this link?
          </DialogDescription>
        </DialogHeader>
        
        <div className="p-6 flex flex-col gap-4">
          {/* Document Relationship Card */}
          <div className="flex items-center justify-between gap-3 p-4 bg-[#FAFAF9] rounded-lg border border-[#E5E2DC]">
            <div className="flex flex-col flex-1 overflow-hidden">
              <span className="text-[11px] font-semibold text-[#78716C] uppercase tracking-wider mb-0.5">
                From
              </span>
              <span className="text-[14px] font-semibold text-[#1C1917] truncate">
                {sourceDoc.doc_type || 'Document'}
              </span>
              <span className="text-[12px] text-[#78716C] truncate font-mono">
                {sourceDoc.reference_number || sourceDoc.storage_path?.split('/').pop() || 'Doc A'}
              </span>
            </div>
            
            <div className="flex flex-col items-center justify-center shrink-0 px-2">
              {linkType && (
                <span className="text-[9px] font-bold uppercase tracking-wider bg-stone-200 text-stone-700 px-1.5 py-0.5 rounded mb-1">
                  {linkType.replace('_', ' ')}
                </span>
              )}
              <ArrowRight className="text-[#A8A29E]" size={16} />
            </div>
            
            <div className="flex flex-col flex-1 overflow-hidden items-end text-right">
              <span className="text-[11px] font-semibold text-[#78716C] uppercase tracking-wider mb-0.5">
                To
              </span>
              <span className="text-[14px] font-semibold text-[#1C1917] truncate">
                {targetDoc.doc_type || 'Document'}
              </span>
              <span className="text-[12px] text-[#78716C] truncate font-mono">
                {targetDoc.reference_number || targetDoc.storage_path?.split('/').pop() || 'Doc B'}
              </span>
            </div>
          </div>
        </div>

        <DialogFooter className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[#E5E2DC] bg-[#FAFAF9]">
          <Button
            type="button"
            variant="ghost"
            onClick={onClose}
            disabled={isDeleting}
            className="text-[14px] font-medium text-[#1C1917] hover:bg-stone-200/60"
          >
            Cancel
          </Button>
          <Button
            type="button"
            onClick={handleDelete}
            disabled={isDeleting}
            className="inline-flex items-center justify-center text-[14px] font-semibold bg-red-600 hover:bg-red-700 text-white shadow-sm gap-2"
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
