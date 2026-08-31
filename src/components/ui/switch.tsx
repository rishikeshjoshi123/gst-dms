'use client'

import { forwardRef, type ButtonHTMLAttributes } from 'react'

import { cn } from '@/lib/utils'

export interface SwitchProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onChange'> {
  checked: boolean
  onCheckedChange?: (checked: boolean) => void
}

const Switch = forwardRef<HTMLButtonElement, SwitchProps>(
  ({ checked, onCheckedChange, className, disabled, ...props }, ref) => (
    <button
      ref={ref}
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onCheckedChange?.(!checked)}
      className={cn(
        'touch-target relative flex size-11 shrink-0 items-center justify-center rounded-[var(--radius-sm)]',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-1 focus-visible:ring-offset-[var(--surface)]',
        'disabled:cursor-not-allowed disabled:opacity-50',
        className,
      )}
      {...props}
    >
      <span
        aria-hidden="true"
        className={cn(
          'relative h-6 w-11 rounded-[var(--radius-full)] border transition-colors motion-reduce:transition-none',
          checked
            ? 'border-[var(--accent)] bg-[var(--accent)]'
            : 'border-[var(--border-strong)] bg-[var(--bg-overlay)]',
        )}
      >
        <span
          className={cn(
            'absolute left-0.5 top-0.5 size-5 rounded-[var(--radius-full)] bg-[var(--surface)] shadow-sm transition-transform motion-reduce:transition-none',
            checked ? 'translate-x-5' : 'translate-x-0',
          )}
        />
      </span>
    </button>
  ),
)

Switch.displayName = 'Switch'

export { Switch }
