'use client'

import { ExternalLink } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import type { ComponentPropsWithoutRef } from 'react'

import { caseWikiSourceLinkPresentation } from '@/lib/notes/case-wiki-source-link'

type CaseWikiMarkdownLinkProps = ComponentPropsWithoutRef<'a'> & {
  matterId: string
  node?: unknown
  readOnly?: boolean
}

export function CaseWikiMarkdownLink({
  children,
  className,
  href = '',
  matterId,
  node,
  readOnly = false,
  ...props
}: CaseWikiMarkdownLinkProps) {
  void node
  const presentation = caseWikiSourceLinkPresentation(href, { matterId, readOnly })

  if (presentation.kind === 'unverified') {
    return (
      <span
        className="inline-flex min-h-11 flex-wrap items-center gap-x-2 gap-y-1 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--warning-muted)] px-2 py-1 text-[var(--text-primary)]"
        role="note"
      >
        <span>{children}</span>
        <span className="text-xs font-medium text-[var(--text-secondary)]">Source location unverified</span>
      </span>
    )
  }

  if (presentation.kind === 'exact') {
    return (
      <a
        {...props}
        href={presentation.href}
        className={`inline-flex min-h-11 flex-wrap items-center gap-x-2 gap-y-1 rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-2 py-1 text-[var(--primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] ${className ?? ''}`}
      >
        <span>{children}</span>
        <span className="inline-flex items-center gap-1 text-xs font-medium">
          <ExternalLink className="size-3.5" aria-hidden="true" />
          Open exact source
        </span>
      </a>
    )
  }

  return <a {...props} href={presentation.href} className={className}>{children}</a>
}

export function CaseWikiMarkdown({
  children,
  matterId,
  readOnly = false,
}: {
  children: string
  matterId: string
  readOnly?: boolean
}) {
  return (
    <ReactMarkdown
      components={{
        a: (props) => <CaseWikiMarkdownLink {...props} matterId={matterId} readOnly={readOnly} />,
      }}
    >
      {children}
    </ReactMarkdown>
  )
}
