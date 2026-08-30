import { forwardRef } from 'react'

import { cn } from '@/lib/utils'

export type TableProps = React.TableHTMLAttributes<HTMLTableElement>

const Table = forwardRef<HTMLTableElement, TableProps>(({ className, ...props }, ref) => (
  <table ref={ref} className={cn('w-full text-left text-sm', className)} {...props} />
))
Table.displayName = 'Table'

export interface TableHeaderProps extends React.HTMLAttributes<HTMLTableSectionElement> {
  sticky?: boolean
}

const TableHeader = forwardRef<HTMLTableSectionElement, TableHeaderProps>(({ className, sticky = false, ...props }, ref) => (
  <thead
    ref={ref}
    className={cn('bg-[var(--bg-overlay)] text-[var(--text-muted)]', sticky && 'sticky top-0 z-10', className)}
    {...props}
  />
))
TableHeader.displayName = 'TableHeader'

export type TableBodyProps = React.HTMLAttributes<HTMLTableSectionElement>

const TableBody = forwardRef<HTMLTableSectionElement, TableBodyProps>(({ className, ...props }, ref) => (
  <tbody ref={ref} className={cn('[&_tr:last-child]:border-b-0', className)} {...props} />
))
TableBody.displayName = 'TableBody'

export interface TableRowProps extends React.HTMLAttributes<HTMLTableRowElement> {
  interactive?: boolean
  selected?: boolean
}

const TableRow = forwardRef<HTMLTableRowElement, TableRowProps>(({ className, interactive = false, selected = false, ...props }, ref) => (
  <tr
    ref={ref}
    aria-selected={selected || undefined}
    className={cn(
      'border-b border-[var(--border-subtle)] transition-colors',
      interactive && 'hover:bg-[var(--surface-hover)]',
      selected && 'bg-[var(--accent-muted)]',
      className,
    )}
    {...props}
  />
))
TableRow.displayName = 'TableRow'

export type TableHeadProps = React.ThHTMLAttributes<HTMLTableCellElement>

const TableHead = forwardRef<HTMLTableCellElement, TableHeadProps>(({ className, ...props }, ref) => (
  <th ref={ref} className={cn('h-9 px-3 py-2 align-middle text-xs font-medium', className)} {...props} />
))
TableHead.displayName = 'TableHead'

export type TableCellProps = React.TdHTMLAttributes<HTMLTableCellElement>

const TableCell = forwardRef<HTMLTableCellElement, TableCellProps>(({ className, ...props }, ref) => (
  <td ref={ref} className={cn('px-3 py-2.5 align-middle', className)} {...props} />
))
TableCell.displayName = 'TableCell'

export type TableCaptionProps = React.HTMLAttributes<HTMLTableCaptionElement>

const TableCaption = forwardRef<HTMLTableCaptionElement, TableCaptionProps>(({ className, ...props }, ref) => (
  <caption ref={ref} className={cn('sr-only', className)} {...props} />
))
TableCaption.displayName = 'TableCaption'

export { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow }
