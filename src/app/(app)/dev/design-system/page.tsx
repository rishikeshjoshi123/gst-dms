import { Check, CircleAlert, Clock3, FileText, Loader2 } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

export const metadata = { title: 'Civic Ink Design System' }

const colors = [
  ['Ink', 'var(--sidebar-bg)', 'Navigation'],
  ['Paper', 'var(--bg)', 'Page'],
  ['Surface', 'var(--surface)', 'Panels'],
  ['Action', 'var(--primary)', 'Primary action'],
  ['Attention', 'var(--warning)', 'Review'],
  ['Positive', 'var(--success)', 'Complete'],
  ['Critical', 'var(--danger)', 'Failure'],
] as const

const documents = [
  { name: 'DRC-01A_SCN_Riviera.pdf', detail: 'Waiting for processing capacity', state: 'Queued', variant: 'muted' as const, icon: Clock3 },
  { name: 'Appeal_Order_17-2025.pdf', detail: 'Extracting text and document fields', state: 'Processing', variant: 'default' as const, icon: Loader2 },
  { name: 'GST_DRC-07_Final.pdf', detail: 'Matched to Mehta Industrial', state: 'Ready', variant: 'success' as const, icon: Check },
  { name: 'Encrypted_Notice_2025.pdf', detail: 'Password-protected PDF', state: 'Failed', variant: 'danger' as const, icon: CircleAlert },
] as const

export default function DesignSystemPage() {
  return (
    <div className="flex flex-1 flex-col overflow-y-auto pb-10">
      <header className="flex flex-col gap-2 border-b border-[var(--border)] pb-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[var(--primary)]">Civic Ink</p>
          <h1 className="mt-1 text-2xl font-semibold text-[var(--text-primary)]">Design system</h1>
        </div>
        <p className="max-w-lg text-sm text-[var(--text-muted)] sm:text-right">The implementation reference for CaseChain foundations, primitives, domain patterns, and responsive states.</p>
      </header>

      <section className="py-6">
        <h2 className="text-base font-semibold">Semantic colour</h2>
        <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4 xl:grid-cols-7">
          {colors.map(([name, value, use]) => (
            <div key={name} className="min-w-0">
              <div className="h-12 rounded-[var(--radius-sm)] border border-[var(--border)]" style={{ background: value }} />
              <strong className="mt-2 block text-sm font-medium">{name}</strong>
              <small className="block truncate text-[var(--text-muted)]">{use}</small>
            </div>
          ))}
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Core actions</h2>
        <div className="mt-3 flex flex-wrap gap-2">
          <Button>Primary action</Button>
          <Button variant="secondary">Secondary</Button>
          <Button variant="ghost">Quiet action</Button>
          <Button variant="destructive">Destructive</Button>
          <Button disabled>Disabled</Button>
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-base font-semibold">Collection status consistency</h2>
            <p className="mt-1 text-sm text-[var(--text-muted)]">Every document row reserves the same 96px status slot, regardless of label length.</p>
          </div>
          <Badge variant="outline">Collection rule</Badge>
        </div>
        <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          {documents.map(({ name, detail, state, variant, icon: Icon }, index) => (
            <div key={name} className={`flex items-center gap-3 p-3 ${index ? 'border-t border-[var(--border)]' : ''}`}>
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--surface-hover)] text-[var(--text-muted)]"><FileText size={16} aria-hidden="true" /></div>
              <div className="min-w-0 flex-1">
                <strong className="block truncate text-sm font-medium">{name}</strong>
                <small className="mt-0.5 block truncate text-[var(--text-muted)]">{detail}</small>
              </div>
              <Badge variant={variant} fixedWidth="lg"><Icon size={11} className={state === 'Processing' ? 'animate-spin' : ''} aria-hidden="true" />{state}</Badge>
            </div>
          ))}
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Live processing rail</h2>
        <div className="mt-4 max-w-xl rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4">
          <div className="flex items-center justify-between gap-3"><strong className="text-sm font-medium">Appeal_Order_17-2025.pdf</strong><Badge variant="default" fixedWidth="lg">Processing</Badge></div>
          <p className="mt-1 text-xs text-[var(--text-muted)]">Extracting text and document fields · step 2 of 4</p>
          <div className="mt-3 grid grid-cols-4 gap-1.5" aria-label="Extracting, step 2 of 4">
            <span className="h-1 rounded-[var(--radius-sm)] bg-[var(--success)]" />
            <span className="h-1 rounded-[var(--radius-sm)] bg-[var(--primary)] ring-2 ring-[color-mix(in_srgb,var(--primary)_18%,transparent)]" />
            <span className="h-1 rounded-[var(--radius-sm)] bg-[var(--border-strong)]" />
            <span className="h-1 rounded-[var(--radius-sm)] bg-[var(--border-strong)]" />
          </div>
        </div>
      </section>
    </div>
  )
}
