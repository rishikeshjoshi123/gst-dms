'use client'

import { X } from 'lucide-react'
import { PdfViewer } from '@/components/ui/pdf-viewer'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'

interface DocumentViewerModalProps {
  url: string
  title?: string
  onClose: () => void
  returnFocusRef?: React.RefObject<HTMLButtonElement | null>
}

export function DocumentViewerModal({ url, title = 'Document Viewer', onClose, returnFocusRef }: DocumentViewerModalProps) {
  return (
    <Dialog open onOpenChange={(open) => { if (!open) onClose() }}>
      <DialogContent
        showClose={false}
        className="flex h-[calc(100dvh-2rem)] max-h-[90vh] w-[calc(100vw-2rem)] max-w-6xl flex-col overflow-hidden p-0 sm:h-[calc(100dvh-4rem)] sm:w-[calc(100vw-4rem)]"
        onCloseAutoFocus={(event) => {
          if (returnFocusRef?.current) {
            event.preventDefault()
            returnFocusRef.current.focus()
          }
        }}
      >
        <DialogHeader className="mb-0 flex shrink-0 flex-row items-center justify-between border-b border-[var(--border)] bg-[var(--bg)] p-4">
          <DialogTitle className="min-w-0 truncate pr-4 text-[16px] leading-none">
            {title}
          </DialogTitle>
          <Button type="button" variant="ghost" size="sm" onClick={onClose} className="shrink-0">
            <X size={16} aria-hidden="true" />
            Close
          </Button>
        </DialogHeader>

        {/* Viewer Content */}
        <div className="relative min-h-0 flex-1 overflow-hidden bg-[var(--border)]">
          <PdfViewer url={url} />
        </div>
      </DialogContent>
    </Dialog>
  )
}
