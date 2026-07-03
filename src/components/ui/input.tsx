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
          'bg-white text-[--text-primary] placeholder:text-[--text-muted]',
          'border transition-all duration-[--duration-fast]',
          error
            ? 'border-[--danger] focus:ring-2 focus:ring-[--danger]'
            : 'border-[--border-strong] focus:border-[--accent] focus:ring-2 focus:ring-[--accent]',
          'outline-none',
          'disabled:opacity-50 disabled:cursor-not-allowed',
          'autofill:bg-white',
          '[&:-webkit-autofill]:bg-white',
          className
        )}
        {...props}
      />
    )
  }
)
Input.displayName = 'Input'

export { Input }
