import { cn } from '@/lib/utils'

type BadgeVariant = 'default' | 'success' | 'warning' | 'danger' | 'incoming' | 'outgoing' | 'muted'

interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: BadgeVariant
  dot?: boolean
}

const variantStyles: Record<BadgeVariant, string> = {
  default:  'bg-[--accent-muted] text-[--accent-hover] border-[--accent]/20',
  success:  'bg-[--success-muted] text-[--success] border-green-500/20',
  warning:  'bg-[--warning-muted] text-[--warning] border-amber-500/20',
  danger:   'bg-[--danger-muted] text-[--danger] border-red-500/20',
  incoming: 'bg-[--incoming-muted] text-[--incoming] border-orange-500/20',
  outgoing: 'bg-[--outgoing-muted] text-[--outgoing] border-indigo-500/20',
  muted:    'bg-[--bg-overlay] text-[--text-muted] border-[--border-subtle]',
}

const dotColors: Record<BadgeVariant, string> = {
  default:  'bg-[--accent]',
  success:  'bg-[--success]',
  warning:  'bg-[--warning]',
  danger:   'bg-[--danger]',
  incoming: 'bg-[--incoming]',
  outgoing: 'bg-[--outgoing]',
  muted:    'bg-[--text-muted]',
}

export function Badge({ className, variant = 'default', dot, children, ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium border',
        variantStyles[variant],
        className
      )}
      {...props}
    >
      {dot && <span className={cn('status-dot', dotColors[variant])} />}
      {children}
    </span>
  )
}
