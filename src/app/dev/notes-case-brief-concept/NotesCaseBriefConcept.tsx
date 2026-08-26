'use client'

import { useMemo, useRef, useState } from 'react'
import {
  Activity,
  ArrowLeft,
  AtSign,
  Bell,
  BookOpen,
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  CircleDollarSign,
  Clock3,
  FileText,
  FolderOpen,
  Gavel,
  Highlighter,
  LayoutGrid,
  Link2,
  ListFilter,
  Menu,
  MessageSquare,
  MoreHorizontal,
  Plus,
  Search,
  Send,
  ShieldCheck,
  Sparkles,
  Users,
  X,
} from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

type WorkspaceView = 'notes' | 'brief'
type Evidence = { document: string; page: number; excerpt: string; version: string }

const sections = [
  { label: 'Timeline', count: 5, icon: Activity },
  { label: 'Files', count: 12, icon: FolderOpen },
  { label: 'Case Brief', icon: BookOpen, view: 'brief' as const },
  { label: 'Notes', count: 8, icon: MessageSquare, view: 'notes' as const },
  { label: 'Deadlines', count: 3, icon: CalendarDays },
  { label: 'Financials', icon: CircleDollarSign },
  { label: 'Activity', icon: Activity },
  { label: 'Details', icon: FileText },
]

const threads = [
  { id: 'hearing', title: 'Hearing preparation', preview: 'I have linked the exact paragraph…', time: '10:42', unread: 2, category: 'Strategy', initials: 'AK' },
  { id: 'client', title: 'Client instructions', preview: 'Documents requested from accounts team', time: 'Yesterday', unread: 0, category: 'Client', initials: 'RJ' },
  { id: 'research', title: 'Section 16 research', preview: 'The limitation point needs a closer look', time: 'Mon', unread: 0, category: 'Research', initials: 'MS' },
  { id: 'general', title: 'Matter discussion', preview: 'Initial review and internal observations', time: '18 Aug', unread: 0, category: 'General', initials: 'AK' },
]

const defaultEvidence: Evidence = {
  document: 'Order-in-Original',
  page: 8,
  version: 'PDF version 2 · verified copy',
  excerpt: 'The proper officer records that the reconciliation submitted by the taxpayer explains the principal mismatch, subject to verification of the remaining invoices.',
}

function AppRail() {
  return (
    <aside className="hidden w-14 shrink-0 flex-col items-center border-r border-[var(--border-subtle)] bg-[var(--sidebar-bg)] py-2 text-[var(--sidebar-text)] lg:flex">
      <div className="mb-4 flex size-9 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--sidebar-text-active)]"><Gavel className="size-5" /></div>
      {[LayoutGrid, FolderOpen, Users, FileText, CalendarDays].map((Icon, index) => (
        <button key={index} aria-label="Application section" className={cn('mb-2 flex size-11 items-center justify-center rounded-[var(--radius-sm)]', index === 1 ? 'bg-[var(--sidebar-active)] text-[var(--sidebar-text-active)]' : 'hover:bg-[var(--sidebar-hover)]')}>
          <Icon className="size-5" />
        </button>
      ))}
      <div className="mt-auto flex size-9 items-center justify-center rounded-full border border-[var(--sidebar-border)] text-xs font-semibold">RJ</div>
    </aside>
  )
}

function MatterHeader() {
  return (
    <>
      <div className="hidden h-10 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-5 text-sm lg:flex">
        <span className="text-[var(--text-muted)]">Matters</span><ChevronRight className="size-4 text-[var(--text-muted)]" /><span>Apex Auto Components</span>
        <div className="ml-auto flex items-center gap-3">
          <div className="flex h-8 w-64 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] px-3 text-xs text-[var(--text-muted)]"><Search className="size-4" />Search this matter <span className="ml-auto">⌘ K</span></div>
          <Bell className="size-4" /><span className="flex size-7 items-center justify-center rounded-full bg-[var(--accent-muted)] text-xs font-semibold text-[var(--accent)]">RJ</span><ChevronDown className="size-4" />
        </div>
      </div>
      <header className="flex min-h-[58px] shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-4 lg:px-5">
        <button aria-label="Open navigation" className="flex size-11 items-center justify-center lg:hidden"><Menu className="size-6" /></button>
        <div className="min-w-0">
          <div className="flex min-w-0 items-center gap-2">
            <h1 className="truncate text-base font-semibold text-[var(--text-primary)] lg:text-lg">Apex Auto Components · ITC mismatch</h1>
            <Badge variant="success" fixedWidth="sm">Active</Badge>
          </div>
          <div className="mt-0.5 flex items-center gap-2 truncate text-xs text-[var(--text-muted)]"><span>MAT-2024-018</span><span>·</span><span>FY 2023–24</span><span>·</span><span>CGST · Pune</span><Badge variant="success" className="min-h-5 px-1.5 py-0 text-[10px]"><span className="relative flex size-1.5"><span className="absolute inline-flex size-full animate-ping rounded-full bg-[var(--success)] opacity-60" /><span className="relative inline-flex size-1.5 rounded-full bg-[var(--success)]" /></span>Live</Badge></div>
        </div>
        <div className="ml-auto flex items-center gap-2"><Button size="sm" className="hidden sm:inline-flex"><Plus className="size-4" />Add document</Button><Button variant="outline" size="icon" aria-label="More matter actions"><MoreHorizontal className="size-5" /></Button></div>
      </header>
    </>
  )
}

function SectionNav({ view, onChange }: { view: WorkspaceView; onChange: (view: WorkspaceView) => void }) {
  return (
    <nav aria-label="Matter sections" className="absolute left-1/2 top-2 z-20 hidden -translate-x-1/2 items-center rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-1 shadow-md lg:flex">
      {sections.map(({ label, count, icon: Icon, view: target }) => (
        <button key={label} onClick={() => target && onChange(target)} className={cn('flex min-h-9 items-center gap-1.5 whitespace-nowrap rounded-[var(--radius-sm)] px-3 text-xs transition-colors', target === view ? 'bg-[var(--primary)] text-[var(--on-accent)]' : 'text-[var(--text-secondary)] hover:bg-[var(--surface-hover)]', !target && 'cursor-default')}>
          <Icon className="size-4" /><span>{label}</span>{count !== undefined && <span className="text-[10px] opacity-75">{count}</span>}
        </button>
      ))}
    </nav>
  )
}

function ThreadList({ selected, onSelect }: { selected: string; onSelect: (id: string) => void }) {
  return (
    <aside className="flex h-full min-w-0 flex-col border-r border-[var(--border-subtle)] bg-[var(--surface)] lg:w-[310px] lg:shrink-0">
      <div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-3">
        <div className="flex h-9 min-w-0 flex-1 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] px-3 text-sm text-[var(--text-muted)]"><Search className="size-4" /><span className="truncate">Search notes</span></div>
        <Button variant="outline" size="icon" aria-label="Filter note threads"><ListFilter className="size-4" /></Button>
        <Button size="icon" aria-label="Start note thread"><Plus className="size-4" /></Button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {threads.map((thread) => (
          <button key={thread.id} onClick={() => onSelect(thread.id)} className={cn('flex w-full gap-3 border-b border-[var(--border-subtle)] px-3 py-3 text-left hover:bg-[var(--surface-hover)]', selected === thread.id && 'bg-[var(--accent-muted)]')}>
            <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--bg-overlay)] text-xs font-semibold text-[var(--text-secondary)]">{thread.initials}</span>
            <span className="min-w-0 flex-1">
              <span className="flex items-center gap-2"><span className="truncate text-sm font-semibold">{thread.title}</span><span className="ml-auto shrink-0 text-[10px] text-[var(--text-muted)]">{thread.time}</span></span>
              <span className="mt-0.5 flex items-center gap-2"><Badge variant="muted" className="min-h-5 px-1.5 py-0 text-[10px]">{thread.category}</Badge>{thread.unread > 0 && <span className="ml-auto flex size-5 items-center justify-center rounded-full bg-[var(--primary)] text-[10px] font-semibold text-[var(--on-accent)]">{thread.unread}</span>}</span>
              <span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{thread.preview}</span>
            </span>
          </button>
        ))}
      </div>
    </aside>
  )
}

function EvidenceCard({ evidence, onOpen }: { evidence: Evidence; onOpen: () => void }) {
  return (
    <button onClick={onOpen} className="mt-2 block w-full max-w-xl rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--bg-overlay)] p-3 text-left hover:border-[var(--accent)]">
      <span className="flex items-center gap-2 text-xs font-semibold text-[var(--accent)]"><Highlighter className="size-4" />Quoted from {evidence.document}<span className="ml-auto font-normal text-[var(--text-muted)]">Page {evidence.page}</span></span>
      <span className="mt-2 block border-l-2 border-[var(--accent)] pl-3 text-sm leading-5 text-[var(--text-secondary)]">“{evidence.excerpt}”</span>
      <span className="mt-2 flex items-center gap-1 text-xs font-medium text-[var(--accent)]">Open exact source <ChevronRight className="size-3.5" /></span>
    </button>
  )
}

function MessageFeed({ onEvidence }: { onEvidence: () => void }) {
  return (
    <div className="mx-auto w-full max-w-3xl space-y-5 px-4 py-5 lg:px-7">
      <div className="flex gap-3">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--accent-muted)] text-xs font-semibold text-[var(--accent)]">AK</span>
        <div className="min-w-0"><div className="flex flex-wrap items-baseline gap-2"><span className="text-sm font-semibold">Ananya Kapoor</span><span className="text-xs text-[var(--text-muted)]">Today, 09:18</span></div><p className="mt-1 text-sm leading-6">The department has accepted most of our reconciliation. <span className="rounded bg-[var(--accent-muted)] px-1 font-medium text-[var(--accent)]">@Rishikesh</span>, please confirm whether the residual invoices were included in the appeal set.</p></div>
      </div>
      <div className="flex gap-3">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--bg-overlay)] text-xs font-semibold">RJ</span>
        <div className="min-w-0 flex-1"><div className="flex flex-wrap items-baseline gap-2"><span className="text-sm font-semibold">Rishikesh Joshi</span><span className="text-xs text-[var(--text-muted)]">Today, 09:41</span><span className="text-[10px] text-[var(--text-muted)]">Edited</span></div><p className="mt-1 text-sm leading-6">Yes. The relevant finding is on page 8 of the signed order. I have linked the exact paragraph here.</p><EvidenceCard evidence={defaultEvidence} onOpen={onEvidence} /></div>
      </div>
      <div className="flex items-center gap-3"><span className="h-px flex-1 bg-[var(--border-subtle)]" /><span className="rounded-full bg-[var(--accent-muted)] px-3 py-1 text-xs font-semibold text-[var(--accent)]">2 new notes</span><span className="h-px flex-1 bg-[var(--border-subtle)]" /></div>
      <div className="flex gap-3">
        <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--bg-overlay)] text-xs font-semibold">MS</span>
        <div className="min-w-0 flex-1"><div className="flex flex-wrap items-baseline gap-2"><span className="text-sm font-semibold">Meera Shah</span><span className="text-xs text-[var(--text-muted)]">Today, 10:17</span></div><p className="mt-1 text-sm leading-6">I created a follow-up for the invoice verification. It should be completed before we finalise the grounds.</p><div className="mt-2 flex max-w-xl items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] p-3"><CheckCircle2 className="size-5 shrink-0 text-[var(--success)]" /><div className="min-w-0"><div className="text-sm font-semibold">Verify 11 residual invoices</div><div className="text-xs text-[var(--text-muted)]">Assigned to Rishikesh · Due 27 Aug</div></div><Badge variant="warning" className="ml-auto">Open</Badge></div></div>
      </div>
    </div>
  )
}

function Composer() {
  const [value, setValue] = useState('')
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const mentionMembers = ['Rishikesh Joshi', 'Meera Shah', 'Ananya Kapoor']
  const mentionMatch = value.match(/@([\p{L}\p{N}._-]*)$/u)
  const mentionQuery = mentionMatch?.[1] ?? null
  const matchingMembers = mentionQuery === null
    ? []
    : mentionMembers.filter((name) => name.toLocaleLowerCase().includes(mentionQuery.toLocaleLowerCase()))

  const startMention = () => {
    setValue((current) => `${current}${current && !current.endsWith(' ') ? ' ' : ''}@`)
    requestAnimationFrame(() => textareaRef.current?.focus())
  }

  const selectMention = (name: string) => {
    if (!mentionMatch || mentionMatch.index === undefined) return
    setValue(`${value.slice(0, mentionMatch.index)}@${name} `)
  }

  return (
    <div className="relative shrink-0 border-t border-[var(--border-subtle)] bg-[var(--bg)] p-3">
      {mentionQuery !== null && <div role="listbox" aria-label="Mention a team member" className="absolute bottom-[112px] left-4 z-20 w-[min(18rem,calc(100vw-2rem))] rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-1 shadow-lg"><div className="flex min-h-9 items-center gap-2 border-b border-[var(--border-subtle)] px-3 text-xs text-[var(--text-muted)]"><Search className="size-4" /><span className="truncate">{mentionQuery ? `Searching for “${mentionQuery}”` : 'Type a name to search'}</span></div>{matchingMembers.length > 0 ? matchingMembers.map((name) => <button role="option" aria-selected="false" key={name} onMouseDown={(event) => event.preventDefault()} onClick={() => selectMention(name)} className="flex min-h-11 w-full items-center gap-2 rounded-[var(--radius-sm)] px-3 text-left text-sm hover:bg-[var(--surface-hover)]"><span className="flex size-7 items-center justify-center rounded-full bg-[var(--accent-muted)] text-[10px] font-semibold text-[var(--accent)]">{name.split(' ').map((part) => part[0]).join('')}</span><span className="min-w-0"><span className="block truncate font-medium">{name}</span><span className="block text-[10px] text-[var(--text-muted)]">Matter team</span></span></button>) : <div className="px-3 py-4 text-sm text-[var(--text-muted)]">No accessible members found</div>}</div>}
      <div className="mx-auto max-w-3xl rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--bg)] focus-within:ring-2 focus-within:ring-[var(--accent-ring)]">
        <textarea ref={textareaRef} value={value} onChange={(event) => setValue(event.target.value)} placeholder="Write a note… Type @ to mention someone" className="min-h-16 w-full resize-none bg-transparent px-3 pt-3 text-sm outline-none focus-visible:!outline-none placeholder:text-[var(--text-muted)]" />
        <div className="flex items-center gap-1 border-t border-[var(--border-subtle)] px-2 py-1.5"><Button variant="ghost" size="sm" onClick={startMention}><AtSign className="size-4" />Mention</Button><Button variant="ghost" size="sm"><Highlighter className="size-4" />Quote document</Button><Button variant="ghost" size="sm" className="hidden sm:inline-flex"><CheckCircle2 className="size-4" />Create task</Button><Button size="sm" className="ml-auto"><Send className="size-4" />Send</Button></div>
      </div>
    </div>
  )
}

function SourcePanel({ evidence, onClose }: { evidence: Evidence; onClose: () => void }) {
  return (
    <aside className="absolute inset-y-0 right-0 z-30 flex w-full max-w-sm flex-col border-l border-[var(--border-subtle)] bg-[var(--surface)] shadow-xl lg:relative lg:shadow-none">
      <div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-4"><Highlighter className="size-4 text-[var(--accent)]" /><span className="text-sm font-semibold">Source context</span><Button variant="ghost" size="icon" className="ml-auto" onClick={onClose} aria-label="Close source context"><X className="size-4" /></Button></div>
      <div className="min-h-0 flex-1 overflow-y-auto p-4"><Badge variant="success"><ShieldCheck className="size-3.5" />Exact source</Badge><h3 className="mt-3 font-semibold">{evidence.document}</h3><p className="mt-1 text-xs text-[var(--text-muted)]">{evidence.version}</p><div className="mt-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-3"><div className="text-xs font-semibold text-[var(--text-muted)]">PAGE {evidence.page}</div><p className="mt-2 border-l-2 border-[var(--accent)] pl-3 text-sm leading-6">{evidence.excerpt}</p></div><Button className="mt-4 w-full"><FileText className="size-4" />Open PDF at highlighted text</Button><p className="mt-3 text-xs leading-5 text-[var(--text-muted)]">The quote stays attached to this immutable PDF version. For scanned pages, the saved page region is highlighted even when text selection is unavailable.</p></div>
    </aside>
  )
}

function NotesWorkspace() {
  const [selected, setSelected] = useState('hearing')
  const [mobileThread, setMobileThread] = useState(false)
  const [evidenceOpen, setEvidenceOpen] = useState(false)
  const selectedThread = useMemo(() => threads.find((thread) => thread.id === selected) ?? threads[0], [selected])
  const selectThread = (id: string) => { setSelected(id); setMobileThread(true) }
  return (
    <div className="relative flex min-h-0 flex-1 overflow-hidden border-t border-[var(--border-subtle)] lg:mt-[54px] lg:rounded-t-[var(--radius-md)] lg:border lg:border-b-0">
      <div className={cn('h-full w-full lg:block lg:w-auto', mobileThread && 'hidden lg:block')}><ThreadList selected={selected} onSelect={selectThread} /></div>
      <section className={cn('min-w-0 flex-1 flex-col bg-[var(--bg)]', mobileThread ? 'flex' : 'hidden lg:flex')}>
        <div className="flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 lg:px-4"><Button variant="ghost" size="icon" className="lg:hidden" onClick={() => setMobileThread(false)} aria-label="Back to note threads"><ArrowLeft className="size-5" /></Button><div className="min-w-0"><h2 className="truncate text-sm font-semibold">{selectedThread.title}</h2><p className="truncate text-xs text-[var(--text-muted)]">4 participants · Matter team</p></div><Button variant="outline" size="sm" className="ml-auto hidden sm:inline-flex"><Users className="size-4" />Participants</Button><Button variant="ghost" size="icon" aria-label="More thread actions"><MoreHorizontal className="size-5" /></Button></div>
        <div className="min-h-0 flex-1 overflow-y-auto"><MessageFeed onEvidence={() => setEvidenceOpen(true)} /></div><Composer />
      </section>
      {evidenceOpen && <SourcePanel evidence={defaultEvidence} onClose={() => setEvidenceOpen(false)} />}
    </div>
  )
}

const briefSections = [
  { title: 'Current posture', sources: 3, state: 'Current' },
  { title: 'Issues in dispute', sources: 4, state: 'Current' },
  { title: 'Positions & findings', sources: 6, state: 'Review' },
  { title: 'Key turning points', sources: 4, state: 'Current' },
  { title: 'Open questions', sources: 2, state: 'Current' },
]

function CaseBriefWorkspace() {
  const [sourceOpen, setSourceOpen] = useState(false)
  const [outlineOpen, setOutlineOpen] = useState(false)
  return (
    <div className="relative flex min-h-0 flex-1 overflow-hidden border-t border-[var(--border-subtle)] bg-[var(--surface)] lg:mt-[54px] lg:rounded-t-[var(--radius-md)] lg:border lg:border-b-0">
      <aside className="hidden w-60 shrink-0 flex-col border-r border-[var(--border-subtle)] bg-[var(--bg-overlay)] lg:flex"><div className="flex h-14 items-center px-4 text-xs font-semibold uppercase tracking-wide text-[var(--text-muted)]">Brief outline</div>{briefSections.map((section, index) => <button key={section.title} className={cn('border-l-2 px-4 py-3 text-left hover:bg-[var(--surface-hover)]', index === 0 ? 'border-[var(--accent)] bg-[var(--surface)]' : 'border-transparent')}><span className="block text-sm font-medium">{section.title}</span><span className="mt-1 flex items-center gap-2 text-[10px] text-[var(--text-muted)]">{section.sources} sources {section.state === 'Review' && <Badge variant="warning" className="min-h-5 px-1.5 py-0 text-[10px]">Review</Badge>}</span></button>)}</aside>
      <section className="flex min-w-0 flex-1 flex-col">
        <div className="flex min-h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-3 lg:px-5"><Button variant="outline" size="sm" className="lg:hidden" onClick={() => setOutlineOpen(!outlineOpen)}><BookOpen className="size-4" />Outline</Button><div className="hidden items-center gap-2 text-xs text-[var(--text-muted)] sm:flex"><Clock3 className="size-4" />Updated 2 hours ago<span>·</span><Link2 className="size-4" />6 sources</div><Badge variant="warning" className="ml-auto"><Sparkles className="size-3.5" />1 change to review</Badge><Button variant="outline" size="sm">Edit section</Button></div>
        {outlineOpen && <div className="absolute inset-x-3 top-16 z-20 rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-2 shadow-lg lg:hidden">{briefSections.map((section) => <button key={section.title} onClick={() => setOutlineOpen(false)} className="flex min-h-11 w-full items-center rounded-[var(--radius-sm)] px-3 text-left text-sm hover:bg-[var(--surface-hover)]">{section.title}<ChevronRight className="ml-auto size-4" /></button>)}</div>}
        <div className="min-h-0 flex-1 overflow-y-auto"><article className="mx-auto max-w-3xl px-5 py-7 lg:px-10 lg:py-9"><div className="flex items-start gap-3"><div><div className="text-xs font-semibold uppercase tracking-[0.12em] text-[var(--text-muted)]">Current posture</div><h2 className="mt-1 text-2xl font-semibold tracking-tight">The demand is substantially reduced; a residual appeal remains active.</h2></div><Badge variant="success" className="ml-auto hidden sm:inline-flex">Current</Badge></div><p className="mt-5 text-[15px] leading-7 text-[var(--text-secondary)]">The Order-in-Original reduced the disputed input tax credit demand from <strong className="text-[var(--text-primary)]">₹14,20,000 to ₹50,000</strong> after accepting the principal reconciliation.<button onClick={() => setSourceOpen(true)} className="ml-1 inline-flex size-5 items-center justify-center rounded-full bg-[var(--accent-muted)] align-super text-[10px] font-semibold text-[var(--accent)]">1</button> The taxpayer has appealed the residual finding and deposited ₹5,000 as pre-deposit.<button onClick={() => setSourceOpen(true)} className="ml-1 inline-flex size-5 items-center justify-center rounded-full bg-[var(--accent-muted)] align-super text-[10px] font-semibold text-[var(--accent)]">2</button></p><div className="mt-6 grid gap-3 sm:grid-cols-3"><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs text-[var(--text-muted)]">Current exposure</div><div className="mt-1 font-semibold">₹50,000</div></div><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs text-[var(--text-muted)]">Next milestone</div><div className="mt-1 font-semibold">Appeal hearing</div></div><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs text-[var(--text-muted)]">Open questions</div><div className="mt-1 font-semibold">2 unresolved</div></div></div><hr className="my-8 border-[var(--border-subtle)]" /><div className="flex items-center gap-2"><h3 className="text-lg font-semibold">What matters now</h3><span className="text-xs text-[var(--text-muted)]">Refreshed today</span></div><ul className="mt-4 space-y-3 text-[15px] leading-6 text-[var(--text-secondary)]"><li className="flex gap-3"><span className="mt-2 size-1.5 shrink-0 rounded-full bg-[var(--accent)]" />Establish that all residual invoices form part of the reconciliation already accepted in principle.</li><li className="flex gap-3"><span className="mt-2 size-1.5 shrink-0 rounded-full bg-[var(--accent)]" /><span>The limitation argument remains available, but the supporting authority needs validation.<button onClick={() => setSourceOpen(true)} className="ml-1 inline-flex size-5 items-center justify-center rounded-full bg-[var(--accent-muted)] align-super text-[10px] font-semibold text-[var(--accent)]">3</button></span></li></ul><div className="mt-7 rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-4"><div className="flex items-center gap-2 text-sm font-semibold text-[var(--warning)]"><Sparkles className="size-4" />Suggested update requires review</div><p className="mt-2 text-sm leading-6">A newly processed appeal acknowledgement may change the recorded filing date. The current human-edited sentence has not been overwritten.</p><Button variant="outline" size="sm" className="mt-3">Review proposed change</Button></div><p className="mt-7 rounded-[var(--radius-sm)] border-l-2 border-[var(--accent)] bg-[var(--accent-muted)] px-4 py-3 text-sm leading-6"><span className="font-semibold">Human context:</span> <span className="decoration-[var(--accent)] decoration-dotted underline underline-offset-4" title="Edited by Ananya Kapoor · 3 hours ago">The client has confirmed that the missing invoice set is available in physical form.</span></p></article></div>
      </section>
      {sourceOpen && <SourcePanel evidence={defaultEvidence} onClose={() => setSourceOpen(false)} />}
    </div>
  )
}

function MobileNav({ view, onChange }: { view: WorkspaceView; onChange: (view: WorkspaceView) => void }) {
  return <nav className="grid h-16 shrink-0 grid-cols-4 border-t border-[var(--border-subtle)] bg-[var(--surface)] lg:hidden"><button className="flex flex-col items-center justify-center gap-1 text-xs text-[var(--text-muted)]"><Activity className="size-5" />Timeline</button><button onClick={() => onChange('brief')} className={cn('flex flex-col items-center justify-center gap-1 text-xs', view === 'brief' ? 'text-[var(--accent)]' : 'text-[var(--text-muted)]')}><BookOpen className="size-5" />Case Brief</button><button onClick={() => onChange('notes')} className={cn('flex flex-col items-center justify-center gap-1 text-xs', view === 'notes' ? 'text-[var(--accent)]' : 'text-[var(--text-muted)]')}><MessageSquare className="size-5" />Notes</button><button className="flex flex-col items-center justify-center gap-1 text-xs text-[var(--text-muted)]"><MoreHorizontal className="size-5" />More</button></nav>
}

export function NotesCaseBriefConcept() {
  const [view, setView] = useState<WorkspaceView>('notes')
  return (
    <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]"><AppRail /><main className="flex min-w-0 flex-1 flex-col overflow-hidden"><MatterHeader /><div className="relative flex min-h-0 flex-1 flex-col px-0 lg:px-3"><SectionNav view={view} onChange={setView} />{view === 'notes' ? <NotesWorkspace /> : <CaseBriefWorkspace />}</div><MobileNav view={view} onChange={setView} /></main></div>
  )
}
