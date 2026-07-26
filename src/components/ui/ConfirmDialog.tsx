'use client'

import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { AlertTriangle, Loader2 } from 'lucide-react'

export function ConfirmDialog({
  isOpen,
  onClose,
  onConfirm,
  title,
  description,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  variant = 'destructive',
  isPending = false
}: {
  isOpen: boolean
  onClose: () => void
  onConfirm: () => void
  title: string
  description: string
  confirmText?: string
  cancelText?: string
  variant?: 'destructive' | 'default' | 'outline'
  isPending?: boolean
}) {
  return (
    <Dialog open={isOpen} onOpenChange={(open) => !open && !isPending && onClose()}>
      <DialogContent className="sm:max-w-[420px] bg-[var(--surface)] border border-[var(--border)] shadow-xl p-0 overflow-hidden text-[var(--text-primary)]">
        <DialogHeader className="p-6 pb-2 border-b border-[var(--border)]">
          <div className="flex items-center gap-3 text-red-500 dark:text-red-400 mb-1">
            <div className="p-2 bg-red-500/10 rounded-md border border-red-500/20">
              <AlertTriangle size={20} className="text-red-500 dark:text-red-400" />
            </div>
            <DialogTitle className="text-[18px] font-semibold text-[var(--text-primary)]">
              {title}
            </DialogTitle>
          </div>
          <DialogDescription className="text-[14px] text-[var(--text-secondary)] pt-1 leading-relaxed">
            {description}
          </DialogDescription>
        </DialogHeader>

        <DialogFooter className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
          <Button
            type="button"
            variant="ghost"
            onClick={onClose}
            disabled={isPending}
            className="text-[14px] font-medium text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]"
          >
            {cancelText}
          </Button>
          <Button
            type="button"
            onClick={onConfirm}
            disabled={isPending}
            variant={variant === 'destructive' ? 'destructive' : 'default'}
            className="inline-flex items-center justify-center text-[14px] font-semibold shadow-sm gap-2"
          >
            {isPending ? (
              <>
                <Loader2 size={16} className="animate-spin" />
                Processing...
              </>
            ) : (
              confirmText
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
