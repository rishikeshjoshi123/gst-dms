'use client'
import * as LabelPrimitive from '@radix-ui/react-label'
import { cn } from '@/lib/utils'

export interface LabelProps extends React.ComponentPropsWithoutRef<typeof LabelPrimitive.Root> {
  required?: boolean
}

function Label({ className, required, children, ...props }: LabelProps) {
  return (
    <LabelPrimitive.Root
      className={cn(
        'block text-[12px] font-medium uppercase tracking-wide text-[--text-secondary] mb-1.5',
        'select-none',
        className
      )}
      {...props}
    >
      {children}
      {required && <span className="ml-0.5 text-[--danger]">*</span>}
    </LabelPrimitive.Root>
  )
}

/** Convenient wrapper: Label + Input + error text */
export function FormField({
  label,
  required,
  error,
  hint,
  children,
  className,
}: {
  label: string
  required?: boolean
  error?: string
  hint?: string
  children: React.ReactNode
  className?: string
}) {
  return (
    <div className={cn('flex flex-col', className)}>
      <Label required={required}>{label}</Label>
      {hint && <p className="mb-2 text-xs text-[--text-muted]">{hint}</p>}
      {children}
      {error && (
        <p className="mt-1 text-xs text-[--danger] animate-fade-in">{error}</p>
      )}
    </div>
  )
}

export { Label }
