'use client'

import * as DialogPrimitive from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import { cn } from '@/lib/utils'

const Dialog = DialogPrimitive.Root
const DialogTrigger = DialogPrimitive.Trigger
const DialogPortal = DialogPrimitive.Portal
const DialogClose = DialogPrimitive.Close

function DialogOverlay({ className, ...props }: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>) {
  return (
    <DialogPrimitive.Overlay
      className={cn(
        'fixed inset-0 z-50 bg-[var(--scrim,rgba(11,18,29,0.6))] backdrop-blur-sm',
        'data-[state=open]:animate-scale-in data-[state=closed]:opacity-0',
          'transition-all duration-[var(--duration-base)]',
        className
      )}
      {...props}
    />
  )
}

function DialogContent({
  className,
  children,
  showClose = true,
  ...props
}: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content> & { showClose?: boolean }) {
  return (
    <DialogPortal>
      <DialogOverlay />
      <DialogPrimitive.Content
        className={cn(
          'fixed left-1/2 top-1/2 z-50 -translate-x-1/2 -translate-y-1/2',
          'w-full max-w-[calc(100vw-2rem)] sm:max-w-md',
          'bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-md)]',
          'shadow-[var(--shadow-xl)]',
          'p-6',
          'animate-scale-in',
          'focus:outline-none',
          className
        )}
        {...props}
      >
        {children}
        {showClose && (
          <DialogPrimitive.Close className="absolute right-2 top-2 flex h-11 w-11 items-center justify-center text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-[var(--radius-sm)] transition-colors">
            <X size={16} />
          </DialogPrimitive.Close>
        )}
      </DialogPrimitive.Content>
    </DialogPortal>
  )
}

function DialogHeader({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn('flex flex-col gap-1.5 mb-5', className)} {...props} />
  )
}

function DialogTitle({ className, ...props }: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Title>) {
  return (
    <DialogPrimitive.Title
      className={cn('text-[18px] font-semibold text-[var(--text-primary)]', className)}
      {...props}
    />
  )
}

function DialogDescription({ className, ...props }: React.ComponentPropsWithoutRef<typeof DialogPrimitive.Description>) {
  return (
    <DialogPrimitive.Description
      className={cn('text-[14px] text-[var(--text-muted)]', className)}
      {...props}
    />
  )
}

function DialogFooter({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('flex flex-col-reverse sm:flex-row sm:items-center sm:justify-end gap-2 mt-6 pt-4 border-t border-[var(--border-subtle)]', className)}
      {...props}
    />
  )
}

export {
  Dialog, DialogTrigger, DialogClose, DialogContent,
  DialogHeader, DialogTitle, DialogDescription, DialogFooter,
}
