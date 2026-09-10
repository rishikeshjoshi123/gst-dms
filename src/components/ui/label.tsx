'use client'
import * as LabelPrimitive from '@radix-ui/react-label'
import { cloneElement } from 'react'
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
type FormFieldControlProps = {
  'aria-describedby'?: string
  'aria-errormessage'?: string
  'aria-invalid'?: React.AriaAttributes['aria-invalid']
}

export function FormField({
  label,
  htmlFor,
  required,
  error,
  hint,
  children,
  className,
}: {
  label: string
  htmlFor: string
  required?: boolean
  error?: string
  hint?: string
  children: React.ReactElement<FormFieldControlProps>
  className?: string
}) {
  const hintId = `${htmlFor}-hint`
  const errorId = `${htmlFor}-error`
  const describedBy = Array.from(new Set([
    ...(children.props['aria-describedby']?.split(/\s+/).filter(Boolean) ?? []),
    ...(hint ? [hintId] : []),
    ...(error ? [errorId] : []),
  ])).join(' ') || undefined
  const control = cloneElement(children, {
    'aria-describedby': describedBy,
    'aria-errormessage': error ? errorId : children.props['aria-errormessage'],
    'aria-invalid': error ? true : children.props['aria-invalid'],
  })

  return (
    <div className={cn('flex flex-col', className)}>
      <Label htmlFor={htmlFor} required={required}>{label}</Label>
      {hint && <p id={hintId} className="mb-2 text-xs text-[--text-muted]">{hint}</p>}
      {control}
      {error && (
        <p id={errorId} role="alert" className="mt-1 text-xs text-[--danger] animate-fade-in">{error}</p>
      )}
    </div>
  )
}

export { Label }
