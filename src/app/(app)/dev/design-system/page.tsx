import { Check, CircleAlert, Clock3, FileText, ListFilter, Loader2, Plus, Users } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { MatterSectionWorkbar } from '@/components/ui/matter-section-workbar'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'

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
        <h2 className="text-base font-semibold">Trash read-only context</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Exact canonical legal-record routes keep the Trash state and route back to the selected group outside their scrolling body.</p>
        <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <TrashReadOnlyStrip context={{
            state: 'trash', membershipId: 'membership-example', cause: 'inherited', parentMembershipId: 'parent-example',
            operationId: 'operation-example', rootResourceId: 'matter-example', rootResourceType: 'matter', rootResourceName: 'FY 2024–25 audit response',
            operationState: 'trashed', trashedAt: '2026-08-30T10:32:00+05:30', trashedBy: null, trashedByName: 'Ananya Kapoor', canRestore: false,
            retention: { mode: 'manual_only', days: null, purgeEligibleAt: null, autoPurgeEnabled: false, autoPurgeAt: null, purgeScheduledAt: null, blockerCount: 0 },
          }} />
          <div className="p-4 text-sm text-[var(--text-muted)]">Canonical Client, Matter, or Document content continues here in read-only mode.</div>
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Matter section workbar</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Views remain left, optional context occupies the middle, and the primary action remains rightmost.</p>
        <MatterSectionWorkbar
          className="mt-4 rounded-[var(--radius-md)] border border-[var(--border)]"
          views={<div className="flex rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-0.5"><Button variant="secondary" size="sm" className="shadow-none">Legal position</Button><Button variant="ghost" size="sm">Internal costs</Button></div>}
          context={<span className="hidden text-xs text-[var(--text-muted)] sm:inline">Verified facts only in solid totals</span>}
          actions={<><Button variant="outline" size="sm"><Users size={14} />Participants</Button><Button variant="outline" size="sm"><ListFilter size={14} />Filters</Button><Button size="sm"><Plus size={14} />Add entry</Button></>}
        />
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Compact operational table</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Rows keep comparison and selection context compact; longer explanations belong in the selected detail pane.</p>
        <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <Table>
            <TableCaption>Example compact document collection.</TableCaption>
            <TableHeader><TableRow><TableHead>Document</TableHead><TableHead>Current stage</TableHead><TableHead className="w-28"><span className="sr-only">Action</span></TableHead></TableRow></TableHeader>
            <TableBody>
              {documents.slice(0, 3).map(({ name, detail, state, variant, icon: Icon }) => (
                <TableRow key={name} interactive>
                  <TableCell><strong className="block truncate text-sm font-medium">{name}</strong><small className="mt-0.5 block truncate text-[var(--text-muted)]">{detail}</small></TableCell>
                  <TableCell><Badge variant={variant} fixedWidth="lg"><Icon size={11} className={state === 'Processing' ? 'animate-spin motion-reduce:animate-none' : ''} aria-hidden="true" />{state}</Badge></TableCell>
                  <TableCell><Button variant="ghost" size="sm">View details</Button></TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Layout-preserving loading</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Skeletons reuse the final collection geometry, reserve stable row dimensions, and remain static when reduced motion is requested.</p>
        <div className="mt-4 max-w-2xl overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]" aria-busy="true" aria-label="Loading document rows">
          <p className="sr-only">Loading document rows…</p>
          {[1, 2, 3].map((item) => (
            <div key={item} className={`flex items-center gap-3 p-3 ${item > 1 ? 'border-t border-[var(--border)]' : ''}`}>
              <Skeleton className="size-9 shrink-0" />
              <span className="min-w-0 flex-1">
                <Skeleton className="h-3.5 w-3/5 max-w-64" />
                <Skeleton className="mt-2 h-3 w-2/5 max-w-44" />
              </span>
              <Skeleton className="h-6 w-24 shrink-0" />
            </div>
          ))}
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
        <div className="mt-3 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <div className="flex items-center gap-3 p-3"><span className="min-w-0 flex-1 text-sm font-medium">Deadline readiness</span><Badge variant="danger" fixedWidth="xl">Outcome required</Badge></div>
          <div className="flex items-center gap-3 border-t border-[var(--border)] p-3"><span className="min-w-0 flex-1 text-sm font-medium">Deadline readiness</span><Badge variant="warning" fixedWidth="xl">Setup required</Badge></div>
          <div className="flex items-center gap-3 border-t border-[var(--border)] p-3"><span className="min-w-0 flex-1 text-sm font-medium">Deadline readiness</span><Badge variant="default" fixedWidth="xl">Alerts active</Badge></div>
        </div>
        <p className="mt-2 text-xs text-[var(--text-muted)]">This longer vocabulary reserves the same 128px status slot for every row.</p>
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
