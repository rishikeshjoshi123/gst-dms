import { cn } from '@/lib/utils'

type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'incoming' | 'outgoing' | 'muted' | 'outline'

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant
  dot?: boolean
  fixedWidth?: 'sm' | 'md' | 'lg'
}

const variantStyles: Record<BadgeVariant, string> = {
  default:  'bg-[var(--accent-muted)] text-[var(--accent-hover)] border-[color-mix(in_srgb,var(--accent)_24%,transparent)]',
  success:  'bg-[var(--success-muted)] text-[var(--success)] border-[color-mix(in_srgb,var(--success)_24%,transparent)]',
  warning:  'bg-[var(--warning-muted)] text-[var(--warning)] border-[color-mix(in_srgb,var(--warning)_24%,transparent)]',
  danger:   'bg-[var(--danger-muted)] text-[var(--danger)] border-[color-mix(in_srgb,var(--danger)_24%,transparent)]',
  incoming: 'bg-[var(--incoming-muted)] text-[var(--incoming)] border-[color-mix(in_srgb,var(--incoming)_24%,transparent)]',
  outgoing: 'bg-[var(--outgoing-muted)] text-[var(--outgoing)] border-[color-mix(in_srgb,var(--outgoing)_24%,transparent)]',
  muted:    'bg-[var(--bg-overlay)] text-[var(--text-muted)] border-[var(--border-subtle)]',
  outline:  'bg-transparent text-[var(--text-primary)] border-[var(--border-strong)]',
}

const fixedWidths = { sm: 'w-16', md: 'w-20', lg: 'w-24' }

const dotColors: Record<BadgeVariant, string> = {
  default:  'bg-[--accent]',
  success:  'bg-[--success]',
  warning:  'bg-[--warning]',
  danger:   'bg-[--danger]',
  incoming: 'bg-[--incoming]',
  outgoing: 'bg-[--outgoing]',
  muted:    'bg-[--text-muted]',
  outline:  'bg-[--text-primary]',
}

export function Badge({ className, variant = 'default', dot, fixedWidth, children, ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex min-h-6 items-center justify-center gap-1.5 rounded-full border px-2 py-0.5 text-xs font-medium whitespace-nowrap',
        variantStyles[variant],
        fixedWidth && fixedWidths[fixedWidth],
        className
      )}
      {...props}
    >
      {dot && <span className={cn('status-dot', dotColors[variant])} />}
      {children}
    </span>
  )
}
