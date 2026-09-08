import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/**
 * Merge Tailwind classes safely — combines clsx conditionals with twMerge conflict resolution.
 * Usage: cn('base-class', condition && 'conditional', { 'object-class': bool })
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Format a date as human-readable (e.g. "12 Jan 2024")
 */
export function formatDate(dateString: string | Date): string {
  const date = typeof dateString === 'string' ? new Date(dateString) : dateString
  return date.toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}

/**
 * Format a relative time (e.g. "2 days ago")
 */
export function timeAgo(dateString: string | Date): string {
  const date = typeof dateString === 'string' ? new Date(dateString) : dateString
  const now = new Date()
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000)

  if (seconds < 60) return 'just now'
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`
  return formatDate(date)
}

/**
 * Returns display-name initials without ever deriving an identity from an
 * address or identifier. Null tells Avatar to render its neutral user icon.
 */
export function getInitials(displayName?: string | null): string | null {
  const tokens = displayName?.trim().split(/\s+/).filter(Boolean) ?? []
  if (tokens.length === 0) return null

  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  const firstGraphemes = (value: string, count: number) => Array.from(segmenter.segment(value), ({ segment }) => segment).slice(0, count).join('')

  if (tokens.length === 1) return firstGraphemes(tokens[0], 2).toLocaleUpperCase()
  return `${firstGraphemes(tokens[0], 1)}${firstGraphemes(tokens[tokens.length - 1], 1)}`.toLocaleUpperCase()
}
