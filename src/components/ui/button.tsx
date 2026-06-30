import { forwardRef } from 'react'
import { cn } from '@/lib/utils'

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'default' | 'secondary' | 'outline' | 'ghost' | 'destructive' | 'link'
  size?: 'sm' | 'md' | 'lg' | 'icon'
  loading?: boolean
}

const variants = {
  default:
    'bg-[--accent] text-white hover:bg-[--accent-hover] shadow-sm hover:shadow-[--shadow-glow]',
  secondary:
    'bg-[--bg-overlay] text-[--text-primary] hover:bg-[--bg-muted] border border-[--border-default]',
  outline:
    'bg-transparent text-[--text-primary] border border-[--border-default] hover:bg-[--bg-overlay] hover:border-[--border-strong]',
  ghost:
    'bg-transparent text-[--text-secondary] hover:bg-[--bg-overlay] hover:text-[--text-primary]',
  destructive:
    'bg-[--danger] text-white hover:opacity-90',
  link:
    'bg-transparent text-[--accent] hover:text-[--accent-hover] underline-offset-4 hover:underline p-0 h-auto',
}

const sizes = {
  sm:   'h-8 px-3 text-xs gap-1.5',
  md:   'h-9 px-4 text-sm gap-2',
  lg:   'h-11 px-6 text-sm gap-2.5',
  icon: 'h-9 w-9',
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = 'default', size = 'md', loading, disabled, children, ...props }, ref) => {
    return (
      <button
        ref={ref}
        disabled={disabled || loading}
        className={cn(
          // Base styles
          'inline-flex items-center justify-center rounded-[--radius-md] font-medium',
          'transition-all duration-[--duration-fast] ease-[--ease-smooth]',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[--accent-ring] focus-visible:ring-offset-1 focus-visible:ring-offset-[--bg-base]',
          'disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
          'select-none cursor-pointer',
          variants[variant],
          sizes[size],
          className
        )}
        {...props}
      >
        {loading ? (
          <>
            <span className="spinner" />
            {children}
          </>
        ) : children}
      </button>
    )
  }
)
Button.displayName = 'Button'

export { Button }
