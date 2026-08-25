'use client'

import { useMemo, useState } from 'react'
import {
  Activity,
  AlertTriangle,
  Bell,
  BookOpen,
  CalendarDays,
  Check,
  ChevronDown,
  ChevronRight,
  Clock3,
  FileText,
  Files,
  FolderOpen,
  GitBranch,
  Inbox,
  IndianRupee,
  Info,
  LayoutDashboard,
  Link2,
  List,
  Maximize2,
  Menu,
  MessageSquare,
  MoreHorizontal,
  PanelRightClose,
  Plus,
  Scale,
  Search,
  Settings,
  SlidersHorizontal,
  StickyNote,
  Upload,
  Users,
  ZoomIn,
  ZoomOut,
} from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type Section = 'timeline' | 'files' | 'brief' | 'notes' | 'deadlines' | 'financials' | 'details' | 'activity'
type TimelineMode = 'graph' | 'list'

type DocumentNode = {
  id: string
  kind: string
  direction: 'Incoming' | 'Outgoing' | 'Internal'
  title: string
  date: string
  reference: string
  fact: string
  amount?: string
  deadline?: string
  position: string
}

const timelineNodes: DocumentNode[] = [
  {
    id: 'scn',
    kind: 'DRC-01',
    direction: 'Incoming',
    title: 'Show Cause Notice',
    date: '14 Feb 2024',
    reference: 'DRC01/2024/1187',
    fact: 'Input tax credit mismatch alleged',
    amount: '₹14,20,000',
    deadline: 'Reply due 15 Mar 2024',
    position: 'left-[5%] top-[19%]',
  },
  {
    id: 'reply',
    kind: 'Reply',
    direction: 'Outgoing',
    title: 'Reply to SCN',
    date: '12 Mar 2024',
    reference: 'ACK-24-0312-88',
    fact: 'Reconciliation and invoices submitted',
    position: 'left-[29%] top-[49%]',
  },
  {
    id: 'hearing',
    kind: 'Hearing',
    direction: 'Incoming',
    title: 'Personal Hearing Notice',
    date: '11 Apr 2024',
    reference: 'PH/2024/0441',
    fact: 'Appearance scheduled for 22 April',
    deadline: 'Hearing 22 Apr 2024',
    position: 'left-[36%] top-[10%]',
  },
  {
    id: 'oio',
    kind: 'OIO',
    direction: 'Incoming',
    title: 'Order-in-Original',
    date: '08 Sep 2024',
    reference: 'OIO/CGST/2024/091',
    fact: 'Demand substantially reduced',
    amount: '₹50,000',
    deadline: 'Appeal due 07 Dec 2024',
    position: 'left-[57%] top-[37%]',
  },
  {
    id: 'appeal',
    kind: 'APL-01',
    direction: 'Outgoing',
    title: 'Appeal Filed',
    date: '02 Oct 2024',
    reference: 'APL01/2024/5532',
    fact: 'Appeal against residual demand',
    amount: 'Pre-deposit ₹5,000',
    position: 'left-[75%] top-[13%]',
  },
]

const sectionItems: Array<{ id: Section; label: string; icon: typeof FileText; count?: string }> = [
  { id: 'timeline', label: 'Timeline', icon: GitBranch, count: '5' },
  { id: 'files', label: 'Files', icon: Files, count: '12' },
  { id: 'brief', label: 'Case Brief', icon: BookOpen },
  { id: 'notes', label: 'Notes', icon: MessageSquare, count: '8' },
  { id: 'deadlines', label: 'Deadlines', icon: CalendarDays, count: '3' },
  { id: 'financials', label: 'Financials', icon: IndianRupee },
  { id: 'activity', label: 'Activity', icon: Activity },
  { id: 'details', label: 'Details', icon: Info },
]

const supportingFiles = [
  { title: 'Purchase register — FY 2023–24', category: 'Evidence', type: 'XLSX', size: '2.4 MB', added: '12 Mar 2024', metadata: 'Indexed', linked: 'Reply to SCN' },
  { title: 'Supplier invoices — batch 04', category: 'Invoices', type: 'PDF', size: '8.8 MB', added: '12 Mar 2024', metadata: 'Text available', linked: 'Reply to SCN' },
  { title: 'Factory premises photograph', category: 'Evidence', type: 'JPG', size: '3.1 MB', added: '18 Mar 2024', metadata: 'No text', linked: 'Not linked' },
  { title: 'Counsel research — Section 16', category: 'Research', type: 'PDF', size: '1.2 MB', added: '21 Mar 2024', metadata: 'Indexed', linked: 'Not linked' },
]

const navItems = [
  { label: 'Today', icon: LayoutDashboard },
  { label: 'Documents', icon: Inbox },
  { label: 'Clients', icon: Users },
  { label: 'Matters', icon: FolderOpen, selected: true },
  { label: 'Notes', icon: StickyNote },
  { label: 'Deadlines', icon: CalendarDays },
]

function DirectionBadge({ direction }: { direction: DocumentNode['direction'] }) {
  const variant = direction === 'Incoming' ? 'incoming' : direction === 'Outgoing' ? 'outgoing' : 'muted'
  return <Badge variant={variant} className="min-h-5 px-1.5 py-0 text-[10px]">{direction}</Badge>
}

function TimelineNode({ node, selected, onSelect }: { node: DocumentNode; selected: boolean; onSelect: () => void }) {
  return (
    <button
      type="button"
      onClick={onSelect}
      aria-label={`Open ${node.title}`}
      className={cn(
        'absolute z-10 w-[205px] rounded-[var(--radius-md)] border bg-[var(--surface)] p-3 text-left shadow-[var(--shadow-sm)]',
        'transition-[border-color,box-shadow,transform] duration-[var(--duration-fast)] hover:-translate-y-0.5 hover:border-[var(--border-strong)] hover:shadow-[var(--shadow-md)]',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',
        node.position,
        selected && 'border-[var(--primary)] shadow-[var(--shadow-md)] ring-1 ring-[var(--primary)]',
      )}
    >
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">{node.kind}</span>
        <DirectionBadge direction={node.direction} />
      </div>
      <div className="truncate text-sm font-semibold text-[var(--text-primary)]">{node.title}</div>
      <div className="mt-1 flex items-center gap-1.5 text-[11px] text-[var(--text-muted)]">
        <Clock3 size={12} aria-hidden="true" />
        {node.date}
      </div>
      <p className="mt-2 line-clamp-2 text-xs leading-4 text-[var(--text-secondary)]">{node.fact}</p>
      {node.amount && <div className="mt-2 border-t border-[var(--border-subtle)] pt-2 text-xs font-semibold text-[var(--text-primary)]">{node.amount}</div>}
    </button>
  )
}

function TimelineList({ selectedId, onSelect, nodes = timelineNodes, showRelationshipReview = true, embeddedDesktop = false }: { selectedId: string | null; onSelect: (id: string) => void; nodes?: DocumentNode[]; showRelationshipReview?: boolean; embeddedDesktop?: boolean }) {
  return (
    <div className={cn('h-full overflow-y-auto', embeddedDesktop ? 'px-8 pb-8 pt-0' : 'px-4 pb-24 pt-5 md:px-8 md:pb-8 md:pt-36')}>
      <div className="mx-auto max-w-6xl">
        <div className="mb-5 flex items-end justify-between gap-4 md:hidden">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">Chronology</p>
            <h2 className="mt-1 text-xl font-semibold text-[var(--text-primary)]">{nodes.length} proceeding {nodes.length === 1 ? 'document' : 'documents'}</h2>
          </div>
          {showRelationshipReview && <Badge variant="warning">1 relationship to review</Badge>}
        </div>
        <ol className="relative ml-3 border-l border-[var(--border-strong)] pl-7 md:hidden">
          {nodes.map((node) => (
            <li key={node.id} className="relative mb-4 last:mb-0">
              <span className="absolute -left-[35px] top-5 h-3.5 w-3.5 rounded-full border-2 border-[var(--surface)] bg-[var(--primary)]" />
              <button
                type="button"
                onClick={() => onSelect(node.id)}
                className={cn(
                  'w-full rounded-[var(--radius-md)] border bg-[var(--surface)] p-4 text-left shadow-[var(--shadow-sm)] transition-colors hover:bg-[var(--surface-hover)]',
                  selectedId === node.id ? 'border-[var(--primary)] ring-1 ring-[var(--primary)]' : 'border-[var(--border)]',
                )}
              >
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <div className="flex items-center gap-2"><span className="font-semibold text-[var(--text-primary)]">{node.title}</span><DirectionBadge direction={node.direction} /></div>
                    <p className="mt-1 text-xs text-[var(--text-muted)]">{node.kind} · {node.reference}</p>
                  </div>
                  <span className="text-xs font-medium text-[var(--text-secondary)]">{node.date}</span>
                </div>
                <p className="mt-3 text-sm text-[var(--text-secondary)]">{node.fact}</p>
                {node.amount && <p className="mt-2 text-sm font-semibold text-[var(--text-primary)]">{node.amount}</p>}
              </button>
            </li>
          ))}
        </ol>
        <div className="hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] md:block">
          <table className="w-full table-fixed border-collapse text-left">
            <caption className="sr-only">{nodes.length} proceeding {nodes.length === 1 ? 'document' : 'documents'} in chronological order</caption>
            <colgroup><col className="w-10" /><col className="w-[112px]" /><col className="w-[25%]" /><col className="w-[96px]" /><col /><col className="w-[178px]" /><col className="w-11" /></colgroup>
            <thead className="sticky top-0 z-10 bg-[var(--bg-overlay)]">
              <tr className="border-b border-[var(--border)] text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)]">
                <th scope="col" className="px-0 py-2.5"><span className="sr-only">Timeline</span></th>
                <th scope="col" className="px-3 py-2.5">Date</th>
                <th scope="col" className="px-3 py-2.5">Document</th>
                <th scope="col" className="px-3 py-2.5">Direction</th>
                <th scope="col" className="px-3 py-2.5">Procedural effect</th>
                <th scope="col" className="px-3 py-2.5">Key fact</th>
                <th scope="col" className="px-0 py-2.5"><span className="sr-only">Open details</span></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-subtle)]">
              {nodes.map((node) => (
                <tr key={node.id} className={cn('group transition-colors hover:bg-[var(--surface-hover)]', selectedId === node.id && 'bg-[var(--accent-muted)]')}>
                  <td className="relative p-0"><span className="absolute inset-y-0 left-1/2 w-px -translate-x-1/2 bg-[var(--border-strong)]" /><span className="absolute left-1/2 top-1/2 h-3.5 w-3.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-[var(--surface)] bg-[var(--primary)]" /></td>
                  <td className="px-3 py-3.5 align-middle"><span className="text-sm font-semibold text-[var(--text-primary)]">{node.date}</span><span className="mt-1 block text-[11px] text-[var(--text-muted)]">{node.kind}</span></td>
                  <td className="px-3 py-3.5 align-middle"><button type="button" onClick={() => onSelect(node.id)} className="block max-w-full text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><span className="block truncate text-sm font-semibold text-[var(--text-primary)] group-hover:text-[var(--primary)]">{node.title}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{node.reference}</span></button></td>
                  <td className="px-3 py-3.5 align-middle"><DirectionBadge direction={node.direction} /></td>
                  <td className="px-3 py-3.5 align-middle"><p className="line-clamp-2 text-sm leading-5 text-[var(--text-secondary)]">{node.fact}</p></td>
                  <td className="px-3 py-3.5 align-middle"><span className="text-sm font-semibold text-[var(--text-primary)]">{node.amount ?? node.deadline ?? <span className="font-normal text-[var(--text-disabled)]">—</span>}</span></td>
                  <td className="px-1 py-3.5 align-middle"><button type="button" onClick={() => onSelect(node.id)} aria-label={`Open details for ${node.title}`} className="flex h-9 w-9 items-center justify-center rounded-[var(--radius-sm)] text-[var(--text-muted)] hover:bg-[var(--bg-overlay)] hover:text-[var(--text-primary)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><ChevronRight size={17} /></button></td>
                </tr>
              ))}
              {nodes.length === 0 && <tr><td colSpan={7} className="px-4 py-10 text-center text-sm text-[var(--text-muted)]">No proceeding documents match these filters.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

function DocumentInspector({ node, onClose }: { node: DocumentNode; onClose: () => void }) {
  const [tab, setTab] = useState<'overview' | 'relationships' | 'notes'>('overview')
  return (
    <aside className="absolute inset-y-3 right-3 z-30 flex w-[370px] flex-col overflow-hidden rounded-[var(--radius-lg)] border border-[var(--border)] bg-[var(--surface)] shadow-[var(--shadow-lg)] max-md:inset-0 max-md:w-auto max-md:rounded-none max-md:border-0">
      <header className="shrink-0 border-b border-[var(--border)] px-4 py-3">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="mb-1.5 flex items-center gap-2"><Badge variant="outline">{node.kind}</Badge><DirectionBadge direction={node.direction} /></div>
            <h2 className="truncate text-base font-semibold text-[var(--text-primary)]">{node.title}</h2>
            <p className="mt-1 truncate text-xs text-[var(--text-muted)]">{node.reference}</p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label="Close document details" title="Close document details">
            <PanelRightClose size={18} />
          </Button>
        </div>
        <Button className="mt-3 w-full"><FileText size={16} />Open document</Button>
      </header>

      <div className="flex shrink-0 border-b border-[var(--border)] px-3">
        {(['overview', 'relationships', 'notes'] as const).map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setTab(item)}
            className={cn(
              'min-h-11 flex-1 border-b-2 px-2 text-xs font-medium capitalize transition-colors',
              tab === item ? 'border-[var(--primary)] text-[var(--text-primary)]' : 'border-transparent text-[var(--text-muted)] hover:text-[var(--text-primary)]',
            )}
          >{item}</button>
        ))}
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        {tab === 'overview' && (
          <div className="space-y-5">
            <section>
              <h3 className="text-xs font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">What changed</h3>
              <p className="mt-2 text-sm leading-6 text-[var(--text-primary)]">{node.fact}. This is the salient matter-level consequence extracted from the document.</p>
            </section>
            {(node.amount || node.deadline) && (
              <div className="grid grid-cols-1 gap-2">
                {node.amount && <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-3"><div className="flex items-center gap-2 text-xs text-[var(--text-muted)]"><IndianRupee size={14} />Financial effect</div><p className="mt-1.5 font-semibold text-[var(--text-primary)]">{node.amount}</p></div>}
                {node.deadline && <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-3"><div className="flex items-center gap-2 text-xs text-[var(--text-muted)]"><CalendarDays size={14} />Deadline</div><p className="mt-1.5 font-semibold text-[var(--text-primary)]">{node.deadline}</p></div>}
              </div>
            )}
            <section>
              <div className="flex items-center justify-between"><h3 className="text-xs font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">Document facts</h3><button className="text-xs font-medium text-[var(--primary)] hover:underline">View all metadata</button></div>
              <dl className="mt-2 divide-y divide-[var(--border-subtle)] rounded-[var(--radius-md)] border border-[var(--border)] px-3">
                <div className="flex justify-between gap-4 py-2.5 text-xs"><dt className="text-[var(--text-muted)]">Document date</dt><dd className="font-medium text-[var(--text-primary)]">{node.date}</dd></div>
                <div className="flex justify-between gap-4 py-2.5 text-xs"><dt className="text-[var(--text-muted)]">Issuer</dt><dd className="text-right font-medium text-[var(--text-primary)]">CGST Division II, Pune</dd></div>
                <div className="flex justify-between gap-4 py-2.5 text-xs"><dt className="text-[var(--text-muted)]">Confidence</dt><dd className="flex items-center gap-1 font-medium text-[var(--success)]"><Check size={13} />Verified</dd></div>
              </dl>
            </section>
            <section className="rounded-[var(--radius-md)] border border-[var(--border)] p-3">
              <div className="flex items-start gap-2.5"><Info size={16} className="mt-0.5 shrink-0 text-[var(--text-muted)]" /><div><h3 className="text-xs font-semibold text-[var(--text-primary)]">Evidence stays traceable</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">Each extracted fact opens the exact PDF page and highlighted source text in the Document Workbench.</p></div></div>
            </section>
          </div>
        )}
        {tab === 'relationships' && (
          <div className="space-y-3">
            <div className="rounded-[var(--radius-md)] border border-[var(--border)] p-3"><div className="flex items-center gap-2 text-xs font-semibold text-[var(--text-primary)]"><Link2 size={15} />Decides Reply to SCN</div><p className="mt-2 text-xs leading-5 text-[var(--text-secondary)]">Confirmed from explicit document reference ACK-24-0312-88.</p><Badge variant="success" className="mt-3">Confirmed</Badge></div>
            <div className="rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3"><div className="flex items-center gap-2 text-xs font-semibold text-[var(--text-primary)]"><AlertTriangle size={15} />May follow Hearing Notice</div><p className="mt-2 text-xs leading-5 text-[var(--text-secondary)]">Suggested by chronology and shared proceeding number. It will not become a graph edge until reviewed.</p><div className="mt-3 flex gap-2"><Button size="sm">Confirm link</Button><Button size="sm" variant="secondary">Dismiss</Button></div></div>
          </div>
        )}
        {tab === 'notes' && (
          <div>
            <div className="rounded-[var(--radius-md)] border border-[var(--border)] p-3"><div className="flex items-center justify-between"><span className="text-xs font-semibold text-[var(--text-primary)]">Riya Sharma</span><span className="text-[11px] text-[var(--text-muted)]">2h ago</span></div><p className="mt-2 text-sm leading-5 text-[var(--text-secondary)]">The residual demand appears appealable. <span className="font-medium text-[var(--primary)]">@Arjun</span> please verify the limitation date.</p><button className="mt-3 text-xs font-medium text-[var(--primary)] hover:underline">“Demand of ₹50,000 is confirmed…” · Page 18</button></div>
            <Button variant="secondary" className="mt-3 w-full"><MessageSquare size={16} />Add note</Button>
          </div>
        )}
      </div>
    </aside>
  )
}

function SectionSwitcher({ active, onChange, inspectorOpen }: { active: Section; onChange: (section: Section) => void; inspectorOpen: boolean }) {
  return (
    <nav aria-label="Matter sections" className={cn('absolute top-1 z-30 hidden w-max max-w-[calc(100%-32px)] -translate-x-1/2 items-center gap-1 overflow-visible rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-lg)] transition-[left] duration-200 md:flex', inspectorOpen ? 'left-[calc(50%-197px)]' : 'left-1/2')}>
      {sectionItems.map((item) => {
        const Icon = item.icon
        return (
          <button
            key={item.id}
            type="button"
            onClick={() => onChange(item.id)}
            className={cn(
              'flex min-h-9 shrink-0 items-center gap-1.5 rounded-[var(--radius-sm)] px-2.5 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',
              active === item.id ? 'bg-[var(--primary)] text-[var(--on-accent)]' : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]',
            )}
          >
            <Icon size={14} />{item.label}{item.count && <span className={cn('text-[10px]', active === item.id ? 'text-[var(--on-accent)]' : 'text-[var(--text-disabled)]')}>{item.count}</span>}
          </button>
        )
      })}
    </nav>
  )
}

function TimelineCanvas({ selectedId, onSelect, mode, onModeChange }: { selectedId: string | null; onSelect: (id: string | null) => void; mode: TimelineMode; onModeChange: (mode: TimelineMode) => void }) {
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [direction, setDirection] = useState<'all' | 'incoming' | 'outgoing'>('all')
  const [fact, setFact] = useState<'all' | 'deadline' | 'financial'>('all')
  const [showSuggested, setShowSuggested] = useState(true)

  const visibleNodes = timelineNodes.filter((node) => {
    const directionMatches = direction === 'all' || node.direction.toLowerCase() === direction
    const factMatches = fact === 'all' || (fact === 'deadline' ? Boolean(node.deadline) : Boolean(node.amount))
    return directionMatches && factMatches
  })
  const visibleIds = new Set(visibleNodes.map((node) => node.id))
  const activeFilterCount = Number(direction !== 'all') + Number(fact !== 'all') + Number(!showSuggested)
  const edgeVisible = (from: string, to: string) => visibleIds.has(from) && visibleIds.has(to)

  const clearFilters = () => {
    setDirection('all')
    setFact('all')
    setShowSuggested(true)
  }

  return (
    <div className="relative h-full min-h-[500px] overflow-hidden">
      {mode === 'list' ? (
        <div className="absolute inset-x-0 bottom-0 top-36"><TimelineList selectedId={selectedId} onSelect={onSelect} nodes={visibleNodes} showRelationshipReview={showSuggested} embeddedDesktop /></div>
      ) : (
        <>
          <svg className="absolute inset-0 h-full w-full" aria-hidden="true">
            <defs>
              <pattern id="civic-dots" width="24" height="24" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1.1" fill="var(--border-strong)" opacity="0.48" /></pattern>
              <marker id="arrow-confirmed" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="var(--text-muted)" /></marker>
              <marker id="arrow-candidate" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="var(--warning)" /></marker>
            </defs>
            <rect width="100%" height="100%" fill="url(#civic-dots)" />
          </svg>
          <svg className="pointer-events-none absolute inset-0 h-full w-full" viewBox="0 0 1000 600" preserveAspectRatio="none" aria-hidden="true">
            {edgeVisible('scn', 'reply') && <path d="M 165 195 C 245 205, 245 345, 345 365" fill="none" stroke="var(--text-muted)" strokeWidth="1.5" markerEnd="url(#arrow-confirmed)" />}
            {showSuggested && edgeVisible('scn', 'hearing') && <path d="M 165 180 C 260 155, 330 120, 430 125" fill="none" stroke="var(--warning)" strokeWidth="1.5" strokeDasharray="7 6" markerEnd="url(#arrow-candidate)" />}
            {edgeVisible('reply', 'oio') && <path d="M 440 360 C 525 355, 555 315, 635 305" fill="none" stroke="var(--text-muted)" strokeWidth="1.5" markerEnd="url(#arrow-confirmed)" />}
            {edgeVisible('oio', 'appeal') && <path d="M 690 285 C 745 220, 785 170, 830 150" fill="none" stroke="var(--text-muted)" strokeWidth="1.5" markerEnd="url(#arrow-confirmed)" />}
            <g fontFamily="var(--font-geist-sans)" fontSize="11" fill="var(--text-muted)">
              {edgeVisible('scn', 'reply') && <><rect x="212" y="256" width="78" height="22" rx="5" fill="var(--surface)" stroke="var(--border)" /><text x="251" y="271" textAnchor="middle">answered by</text></>}
              {edgeVisible('reply', 'oio') && <><rect x="470" y="326" width="68" height="22" rx="5" fill="var(--surface)" stroke="var(--border)" /><text x="504" y="341" textAnchor="middle">decided by</text></>}
              {edgeVisible('oio', 'appeal') && <><rect x="722" y="202" width="86" height="22" rx="5" fill="var(--surface)" stroke="var(--border)" /><text x="765" y="217" textAnchor="middle">challenged by</text></>}
            </g>
          </svg>

          {visibleNodes.map((node) => <TimelineNode key={node.id} node={node} selected={selectedId === node.id} onSelect={() => onSelect(node.id)} />)}
          {visibleNodes.length === 0 && <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-5 text-center shadow-[var(--shadow-sm)]"><p className="text-sm font-semibold text-[var(--text-primary)]">No documents match these filters</p><button type="button" onClick={clearFilters} className="mt-2 text-xs font-medium text-[var(--primary)] hover:underline">Clear filters</button></div>}

          <div className="absolute bottom-4 left-4 z-20 flex items-center gap-1 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-sm)]">
            <Button variant="ghost" size="icon" aria-label="Zoom out" title="Zoom out"><ZoomOut size={17} /></Button>
            <Button variant="ghost" size="icon" aria-label="Zoom in" title="Zoom in"><ZoomIn size={17} /></Button>
            <Button variant="ghost" size="sm"><Maximize2 size={15} />Fit timeline</Button>
          </div>
          {showSuggested && edgeVisible('scn', 'hearing') && <div className="absolute bottom-4 left-1/2 z-20 -translate-x-1/2 rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] px-3 py-2 text-xs font-medium text-[var(--text-primary)] shadow-[var(--shadow-sm)]"><span className="mr-2 inline-block h-0 w-7 border-t border-dashed border-[var(--warning)] align-middle" />1 suggested relationship</div>}
        </>
      )}

      <div className="absolute left-4 top-20 z-30 flex items-center gap-1 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-sm)]">
        <Button variant="ghost" size="sm" onClick={() => setFiltersOpen((open) => !open)} aria-expanded={filtersOpen}>
          <SlidersHorizontal size={15} />Filter{activeFilterCount > 0 && <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-[var(--primary)] px-1 text-[10px] text-[var(--on-accent)]">{activeFilterCount}</span>}
        </Button>
        <span className="mx-1 h-5 w-px bg-[var(--border)]" />
        <Button
          variant="ghost"
          size="sm"
          onClick={() => onModeChange(mode === 'graph' ? 'list' : 'graph')}
          aria-label={`Switch to ${mode === 'graph' ? 'chronology' : 'graph'} view`}
        >
          {mode === 'graph' ? <List size={14} /> : <GitBranch size={14} />}
          {mode === 'graph' ? 'Chronology' : 'Graph'}
        </Button>
        {mode === 'list' && showSuggested && <Badge variant="warning" className="ml-1">1 link to review</Badge>}
      </div>

      {filtersOpen && (
        <div className="absolute left-4 top-32 z-40 w-[280px] rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3 shadow-[var(--shadow-lg)]">
          <div className="flex items-center justify-between"><h3 className="text-sm font-semibold text-[var(--text-primary)]">Timeline filters</h3><button type="button" onClick={clearFilters} className="text-xs font-medium text-[var(--primary)] hover:underline">Clear</button></div>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Filters only change this view. They never alter the matter.</p>
          <div className="mt-4"><p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)]">Direction</p><div className="grid grid-cols-3 gap-1">{(['all', 'incoming', 'outgoing'] as const).map((value) => <button key={value} type="button" onClick={() => { setDirection(value); onSelect(null) }} className={cn('min-h-9 rounded-[var(--radius-sm)] border px-2 text-xs capitalize', direction === value ? 'border-[var(--primary)] bg-[var(--accent-muted)] font-medium text-[var(--primary)]' : 'border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]')}>{value}</button>)}</div></div>
          <div className="mt-4"><p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)]">Focus</p><div className="grid gap-1">{([{ id: 'all', label: 'All documents' }, { id: 'deadline', label: 'Has a deadline' }, { id: 'financial', label: 'Has financial impact' }] as const).map((value) => <button key={value.id} type="button" onClick={() => { setFact(value.id); onSelect(null) }} className={cn('flex min-h-9 items-center justify-between rounded-[var(--radius-sm)] border px-3 text-left text-xs', fact === value.id ? 'border-[var(--primary)] bg-[var(--accent-muted)] font-medium text-[var(--primary)]' : 'border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]')}>{value.label}{fact === value.id && <Check size={14} />}</button>)}</div></div>
          <label className="mt-4 flex min-h-11 cursor-pointer items-center justify-between rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-xs text-[var(--text-secondary)]"><span>Show suggested relationships</span><input type="checkbox" checked={showSuggested} onChange={(event) => setShowSuggested(event.target.checked)} className="h-4 w-4 accent-[var(--primary)]" /></label>
          <p className="mt-3 text-xs text-[var(--text-muted)]">Showing {visibleNodes.length} of {timelineNodes.length} documents</p>
        </div>
      )}
    </div>
  )
}

function FilesView() {
  const [category, setCategory] = useState('All files')
  const [linked, setLinked] = useState<'all' | 'linked' | 'unlinked'>('all')
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [query, setQuery] = useState('')
  const categories = ['All files', 'Evidence', 'Invoices', 'Correspondence', 'Research', 'Other']
  const activeFilterCount = Number(category !== 'All files') + Number(linked !== 'all')
  const visibleFiles = supportingFiles.filter((file) => {
    const categoryMatches = category === 'All files' || file.category === category
    const linkedMatches = linked === 'all' || (linked === 'linked' ? file.linked !== 'Not linked' : file.linked === 'Not linked')
    const queryMatches = file.title.toLowerCase().includes(query.trim().toLowerCase())
    return categoryMatches && linkedMatches && queryMatches
  })

  const clearFilters = () => {
    setCategory('All files')
    setLinked('all')
  }

  return (
    <div className="h-full overflow-y-auto px-4 pb-24 pt-5 md:px-8 md:pb-8 md:pt-16">
      <div className="mx-auto max-w-6xl">
        <div className="relative min-w-0 overflow-visible rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]">
          <div className="flex min-h-12 items-center gap-3 border-b border-[var(--border)] px-3 md:px-4">
            <Search size={16} className="shrink-0 text-[var(--text-muted)]" />
            <input value={query} onChange={(event) => setQuery(event.target.value)} aria-label="Search matter files" placeholder="Search matter files" className="min-w-0 flex-1 bg-transparent text-sm text-[var(--text-primary)] outline-none placeholder:text-[var(--text-disabled)]" />
            <Button variant="ghost" size="sm" onClick={() => setFiltersOpen((open) => !open)} aria-expanded={filtersOpen}><SlidersHorizontal size={15} />Filters{activeFilterCount > 0 && <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-[var(--primary)] px-1 text-[10px] text-[var(--on-accent)]">{activeFilterCount}</span>}</Button>
            <Button size="sm"><Upload size={15} /><span className="hidden sm:inline">Upload files</span><span className="sm:hidden">Upload</span></Button>
          </div>
          {filtersOpen && (
            <div className="absolute right-3 top-14 z-40 w-[300px] rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3 shadow-[var(--shadow-lg)]">
              <div className="flex items-center justify-between"><h3 className="text-sm font-semibold text-[var(--text-primary)]">File filters</h3><button type="button" onClick={clearFilters} className="text-xs font-medium text-[var(--primary)] hover:underline">Clear</button></div>
              <div className="mt-4"><p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)]">Category</p><div className="grid grid-cols-2 gap-1">{categories.map((item) => <button key={item} type="button" onClick={() => setCategory(item)} className={cn('flex min-h-9 items-center justify-between rounded-[var(--radius-sm)] border px-2.5 text-left text-xs', category === item ? 'border-[var(--primary)] bg-[var(--accent-muted)] font-medium text-[var(--primary)]' : 'border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]')}><span>{item}</span><span className="text-[10px] text-[var(--text-muted)]">{item === 'All files' ? 12 : supportingFiles.filter((file) => file.category === item).length}</span></button>)}</div></div>
              <div className="mt-4"><p className="mb-2 text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)]">Proceeding link</p><div className="grid grid-cols-3 gap-1">{(['all', 'linked', 'unlinked'] as const).map((value) => <button key={value} type="button" onClick={() => setLinked(value)} className={cn('min-h-9 rounded-[var(--radius-sm)] border px-2 text-xs capitalize', linked === value ? 'border-[var(--primary)] bg-[var(--accent-muted)] font-medium text-[var(--primary)]' : 'border-[var(--border)] text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]')}>{value}</button>)}</div></div>
              <p className="mt-3 text-xs text-[var(--text-muted)]">Showing {visibleFiles.length} sample files</p>
            </div>
          )}
          <div className="hidden grid-cols-[minmax(300px,1.8fr)_130px_110px_160px_44px] gap-3 border-b border-[var(--border)] bg-[var(--bg-overlay)] px-4 py-2 text-[11px] font-semibold uppercase tracking-[0.06em] text-[var(--text-muted)] md:grid"><span>File</span><span>Category</span><span>Added</span><span>Linked to</span><span /></div>
          <div className="divide-y divide-[var(--border-subtle)]">
            {visibleFiles.map((file) => (
              <div key={file.title} className="px-3 py-3 transition-colors hover:bg-[var(--surface-hover)] md:px-4">
                <div className="flex items-start gap-3 md:hidden">
                  <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-muted)]"><FileText size={18} /></div>
                  <div className="min-w-0 flex-1"><p className="truncate text-sm font-medium text-[var(--text-primary)]">{file.title}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">{file.type} · {file.size} · {file.metadata}</p><div className="mt-2 flex min-w-0 items-center gap-2"><Badge variant="muted" className="min-h-5 px-1.5 py-0 text-[10px]">{file.category}</Badge><span className="shrink-0 text-[11px] text-[var(--text-muted)]">{file.added}</span><span className="truncate text-[11px] text-[var(--text-muted)]">· {file.linked}</span></div></div>
                  <Button variant="ghost" size="icon" className="-mr-1 -mt-1 shrink-0" aria-label={`More actions for ${file.title}`} title="More actions"><MoreHorizontal size={17} /></Button>
                </div>
                <div className="hidden grid-cols-[minmax(300px,1.8fr)_130px_110px_160px_44px] items-center gap-3 md:grid">
                  <div className="flex min-w-0 items-center gap-3"><div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] text-[var(--text-muted)]"><FileText size={18} /></div><div className="min-w-0"><p className="truncate text-sm font-medium text-[var(--text-primary)]">{file.title}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">{file.type} · {file.size} · {file.metadata}</p></div></div>
                  <div><Badge variant="muted">{file.category}</Badge></div><span className="text-xs text-[var(--text-secondary)]">{file.added}</span><span className="truncate text-xs text-[var(--text-secondary)]">{file.linked}</span><Button variant="ghost" size="icon" aria-label={`More actions for ${file.title}`} title="More actions"><MoreHorizontal size={17} /></Button>
                </div>
              </div>
            ))}
            {visibleFiles.length === 0 && <div className="px-4 py-10 text-center"><p className="text-sm font-medium text-[var(--text-primary)]">No files match these filters</p><button type="button" onClick={clearFilters} className="mt-2 text-xs font-medium text-[var(--primary)] hover:underline">Clear filters</button></div>}
          </div>
        </div>
      </div>
    </div>
  )
}

function SectionPreview({ section }: { section: Exclude<Section, 'timeline' | 'files'> }) {
  const item = sectionItems.find((candidate) => candidate.id === section)!
  const Icon = item.icon
  const copy: Record<typeof section, { title: string; body: string; facts: string[] }> = {
    brief: { title: 'Case Brief', body: 'A sourced, living orientation layer—not a periodic AI essay. It answers what the dispute is, where it stands, what changed, and what remains unresolved.', facts: ['Every claim links to evidence', 'Human-authored blocks are preserved', 'Refresh only affected sections'] },
    notes: { title: 'Matter conversation', body: 'A focused collaboration stream with @mentions, document quotes, decisions, and follow-ups—connected to evidence without turning the timeline into chat.', facts: ['@mention organisation members', 'Quote exact PDF passages', 'Resolve decisions and tasks'] },
    deadlines: { title: 'Deadlines', body: 'One operational view for extracted and manually-created obligations, with accountable owners and evidence for every extracted date.', facts: ['Calendar and chronology views', 'Extracted versus manual provenance', 'Reminder and escalation rules'] },
    financials: { title: 'Financials', body: 'A case-value ledger showing how demand, penalty, interest, pre-deposit, and confirmed amounts evolve across proceeding documents.', facts: ['₹14.2L proposed → ₹50K confirmed', 'Source-backed amount events', 'Separate litigation expenses'] },
    details: { title: 'Matter details', body: 'Stable matter identity, parties, jurisdiction, assignments, tags, and custom metadata—kept out of the working canvas until needed.', facts: ['Controlled edit permissions', 'Complete change history', 'Custom organisation fields'] },
    activity: { title: 'Matter activity', body: 'A complete, filterable audit-friendly feed of meaningful human and system actions scoped to this matter.', facts: ['People, documents, and decisions', 'Deep links to changed objects', 'Noise-free event grouping'] },
  }
  const content = copy[section]
  return (
    <div className="h-full overflow-y-auto px-4 pb-24 pt-5 md:px-8 md:pb-8 md:pt-16"><div className="mx-auto max-w-4xl"><div className="rounded-[var(--radius-lg)] border border-[var(--border)] bg-[var(--surface)] p-6 shadow-[var(--shadow-sm)] md:p-10"><div className="flex h-12 w-12 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)] text-[var(--primary)]"><Icon size={23} /></div><p className="mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-[var(--text-muted)]">Direction preview</p><h2 className="mt-2 text-2xl font-semibold text-[var(--text-primary)]">{content.title}</h2><p className="mt-3 max-w-2xl text-base leading-7 text-[var(--text-secondary)]">{content.body}</p><div className="mt-7 grid gap-3 sm:grid-cols-3">{content.facts.map((fact) => <div key={fact} className="flex items-start gap-2 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-3 text-sm text-[var(--text-primary)]"><Check size={16} className="mt-0.5 shrink-0 text-[var(--success)]" />{fact}</div>)}</div></div></div></div>
  )
}

export function MatterWorkspaceConcept() {
  const [section, setSection] = useState<Section>('timeline')
  const [timelineMode, setTimelineMode] = useState<TimelineMode>('graph')
  const [selectedId, setSelectedId] = useState<string | null>('oio')
  const selectedNode = useMemo(() => timelineNodes.find((node) => node.id === selectedId) ?? null, [selectedId])

  const changeSection = (next: Section) => {
    setSection(next)
    if (next !== 'timeline') setSelectedId(null)
  }

  return (
    <div className="flex h-dvh min-h-[620px] overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]">
      <aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border)] bg-[var(--sidebar-bg)] py-3 text-[var(--sidebar-text)] md:flex">
        <div className="mb-5 flex h-10 w-10 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent)] text-[var(--on-accent)]"><Scale size={21} /></div>
        <nav aria-label="Application navigation" className="flex flex-1 flex-col items-center gap-1">
          {navItems.map((item) => { const Icon = item.icon; return <button key={item.label} type="button" aria-label={item.label} title={item.label} className={cn('flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] transition-colors', item.selected ? 'bg-[var(--sidebar-active)] text-[var(--sidebar-active-text)]' : 'text-[var(--sidebar-text-muted)] hover:bg-[var(--sidebar-hover)] hover:text-[var(--sidebar-text)]')}><Icon size={19} /></button> })}
        </nav>
        <button type="button" aria-label="Settings" title="Settings" className="flex h-11 w-11 items-center justify-center rounded-[var(--radius-sm)] text-[var(--sidebar-text-muted)] hover:bg-[var(--sidebar-hover)] hover:text-[var(--sidebar-text)]"><Settings size={19} /></button>
      </aside>

      <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <header className="flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border)] bg-[var(--surface)] px-3 md:h-12 md:px-5">
          <Button variant="ghost" size="icon" className="md:hidden" aria-label="Open navigation"><Menu size={20} /></Button>
          <div className="hidden items-center gap-2 text-sm text-[var(--text-muted)] md:flex"><span>Matters</span><span>/</span><span className="font-medium text-[var(--text-primary)]">Apex Auto Components</span></div>
          <div className="md:hidden"><p className="text-sm font-semibold">Apex Auto Components</p><p className="text-[11px] text-[var(--text-muted)]">MAT-2024-018</p></div>
          <button className="ml-auto hidden h-9 w-[280px] items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] px-3 text-left text-sm text-[var(--text-muted)] md:flex"><Search size={16} />Search this matter<span className="ml-auto text-[11px]">⌘ K</span></button>
          <Button variant="ghost" size="icon" aria-label="Notifications" title="Notifications"><Bell size={18} /></Button>
          <button type="button" className="flex h-9 items-center gap-2 rounded-[var(--radius-sm)] px-1.5 hover:bg-[var(--surface-hover)]"><span className="flex h-7 w-7 items-center justify-center rounded-full bg-[var(--accent-muted)] text-xs font-semibold text-[var(--primary)]">RJ</span><ChevronDown size={14} className="hidden text-[var(--text-muted)] md:block" /></button>
        </header>

        <section className="flex min-h-[76px] shrink-0 items-center gap-4 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-2 md:min-h-16 md:px-6">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="truncate text-lg font-semibold md:text-xl">Apex Auto Components · ITC mismatch</h1>
              <Badge variant="success">Active</Badge>
            </div>
            <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[var(--text-muted)]">
              <span>MAT-2024-018</span>
              <span className="hidden h-3 w-px bg-[var(--border-strong)] sm:block" />
              <span>FY 2023–24</span>
              <span className="hidden h-3 w-px bg-[var(--border-strong)] sm:block" />
              <span className="hidden sm:inline">CGST · Pune</span>
              <span className="hidden h-3 w-px bg-[var(--border-strong)] md:block" />
              <div className="group relative hidden md:block">
                <Badge
                  variant="success"
                  tabIndex={0}
                  aria-describedby="matter-live-status-help"
                  className="gap-1.5"
                >
                  <span className="h-1.5 w-1.5 rounded-full bg-[var(--success)] motion-safe:animate-pulse" aria-hidden="true" />
                  Live
                </Badge>
                <div
                  id="matter-live-status-help"
                  role="tooltip"
                  className="pointer-events-none absolute left-0 top-[calc(100%+8px)] z-50 w-max max-w-64 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-2.5 py-2 text-xs font-normal text-[var(--text-secondary)] opacity-0 shadow-[var(--shadow-md)] transition-opacity group-focus-within:opacity-100 group-hover:opacity-100"
                >
                  Live updates connected. Changes appear automatically.
                </div>
              </div>
            </div>
          </div>
          <div className="ml-auto flex shrink-0 items-center gap-2">
            <Button className="hidden sm:inline-flex"><Plus size={16} />Add document</Button>
            <Button variant="secondary" size="icon" aria-label="More matter actions" title="More matter actions"><MoreHorizontal size={18} /></Button>
          </div>
        </section>

        <div className="relative min-h-0 flex-1 overflow-hidden bg-[var(--bg)]">
          <SectionSwitcher active={section} onChange={changeSection} inspectorOpen={section === 'timeline' && selectedNode !== null} />
          <div className="absolute inset-x-0 bottom-0 z-40 flex h-16 items-center gap-1 overflow-x-auto border-t border-[var(--border)] bg-[var(--surface)] px-2 md:hidden">
            {sectionItems.map((item) => { const Icon = item.icon; return <button key={item.id} type="button" onClick={() => changeSection(item.id)} className={cn('flex h-12 min-w-[64px] flex-1 flex-col items-center justify-center gap-1 rounded-[var(--radius-sm)] text-[10px] font-medium', section === item.id ? 'bg-[var(--accent-muted)] text-[var(--primary)]' : 'text-[var(--text-muted)]')}><Icon size={17} />{item.label}</button> })}
          </div>

          {section === 'timeline' && (
            <>
              <div className={cn('hidden h-full transition-[margin] md:block', selectedNode && 'mr-[394px]')}><TimelineCanvas selectedId={selectedId} onSelect={setSelectedId} mode={timelineMode} onModeChange={setTimelineMode} /></div>
              <div className="h-full md:hidden"><TimelineList selectedId={selectedId} onSelect={setSelectedId} /></div>
            </>
          )}
          {section === 'files' && <FilesView />}
          {section !== 'timeline' && section !== 'files' && <SectionPreview section={section} />}

          {section === 'timeline' && selectedNode && <DocumentInspector node={selectedNode} onClose={() => setSelectedId(null)} />}
          {section === 'timeline' && !selectedNode && <div className="absolute right-4 top-20 z-20 hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-xs text-[var(--text-muted)] shadow-[var(--shadow-sm)] md:block">Select a document to inspect its evidence and relationships</div>}
          {section === 'timeline' && !selectedNode && <div className="absolute bottom-20 right-3 z-40 sm:hidden"><Button><Plus size={17} />Add document</Button></div>}
        </div>
      </main>
    </div>
  )
}
