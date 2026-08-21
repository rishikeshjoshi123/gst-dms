'use client'

import { useState } from 'react'
import { Menu, X } from 'lucide-react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import { SidebarNav } from './SidebarNav'

interface MobileNavDrawerProps {
  inboxCount?: number
  notifCount?: number
}

export function MobileNavDrawer({ inboxCount = 0, notifCount = 0 }: MobileNavDrawerProps) {
  const [isOpen, setIsOpen] = useState(false)

  return (
    <DialogPrimitive.Root open={isOpen} onOpenChange={setIsOpen}>
      <DialogPrimitive.Trigger asChild>
        <button
          type="button"
          className="-ml-2 flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] text-[var(--text-secondary)] transition-colors hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] md:hidden"
          aria-label="Open navigation menu"
        >
          <Menu size={20} />
        </button>
      </DialogPrimitive.Trigger>

      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-[var(--scrim,rgba(11,18,29,0.6))] backdrop-blur-sm data-[state=open]:animate-in data-[state=open]:fade-in data-[state=closed]:animate-out data-[state=closed]:fade-out" />
        <DialogPrimitive.Content
          aria-describedby={undefined}
          className="fixed inset-y-0 left-0 z-50 flex w-[min(280px,calc(100vw-2rem))] flex-col border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] shadow-[var(--shadow-xl)] outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-left data-[state=closed]:animate-out data-[state=closed]:slide-out-to-left"
        >
          <div className="flex h-14 shrink-0 items-center justify-between border-b border-[var(--sidebar-border,var(--border))] px-4">
            <DialogPrimitive.Title className="text-sm font-semibold tracking-wide text-[var(--on-sidebar,var(--sidebar-accent))]">
              CaseChain
            </DialogPrimitive.Title>
            <DialogPrimitive.Close asChild>
              <button
                type="button"
                className="flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] text-[var(--sidebar-text)] transition-colors hover:bg-[var(--sidebar-hover)] hover:text-[var(--on-sidebar,var(--sidebar-accent))]"
                aria-label="Close navigation menu"
              >
                <X size={18} />
              </button>
            </DialogPrimitive.Close>
          </div>

          <div
            className="flex-1 overflow-y-auto px-2 py-4"
            onClick={(event) => {
              if ((event.target as HTMLElement).closest('a')) setIsOpen(false)
            }}
          >
            <SidebarNav inboxCount={inboxCount} notifCount={notifCount} isMobile />
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  )
}
