import { Check, CircleAlert, Clock3, FileText, ListFilter, Loader2, Plus, Users } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { MatterSectionWorkbar } from '@/components/ui/matter-section-workbar'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { TrashReadOnlyStrip } from '@/components/trash/TrashReadOnlyStrip'
import { SwitchSpecimen } from './SwitchSpecimen'
import { DecisionDialogSpecimen } from './DecisionDialogSpecimen'

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
            <h2 className="text-base font-semibold">PDF viewer source location</h2>
            <p className="mt-1 max-w-3xl text-sm text-[var(--text-muted)]">A server-derived one-based page opens the shared viewer. It clamps to the PDF’s actual page count after loading; bounded native-text search and a synchronized horizontal thumbnail disclosure remain outside the vertical source scroller.</p>
          </div>
          <Badge variant="outline">Static reference</Badge>
        </div>
        <div className="mt-4 max-w-xl rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3">
          <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--text-secondary)]" aria-label="PDF viewer toolbar reference">
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Previous page</span>
            <span className="min-w-28 px-2 text-center font-medium text-[var(--text-primary)]">Page 12 of 24</span>
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Next page</span>
            <span className="h-6 w-px bg-[var(--border)]" aria-hidden="true" />
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Zoom out</span>
            <span className="px-2 font-medium text-[var(--text-primary)]">100%</span>
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Zoom in</span>
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Fit page</span>
            <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface-hover)] px-3 py-2">Show thumbnails</span>
          </div>
          <div className="mt-3 flex gap-2 overflow-hidden border-y border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-2" aria-label="Thumbnail navigator reference">
            {[10, 11, 12, 13, 14].map(page => <span key={page} className={`flex h-16 w-12 shrink-0 items-end justify-center rounded-[var(--radius-sm)] border p-1 text-[10px] ${page === 12 ? 'border-[var(--accent)] bg-[var(--accent-muted)] text-[var(--text-primary)]' : 'border-[var(--border)] bg-[var(--surface)] text-[var(--text-muted)]'}`}>{page}</span>)}
          </div>
          <p className="mt-3 text-xs leading-5 text-[var(--text-muted)]">Illustrative toolbar and thumbnail strip only — not an interactive PDF. The production strip renders at most five labelled nearby thumbnails with explicit earlier/later navigation.</p>
          <div className="mt-3 grid gap-2 sm:grid-cols-2" aria-label="PDF quotation source references">
            <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-2">
              <p className="text-xs font-semibold text-[var(--text-primary)]">Exact quotation source</p>
              <p className="mt-1 text-[11px] text-[var(--text-muted)]">Version 2 · Page 12 · Historical source</p>
              <span className="mt-2 inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium">Open exact source</span>
            </div>
            <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-2">
              <p className="text-xs font-semibold text-[var(--text-primary)]">Legacy quotation</p>
              <p className="mt-1 text-[11px] text-[var(--text-muted)]">Original page 12 · Source location unverified</p>
              <p className="mt-2 text-xs text-[var(--text-secondary)]">Keep the excerpt visible; do not offer an exact-source action.</p>
            </div>
          </div>
          <div className="mt-3 grid gap-2 sm:grid-cols-2" aria-label="PDF source failure references">
            {[
              ['Password-protected PDF', 'Upload an unencrypted PDF copy.'],
              ['Unreadable PDF', 'Upload a valid readable PDF copy.'],
              ['PDF file unavailable', 'Return to the record or contact an administrator.'],
              ['PDF access needs refreshing', 'Refresh PDF access.'],
              ['Page could not be rendered', 'Retry only the affected page.'],
            ].map(([title, recovery]) => <div key={title} className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] p-2"><p className="text-xs font-semibold text-[var(--text-primary)]">{title}</p><p className="mt-1 text-[11px] text-[var(--text-muted)]">{recovery}</p></div>)}
          </div>
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Motion rhythm</h2>
        <p className="mt-1 max-w-3xl text-sm text-[var(--text-muted)]">Hover or focus these specimens. Feedback begins immediately: micro-state changes complete in 150ms, while a user-triggered pane or disclosure completes in 250ms.</p>
        <div className="mt-4 grid max-w-3xl gap-3 sm:grid-cols-2">
          <button type="button" className="group rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3 text-left outline-none transition-colors duration-[var(--duration-fast)] ease-[var(--ease-smooth)] hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] motion-reduce:transition-none">
            <span className="block text-sm font-semibold">Micro feedback</span>
            <span className="mt-1 block text-xs text-[var(--text-muted)]">Colour, hover, focus, and tabs · 150ms</span>
          </button>
          <button type="button" className="group overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3 text-left outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">
            <span className="block text-sm font-semibold">Structural transition</span>
            <span className="mt-2 flex items-center gap-2"><span className="h-8 min-w-0 flex-1 rounded-[var(--radius-sm)] bg-[var(--bg-overlay)]" /><span className="h-8 w-20 translate-x-1 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--accent-muted)] opacity-70 transition-[transform,opacity] duration-[var(--duration-base)] ease-[var(--ease-smooth)] group-hover:translate-x-0 group-hover:opacity-100 group-focus-visible:translate-x-0 group-focus-visible:opacity-100 motion-reduce:translate-x-0 motion-reduce:opacity-100 motion-reduce:transition-none" /></span>
            <span className="mt-1 block text-xs text-[var(--text-muted)]">Pane and disclosure movement · 250ms</span>
          </button>
        </div>
        <p className="mt-3 text-xs text-[var(--text-muted)]">No operational entry delay. Reduced motion removes spatial movement, and realtime rows never animate position.</p>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Decision confirmation</h2>
        <p className="mt-1 max-w-3xl text-sm text-[var(--text-muted)]">Confirmations use the shared semantic scrim and present the selected outcome, concrete consequences, supporting authority, and one clear confirmation action in that order.</p>
        <div className="mt-4"><DecisionDialogSpecimen /></div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Binary settings</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Switches keep one shared focus, motion, disabled, and effective touch-target contract.</p>
        <SwitchSpecimen />
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <h2 className="text-base font-semibold">Trash read-only context</h2>
        <p className="mt-1 text-sm text-[var(--text-muted)]">Exact canonical legal-record routes keep the Trash state and route back to the selected group outside their scrolling body. This inherited specimen deliberately has no independent Restore action.</p>
        <div className="mt-4 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <TrashReadOnlyStrip context={{
            state: 'trash', membershipId: 'membership-example', cause: 'inherited', parentMembershipId: 'parent-example',
            operationId: 'operation-example', rootResourceId: 'matter-example', rootResourceType: 'matter', rootResourceName: 'FY 2024–25 audit response',
            operationState: 'trashed', trashedAt: '2026-08-30T10:32:00+05:30', trashedBy: null, trashedByName: 'Ananya Kapoor', canRestore: false,
            restorePreflight: null,
            retention: { mode: 'manual_only', days: null, purgeEligibleAt: null, autoPurgeEnabled: false, autoPurgeAt: null, purgeScheduledAt: null, blockerCount: 0 },
          }} />
          <div className="p-4 text-sm text-[var(--text-muted)]">Canonical Client, Matter, or Document content continues here in read-only mode.</div>
        </div>
      </section>

      <section className="border-t border-[var(--border)] py-6">
        <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-base font-semibold">Matter section navigation</h2>
            <p className="mt-1 max-w-3xl text-sm text-[var(--text-muted)]">The permanent eight-section desktop strip and four-plus-More mobile bar keep Matter navigation stable while only the active section loads.</p>
          </div>
          <Badge variant="outline">Responsive contract</Badge>
        </div>
        <div className="mt-4 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] p-3">
          <p className="text-xs font-semibold text-[var(--text-secondary)]">Desktop · fixed order outside the section scroller</p>
          <div className="mt-2 grid grid-cols-4 gap-1 border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-sm)] lg:grid-cols-8">
            {['Timeline', 'Files', 'Case Brief', 'Notes', 'Deadlines', 'Financials', 'Activity', 'Details'].map((label, index) => (
              <span key={label} className={`flex min-h-11 items-center justify-center rounded-[var(--radius-sm)] px-2 text-center text-xs font-medium ${index === 0 ? 'bg-[var(--primary-muted)] text-[var(--primary)]' : 'text-[var(--text-secondary)]'}`}>{label}</span>
            ))}
          </div>
          <p className="mt-4 text-xs font-semibold text-[var(--text-secondary)]">Mobile · fixed destinations above the content-safe inset</p>
          <div className="mt-2 grid max-w-md grid-cols-5 border border-[var(--border-strong)] bg-[var(--surface)] p-1 shadow-[var(--shadow-lg)]">
            {['Timeline', 'Files', 'Case Brief', 'Notes', 'More'].map((label, index) => (
              <span key={label} className={`flex min-h-11 items-center justify-center rounded-[var(--radius-sm)] px-1 text-center text-[11px] font-medium ${index === 0 ? 'bg-[var(--primary-muted)] text-[var(--primary)]' : 'text-[var(--text-secondary)]'}`}>{label}</span>
            ))}
          </div>
          <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">More opens an accessible bottom sheet for Deadlines, Financials, Activity, and Details and names the active secondary destination.</p>
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
        <div className="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 className="text-base font-semibold">Low-surprise table disclosure</h2>
            <p className="mt-1 max-w-3xl text-sm text-[var(--text-muted)]">The full table is the resting state. Selection opens an adaptive contextual sidebar, and explicit source viewing replaces the table instead of adding a third pane.</p>
          </div>
          <Badge variant="outline">Workspace rule</Badge>
        </div>
        <div className="mt-4 grid gap-3 lg:grid-cols-3">
          {[
            { label: '1 · Resting', left: 'Full table', right: 'All columns', detail: 'No empty detail pane and no PDF opened.' },
            { label: '2 · Selected', left: '60% · 3 columns', right: '40% · sidebar', detail: 'Repeated columns yield to Overview and Extracted data.' },
            { label: '3 · Source', left: 'PDF · cited page', right: 'Same sidebar', detail: 'Exact-page highlight, explicit Close, never a third pane.' },
          ].map(({ label, left, right, detail }) => (
            <div key={label} className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3">
              <div className="flex items-center justify-between gap-2">
                <strong className="text-xs font-semibold uppercase tracking-[0.08em] text-[var(--text-secondary)]">{label}</strong>
                <span className="text-[11px] text-[var(--text-muted)]">Stable anatomy</span>
              </div>
              <div className="mt-3 grid h-24 grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)] overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-subtle)] text-xs">
                <div className="flex items-center justify-center border-r border-[var(--border-subtle)] bg-[var(--surface-hover)] px-2 text-center font-medium text-[var(--text-secondary)]">{left}</div>
                <div className="flex items-center justify-center px-2 text-center font-medium text-[var(--text-primary)]">{right}</div>
              </div>
              <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">{detail}</p>
            </div>
          ))}
        </div>
        <div className="mt-3 flex flex-wrap gap-2 text-xs text-[var(--text-secondary)]">
          <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] px-2.5 py-1.5">Workbar: ownership scope · Search · collection action</span>
          <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] px-2.5 py-1.5">Table heading: field-specific filter</span>
          <span className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] px-2.5 py-1.5">Row marker ↔ sidebar summary: one processing state</span>
        </div>
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
        <h2 className="text-base font-semibold">Selected-detail processing summary</h2>
        <div className="mt-4 max-w-xl rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4">
          <div className="flex items-center justify-between gap-3"><strong className="text-sm font-medium">Appeal_Order_17-2025.pdf</strong><Badge variant="default" fixedWidth="lg">Processing</Badge></div>
          <div className="mt-3 grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-2.5 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] px-3 py-2.5" role="status"><span className="flex size-8 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)]"><Loader2 className="size-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /></span><div className="min-w-0"><p className="truncate text-xs font-semibold">Reading and extracting document</p><p className="mt-0.5 text-[11px] leading-4 text-[var(--text-secondary)]">12 of 28 pages are ready. Processing continues in the background.</p></div><Badge variant="outline" className="hidden sm:inline-flex">No action needed</Badge></div>
        </div>
      </section>
    </div>
  )
}
