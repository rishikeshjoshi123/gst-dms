import { forwardRef } from 'react'
import { cn } from '@/lib/utils'

export interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  error?: string
}

const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, error, type = 'text', ...props }, ref) => {
    return (
      <input
        ref={ref}
        type={type}
        className={cn(
          'w-full h-10 px-3.5 rounded-[--radius-sm] text-[14px]',
          'bg-[var(--surface)] text-[var(--text-primary)] placeholder:text-[var(--text-muted)]',
          'border transition-all duration-[--duration-fast]',
          error
            ? 'border-[--danger] focus:ring-2 focus:ring-[--danger]/20'
            : 'border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20',
          'outline-none',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          className
        )}
        {...props}
      />
    )
  }
)
Input.displayName = 'Input'

export { Input }
