import Link from 'next/link'
import { Badge } from '@/components/ui/badge'
import { reviewFieldLabel, type ReviewQueueItem } from '@/lib/review/model'

export function NeedsAttentionPanel({ documents }: { documents: ReviewQueueItem[] }) {
  if (documents.length === 0) return null
  return <section className="mb-8 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
    <header className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] px-4 py-3"><h2 className="text-section-heading">Needs attention</h2><Link href="/review" className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline">View all Review items</Link></header>
    <div className="divide-y divide-[var(--border)]">{documents.map(item => <div key={item.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
      <div className="min-w-0 flex-1"><h3 className="break-words text-sm font-medium">{item.document_title || 'Document'}</h3><p className="text-sm text-[var(--text-secondary)]">{item.type === 'processing_recovery' ? 'Continue document manually' : item.type === 'ambiguous_placement' ? 'Choose a Matter destination' : `Resolve ${reviewFieldLabel(item.field_path)}`}</p><p className="break-words text-caption text-[var(--text-muted)]">{item.client_name} · {item.matter_title}</p></div>
      <Badge variant="warning" fixedWidth="lg">Needs review</Badge><Link href={`/review?item=${item.id}`} className="inline-flex min-h-11 items-center text-sm text-[var(--primary)] underline">Open Review</Link>
    </div>)}</div>
  </section>
}
