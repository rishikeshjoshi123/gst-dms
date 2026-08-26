import { forwardRef, type HTMLAttributes, type ReactNode } from 'react'

import { cn } from '@/lib/utils'

export interface MatterSectionWorkbarProps extends HTMLAttributes<HTMLDivElement> {
  views: ReactNode
  context?: ReactNode
  actions: ReactNode
  wrap?: boolean
}

const MatterSectionWorkbar = forwardRef<HTMLDivElement, MatterSectionWorkbarProps>(
  ({ views, context, actions, wrap = false, className, ...props }, ref) => (
    <div
      ref={ref}
      className={cn(
        'flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 lg:px-4',
        wrap && 'flex-wrap py-1.5 lg:flex-nowrap lg:py-0',
        className,
      )}
      {...props}
    >
      <div className={cn('flex min-w-0 items-center', wrap && 'flex-1 sm:flex-none')}>{views}</div>
      {context}
      <div className="ml-auto flex shrink-0 items-center gap-2">{actions}</div>
    </div>
  ),
)

MatterSectionWorkbar.displayName = 'MatterSectionWorkbar'

export { MatterSectionWorkbar }
