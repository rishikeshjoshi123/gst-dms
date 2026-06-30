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
          'w-full h-10 px-3.5 rounded-[--radius-md] text-sm',
          'bg-[--bg-overlay] text-[--text-primary] placeholder:text-[--text-muted]',
          'border transition-all duration-[--duration-fast]',
          error
            ? 'border-[--danger] focus:ring-2 focus:ring-red-500/20'
            : 'border-[--border-default] focus:border-[--accent] focus:ring-2 focus:ring-[--accent-ring]',
          'outline-none',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          'autofill:bg-[--bg-overlay]',
          '[&:-webkit-autofill]:bg-[--bg-overlay]',
          className
        )}
        {...props}
      />
    )
  }
)
Input.displayName = 'Input'

export { Input }
