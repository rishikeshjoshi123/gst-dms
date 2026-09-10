'use client'

import { useMemo, useState } from 'react'
import {
  AlertCircle,
  ArrowLeft,
  CalendarClock,
  Check,
  ChevronRight,
  ClipboardCheck,
  Gavel,
  Inbox,
  ListFilter,
  LockKeyhole,
  Moon,
  RefreshCw,
  Search,
  ShieldAlert,
  Sun,
  UserPlus,
  Users,
  X,
} from 'lucide-react'

import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { cn } from '@/lib/utils'

type FixtureMode = 'owner' | 'member' | 'safeguard' | 'loading' | 'empty' | 'error'
type Workspace = 'team' | 'leave-organisation' | 'my-departure'
type TeamView = 'members' | 'departures'
type MemberId = 'ananya' | 'rishikesh' | 'devika' | 'harshvardhan' | 'nisha'

type Member = {
  id: MemberId
  name: string
  email: string
  title: string
  role: 'Admin' | 'Associate' | 'Viewer'
  owner?: boolean
  status: 'Active' | 'Serving notice'
  joined: string
  responsibility: string
}

const members: Member[] = [
  {
    id: 'ananya',
    name: 'Ananya Kapoor',
    email: 'ananya@apextax.in',
    title: 'Senior associate · Indirect tax disputes',
    role: 'Associate',
    status: 'Serving notice',
    joined: '21 Jun 2026',
    responsibility: '9 items need disposition',
  },
  {
    id: 'rishikesh',
    name: 'Rishikesh Joshi',
    email: 'rishikesh@apextax.in',
    title: 'Founding partner',
    role: 'Admin',
    owner: true,
    status: 'Active',
    joined: '18 Jun 2026',
    responsibility: 'Owner · privileged coverage required',
  },
  {
    id: 'devika',
    name: 'Devika Rao',
    email: 'devika@apextax.in',
    title: 'Operations partner',
    role: 'Admin',
    status: 'Active',
    joined: '19 Jun 2026',
    responsibility: 'Eligible reassignment recipient',
  },
  {
    id: 'harshvardhan',
    name: 'Harshvardhan Subramanian Venkataraman',
    email: 'harshvardhan.subramanian.venkataraman@apextax.in',
    title: 'Associate · Appellate records and complex classification matters',
    role: 'Associate',
    status: 'Active',
    joined: '02 Jul 2026',
    responsibility: 'Long-content fixture · no open disposition',
  },
  {
    id: 'nisha',
    name: 'Nisha Patel',
    email: 'nisha@apextax.in',
    title: 'Client reviewer',
    role: 'Viewer',
    status: 'Active',
    joined: '19 Jul 2026',
    responsibility: 'No accountable work',
  },
]

const impact = [
  { label: 'Open tasks', value: '3', detail: 'Give them to someone else, or leave them unassigned for the team', icon: ClipboardCheck },
  { label: 'Important dates', value: '2', detail: 'Choose another person to receive reminders and follow up', icon: CalendarClock },
  { label: 'Access permissions', value: '1', detail: 'Matter-specific access ends with organisation membership', icon: LockKeyhole },
  { label: 'Organisation administration', value: 'Safe', detail: 'The Owner and another eligible Admin remain', icon: ShieldAlert },
]

const departureWork = [
  { label: 'Open tasks', value: '3', detail: 'Another teammate needs to take over these tasks.' },
  { label: 'Important dates', value: '2', detail: 'Another teammate needs to receive the reminders and follow up.' },
]

const fixtureOptions: Array<{ value: FixtureMode; label: string }> = [
  { value: 'owner', label: 'Owner · ready' },
  { value: 'member', label: 'Ordinary member · privacy' },
  { value: 'safeguard', label: 'Current Owner · safeguard' },
  { value: 'loading', label: 'Loading' },
  { value: 'empty', label: 'Empty result' },
  { value: 'error', label: 'Unavailable / error' },
]

const compactTableRowClass = 'h-12 cursor-pointer outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]'
const compactTableCellClass = 'py-1.5'

function AppRail() {
  return (
    <aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-2 text-[var(--sidebar-text)] md:flex" aria-label="Concept navigation">
      <div className="flex size-10 items-center justify-center text-[var(--sidebar-accent)]"><Gavel className="size-5" /></div>
      <button type="button" aria-label="Today" className="mt-5 flex size-11 items-center justify-center rounded-[var(--radius-sm)] hover:bg-[var(--sidebar-hover)]"><Inbox className="size-5" /></button>
      <button type="button" aria-label="Team" className="mt-1 flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Users className="size-5" /></button>
      <div className="mt-auto flex size-10 items-center justify-center rounded-full border border-[var(--sidebar-border,var(--border))] text-xs font-semibold">RJ</div>
    </aside>
  )
}

function WorkspaceHeader({ workspace, workspaces, mode, dark, detailActive, onWorkspace, onMode, onDark }: { workspace: Workspace; workspaces: Array<{ value: Workspace; label: string }>; mode: FixtureMode; dark: boolean; detailActive: boolean; onWorkspace: (workspace: Workspace) => void; onMode: (mode: FixtureMode) => void; onDark: () => void }) {
  const title = workspace === 'team' ? 'Team' : workspace === 'leave-organisation' ? 'Leave organisation' : 'My departure'
  return (
    <header className={cn('flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 md:px-5', detailActive && 'max-xl:hidden')}>
      <div className="hidden size-11 items-center justify-center rounded-[var(--radius-sm)] text-[var(--text-muted)] sm:flex md:hidden" aria-hidden="true"><Users className="size-5" /></div>
      <div className="min-w-0 flex-1">
        <h1 className="truncate text-base font-semibold lg:text-lg">{title}</h1>
        <p className="hidden truncate text-xs text-[var(--text-muted)] sm:block">Apex Tax Advocates · Organisation workspace</p>
      </div>
      <select aria-label="Concept surface" value={workspace} onChange={(event) => onWorkspace(event.target.value as Workspace)} className="min-h-9 max-w-28 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-xs outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] sm:max-w-none">{workspaces.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}</select>
      <Badge variant="warning" className="hidden shrink-0 lg:inline-flex">Fixture only</Badge>
      <select aria-label="Preview state" value={mode} onChange={(event) => onMode(event.target.value as FixtureMode)} className="hidden min-h-9 max-w-40 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-xs outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] sm:block">{fixtureOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select>
      <Button variant="ghost" size="icon" className="hidden sm:inline-flex" onClick={onDark} aria-label={dark ? 'Use light appearance' : 'Use dark appearance'} aria-pressed={dark}>{dark ? <Sun className="size-4" /> : <Moon className="size-4" />}</Button>
    </header>
  )
}

function SegmentedControl<T extends string>({ value, label, items, onChange }: { value: T; label: string; items: Array<{ value: T; label: string; count?: number }>; onChange: (value: T) => void }) {
  return (
    <div role="tablist" aria-label={label} className="flex min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-0.5">
      {items.map((item) => (
        <button
          key={item.value}
          type="button"
          role="tab"
          aria-selected={value === item.value}
          onClick={() => onChange(item.value)}
          className={cn(
            'flex min-h-11 min-w-0 items-center justify-center gap-1.5 rounded-[calc(var(--radius-sm)-2px)] px-3 text-xs font-medium lg:min-h-9',
            value === item.value ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-[var(--shadow-xs)]' : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)]',
          )}
        >
          <span className="truncate">{item.label}</span>
          {item.count !== undefined && <span className="font-mono text-[10px]">{item.count}</span>}
        </button>
      ))}
    </div>
  )
}

function TeamWorkbar({ ordinary, view, onView }: { ordinary: boolean; view: TeamView; onView: (view: TeamView) => void }) {
  return (
    <div className="flex min-h-14 shrink-0 flex-wrap items-center gap-2 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 xl:h-14 xl:flex-nowrap xl:px-4 xl:py-0">
      <SegmentedControl value={view} onChange={onView} label="Team views" items={ordinary ? [{ value: 'members', label: 'Members', count: 5 }] : [{ value: 'members', label: 'Members', count: 5 }, { value: 'departures', label: 'Departure queue', count: 2 }]} />
      <label className="relative min-w-48 flex-1 xl:max-w-md"><span className="sr-only">Search team members</span><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input placeholder={view === 'members' ? 'Search people or authorised email' : 'Search departure cases'} className="pl-9" /></label>
      <Button variant="outline" size="sm"><ListFilter className="size-4" />Filters</Button>
      {!ordinary && <Button size="sm" className="ml-auto"><UserPlus className="size-4" />Invite member</Button>}
    </div>
  )
}

function StatePanel({ mode, onRetry }: { mode: 'loading' | 'empty' | 'error'; onRetry: () => void }) {
  if (mode === 'loading') {
    return (
      <div role="status" aria-label="Loading team members" className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
        <p className="sr-only">Loading team members</p>
        {[0, 1, 2, 3].map((item) => <div key={item} className="flex min-h-16 items-center gap-3 border-b border-[var(--border-subtle)] px-4 last:border-b-0"><Skeleton className="size-9 rounded-full" /><div className="min-w-0 flex-1 space-y-2"><Skeleton className="h-3 w-48 max-w-full" /><Skeleton className="h-2.5 w-64 max-w-[80%]" /></div><Skeleton className="h-6 w-20" /></div>)}
      </div>
    )
  }

  if (mode === 'error') {
    return (
      <div role="alert" className="mx-auto max-w-lg rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--surface)] p-5 text-center">
        <AlertCircle className="mx-auto size-6 text-[var(--danger)]" />
        <h2 className="mt-3 text-sm font-semibold">Team details are unavailable</h2>
        <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The fixture projection could not be displayed. No membership state changed.</p>
        <Button variant="outline" size="sm" className="mt-4" onClick={onRetry}><RefreshCw className="size-4" />Retry preview</Button>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-lg rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-6 text-center">
      <Search className="mx-auto size-6 text-[var(--text-muted)]" />
      <h2 className="mt-3 text-sm font-semibold">No members match this fixture</h2>
      <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Clear the imagined search and role filters to return to the full directory.</p>
      <Button variant="outline" size="sm" className="mt-4" onClick={onRetry}>Clear preview filters</Button>
    </div>
  )
}

function MemberStatus({ member, hideDeparture = false }: { member: Member; hideDeparture?: boolean }) {
  const visibleStatus = hideDeparture && member.status === 'Serving notice' ? 'Active' : member.status
  return <Badge fixedWidth="xl" variant={visibleStatus === 'Serving notice' ? 'warning' : 'success'}>{visibleStatus}</Badge>
}

function MemberDirectory({ selectedId, ordinary, condensed, onSelect }: { selectedId: MemberId | null; ordinary: boolean; condensed: boolean; onSelect: (id: MemberId) => void }) {
  return (
    <div className="bg-[var(--surface)]">
      <Table className="hidden table-fixed md:table">
        <TableCaption>Team members. Select a row to open its details.</TableCaption>
        <colgroup>{condensed ? <><col className="w-[44%]" /><col className="w-[24%]" /><col className="w-[32%]" /></> : <><col className="w-[34%]" /><col className="w-[18%]" /><col className="w-[24%]" /><col className="w-[24%]" /></>}</colgroup>
        <TableHeader sticky>
          <TableRow><TableHead>Person</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead>{!condensed && <TableHead>Joined</TableHead>}</TableRow>
        </TableHeader>
        <TableBody>
          {members.map((member) => (
            <TableRow key={member.id} interactive selected={member.id === selectedId} tabIndex={0} aria-label={`View ${member.name}`} onClick={() => onSelect(member.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(member.id) } }} className={compactTableRowClass}>
              <TableCell className={compactTableCellClass}><div className="flex h-9 min-w-0 items-center gap-3"><Avatar name={member.name} size="sm" /><span className="flex min-w-0 items-center gap-2"><span className="truncate font-medium" title={member.name}>{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</span></div></TableCell>
              <TableCell className={compactTableCellClass}><Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge></TableCell>
              <TableCell className={compactTableCellClass}><MemberStatus member={member} hideDeparture={ordinary} /></TableCell>
              {!condensed && <TableCell className={cn(compactTableCellClass, 'whitespace-nowrap font-mono text-xs text-[var(--text-secondary)]')}>{member.joined}</TableCell>}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <div className="divide-y divide-[var(--border-subtle)] md:hidden">
        {members.map((member) => (
          <button key={member.id} type="button" onClick={() => onSelect(member.id)} className="flex min-h-20 w-full items-center gap-3 p-3 text-left hover:bg-[var(--surface-hover)]">
            <Avatar name={member.name} size="sm" />
            <span className="min-w-0 flex-1"><span className="flex min-w-0 items-center gap-2"><span className="truncate text-sm font-semibold">{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{member.title}</span><span className="mt-1.5 flex flex-wrap gap-1.5"><Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge><MemberStatus member={member} hideDeparture={ordinary} /></span></span>
            <ChevronRight className="size-4 shrink-0 text-[var(--text-muted)]" />
          </button>
        ))}
      </div>
    </div>
  )
}

function DepartureQueue({ selectedId, condensed, onSelect }: { selectedId: MemberId | null; condensed: boolean; onSelect: (id: MemberId) => void }) {
  const rows = [
    { id: 'devika' as const, name: 'Devika Rao', role: 'Admin', effective: '01 Oct 2026', remaining: '30 days', handover: 'Not started', work: '4 items', request: 'Decision required' },
    { id: 'ananya' as const, name: 'Ananya Kapoor', role: 'Associate', effective: '18 Sep 2026', remaining: '17 days', handover: 'In progress', work: '5 items', request: 'No request' },
  ]
  return (
    <div className="bg-[var(--surface)]">
      <Table className="hidden table-fixed md:table">
        <TableCaption>Planned departures. Select a row to open its details.</TableCaption>
        <colgroup>{condensed ? <><col className="w-[46%]" /><col className="w-[32%]" /><col className="w-[22%]" /></> : <><col className="w-[28%]" /><col className="w-[20%]" /><col className="w-[18%]" /><col className="w-[15%]" /><col className="w-[19%]" /></>}</colgroup>
        <TableHeader sticky>
          <TableRow><TableHead>Member</TableHead><TableHead>Last day</TableHead>{!condensed && <TableHead>Handover</TableHead>}<TableHead>Open work</TableHead>{!condensed && <TableHead>Earlier date</TableHead>}</TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow key={row.id} interactive selected={row.id === selectedId} tabIndex={0} aria-label={`Review departure for ${row.name}`} onClick={() => onSelect(row.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(row.id) } }} className={compactTableRowClass}>
              <TableCell className={compactTableCellClass}><div className="flex h-9 min-w-0 items-center gap-3"><Avatar name={row.name} size="sm" /><span className="min-w-0 truncate font-medium">{row.name}</span></div></TableCell>
              <TableCell className={cn(compactTableCellClass, 'whitespace-nowrap text-xs')}><span className="font-mono font-medium">{row.effective}</span><span className="text-[var(--text-muted)]"> · {row.remaining}</span></TableCell>
              {!condensed && <TableCell className={compactTableCellClass}><Badge fixedWidth="lg" variant={row.handover === 'In progress' ? 'warning' : 'muted'}>{row.handover}</Badge></TableCell>}
              <TableCell className={cn(compactTableCellClass, 'font-mono text-xs')}>{row.work}</TableCell>
              {!condensed && <TableCell className={compactTableCellClass}><Badge fixedWidth="xl" variant={row.request === 'No request' ? 'muted' : 'warning'}>{row.request}</Badge></TableCell>}
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <div className="divide-y divide-[var(--border-subtle)] md:hidden">
        {rows.map((row) => (
          <button key={row.id} type="button" onClick={() => onSelect(row.id)} className="flex min-h-24 w-full items-center gap-3 p-3 text-left hover:bg-[var(--surface-hover)]">
            <Avatar name={row.name} size="sm" />
            <span className="min-w-0 flex-1"><span className="block truncate text-sm font-semibold">{row.name}</span><span className="mt-1 block font-mono text-xs">{row.effective} · {row.remaining}</span><span className="mt-1 block truncate text-xs text-[var(--text-muted)]">{row.handover} · {row.work} outstanding</span></span>
            <span className="flex shrink-0 flex-col items-end gap-2"><Badge variant={row.request === 'No request' ? 'muted' : 'warning'}>{row.request}</Badge><ChevronRight className="size-4 text-[var(--text-muted)]" /></span>
          </button>
        ))}
      </div>
    </div>
  )
}

function ImpactGrid({ safeguard = false }: { safeguard?: boolean }) {
  return (
    <div className="overflow-hidden rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      {impact.map((item) => {
        const Icon = item.icon
        const privileged = item.label === 'Organisation administration'
        return <div key={item.label} className={cn('grid min-h-14 gap-1 border-b border-[var(--border-subtle)] px-3 py-2 last:border-b-0 sm:grid-cols-[minmax(10rem,0.7fr)_minmax(0,1fr)_auto] sm:items-center', safeguard && privileged && 'bg-[var(--danger-muted)]')}><div className="flex items-center gap-2"><Icon className={cn('size-4 shrink-0', safeguard && privileged ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]')} /><span className="text-xs font-medium text-[var(--text-secondary)]">{item.label}</span></div><p className="text-xs leading-5 text-[var(--text-muted)]">{safeguard && privileged ? 'Transfer ownership and keep another active Admin before this person leaves.' : item.detail}</p><span className="font-mono text-sm font-semibold">{safeguard && privileged ? 'Blocked' : item.value}</span></div>
      })}
    </div>
  )
}

function DepartureWorkList({ scheduled = false, embedded = false }: { scheduled?: boolean; embedded?: boolean }) {
  return (
    <div className={cn('overflow-hidden bg-[var(--surface)]', embedded ? 'border-t border-[var(--border-subtle)]' : 'rounded-[var(--radius-sm)] border border-[var(--border-subtle)]')}>
      {departureWork.map((item, index) => {
        return (
          <div key={item.label} className="grid gap-2 border-b border-[var(--border-subtle)] px-3 py-3 last:border-b-0 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
            <div className="min-w-0"><div className="flex items-baseline gap-2"><span className="font-mono text-sm font-semibold">{item.value}</span><span className="text-sm font-medium">{item.label}</span></div><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{item.detail}</p></div>
            <Badge fixedWidth="xl" variant="warning">{scheduled && index === 0 ? 'Being arranged' : 'Choose teammate'}</Badge>
          </div>
        )
      })}
    </div>
  )
}

function PrivacyPanel() {
  return (
    <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4">
      <div className="flex items-start gap-3"><LockKeyhole className="mt-0.5 size-5 shrink-0 text-[var(--accent)]" /><div><h3 className="text-sm font-semibold">Operational detail is private</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Ordinary members can use this collaboration identity. Another member’s departure notice, reason, dependency counts, handover, email, and access history are not included in this view.</p></div></div>
    </section>
  )
}

function MemberInspectorHeader({ member, onBack }: { member: Member; onBack: () => void }) {
  return (
    <div className="flex h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3">
      <Button variant="ghost" size="icon" onClick={onBack} aria-label="Back to team list" className="xl:hidden"><ArrowLeft className="size-5" /></Button>
      <Avatar name={member.name} size="sm" />
      <div className="min-w-0 flex-1"><div className="flex min-w-0 items-center gap-2"><h2 className="truncate text-sm font-semibold" title={member.name}>{member.name}</h2>{member.owner && <Badge variant="warning">Owner</Badge>}</div><p className="truncate text-xs text-[var(--text-muted)]" title={member.title}>{member.title}</p></div>
      <Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge>
      <Button variant="ghost" size="icon" onClick={onBack} aria-label="Close member details" className="hidden xl:inline-flex"><X className="size-4" /></Button>
    </div>
  )
}

function DepartureSummary() {
  return (
    <section className="border-l-2 border-[var(--warning)] pl-3">
      <div className="flex min-w-0 items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold">Leaving in 17 days</p>
          <p className="mt-1 font-mono text-xs text-[var(--text-secondary)]">18 Sep 2026 · 12:00 am IST</p>
        </div>
        <Badge variant="warning">Scheduled</Badge>
      </div>
      <p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">30-day notice · No earlier date requested</p>
    </section>
  )
}

function MemberDetails({ member, separated }: { member: Member; separated: boolean }) {
  return (
    <section className={cn(separated && 'border-t border-[var(--border-subtle)] pt-4')}>
      <h3 className="text-sm font-semibold">Member details</h3>
      <dl className="mt-3 grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-3 gap-y-2 text-xs">
        <dt className="text-[var(--text-muted)]">Work area</dt><dd className="min-w-0 truncate font-medium" title={member.title}>{member.title}</dd>
        <dt className="text-[var(--text-muted)]">Email</dt><dd className="min-w-0 truncate font-medium" title={member.email}>{member.email}</dd>
        <dt className="text-[var(--text-muted)]">Joined</dt><dd className="font-mono font-medium">{member.joined}</dd>
      </dl>
    </section>
  )
}

function MemberWorkSummary({ servingNotice }: { servingNotice: boolean }) {
  return (
    <section className="border-t border-[var(--border-subtle)] pt-4">
      <div className="flex min-w-0 items-end justify-between gap-3">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold">{servingNotice ? 'Work to pass on' : 'Current work'}</h3>
          <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">{servingNotice ? 'Choose who will take over these two areas.' : 'Work currently linked to this person.'}</p>
        </div>
        {servingNotice && <span className="shrink-0 font-mono text-xs text-[var(--warning)]">2 areas</span>}
      </div>
      <div className="mt-3 grid overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] sm:grid-cols-2">
        <div className="border-b border-[var(--border-subtle)] p-3 sm:border-b-0 sm:border-r">
          <div className="flex items-center gap-2 text-[var(--text-muted)]"><ClipboardCheck className="size-4" /><span className="text-xs">Open tasks</span></div>
          <div className="mt-2 flex items-baseline gap-2"><strong className="font-mono text-lg leading-none">3</strong><span className="text-xs font-medium">assigned</span></div>
          <p className="mt-2 text-xs text-[var(--text-muted)]">{servingNotice ? 'Choose a teammate' : 'Currently assigned'}</p>
        </div>
        <div className="p-3">
          <div className="flex items-center gap-2 text-[var(--text-muted)]"><CalendarClock className="size-4" /><span className="text-xs">Important dates</span></div>
          <div className="mt-2 flex items-baseline gap-2"><strong className="font-mono text-lg leading-none">2</strong><span className="text-xs font-medium">to follow up</span></div>
          <p className="mt-2 text-xs text-[var(--text-muted)]">{servingNotice ? 'Choose a teammate' : 'Receiving reminders'}</p>
        </div>
      </div>
    </section>
  )
}

function HandoverNote() {
  return (
    <section className="border-t border-[var(--border-subtle)] pt-4">
      <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Note for teammates</h3><span className="inline-flex items-center gap-1 text-xs text-[var(--success)]"><Check className="size-3.5" /> Shared</span></div>
      <p className="mt-2 border-l border-[var(--accent)] pl-3 text-xs leading-5 text-[var(--text-secondary)]">Preserve the linked evidence and contact the client before handing over the two important dates.</p>
    </section>
  )
}

function MemberAccessSummary({ member, safeguard }: { member: Member; safeguard: boolean }) {
  const servingNotice = member.status === 'Serving notice'
  const cells = [
    ['Current role', member.role],
    ['Shared intake', member.role === 'Viewer' ? 'Not granted' : 'Granted'],
    ['Matter access', member.id === 'ananya' ? (servingNotice ? '1 · ends' : '1 grant') : 'No grants'],
    [servingNotice ? 'Admin coverage' : 'Last changed', servingNotice ? (safeguard ? 'Action needed' : 'Safe') : '28 Aug 2026'],
  ]

  return (
    <section className="border-t border-[var(--border-subtle)] pt-4">
      <div className="flex items-baseline justify-between gap-3"><h3 className="text-sm font-semibold">{servingNotice ? 'Access on the last day' : 'Access'}</h3><span className="text-xs text-[var(--text-muted)]">Read-only</span></div>
      <dl className="mt-3 grid grid-cols-2 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] text-xs">
        {cells.map(([label, value], index) => (
          <div key={label} className={cn('min-w-0 p-3', index < 2 && 'border-b border-[var(--border-subtle)]', index % 2 === 0 && 'border-r border-[var(--border-subtle)]')}>
            <dt className="text-[var(--text-muted)]">{label}</dt>
            <dd className="mt-1 truncate font-medium" title={value}>{value}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-2 text-xs text-[var(--text-muted)]">Managed from Organisation access.</p>
    </section>
  )
}

function MemberInspector({ member, ordinary, safeguard, headerless = false, onBack, onReviewRemoval }: { member: Member; ordinary: boolean; safeguard: boolean; headerless?: boolean; onBack: () => void; onReviewRemoval: () => void }) {
  const servingNotice = member.status === 'Serving notice'

  return (
    <aside className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--surface)]" aria-label={`${member.name} details`}>
      {!headerless && <MemberInspectorHeader member={member} onBack={onBack} />}
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)] px-4 py-4" style={{ scrollbarGutter: 'stable' }}>
        <div className="space-y-4">
          {ordinary ? <PrivacyPanel /> : (
            <>
              {servingNotice && <DepartureSummary />}
              {safeguard && <section role="alert" className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><h3 className="text-sm font-semibold">Another administrator is required</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">This person is the current Owner and the last eligible Admin. Transfer ownership and keep another active Admin before removing them.</p></div></div></section>}
              <MemberDetails member={member} separated={servingNotice || safeguard} />
              <MemberWorkSummary servingNotice={servingNotice} />
              {servingNotice && <HandoverNote />}
              <MemberAccessSummary member={member} safeguard={safeguard} />
            </>
          )}
        </div>
      </div>
      {!ordinary && <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3">{member.status === 'Serving notice' ? <Button>Review departure case</Button> : <><Button variant="outline" disabled={safeguard}>Change role</Button><Button variant="destructive" onClick={onReviewRemoval}>{safeguard ? 'Review blocked removal' : 'Review administrative removal'}</Button></>}</div>}
    </aside>
  )
}

function AdministrativeRemovalWorkspace({ member, safeguard, onBack }: { member: Member; safeguard: boolean; onBack: () => void }) {
  const [acknowledged, setAcknowledged] = useState(false)
  const reassignee = member.id === 'devika' ? 'Rishikesh Joshi' : 'Devika Rao'
  const dispositions = [
    ['Open Tasks', '3', `Reassign to ${reassignee}`],
    ['Important dates', '2', `Reassign to ${reassignee}`],
  ]

  return (
    <section className="flex min-h-0 flex-1 flex-col overflow-hidden bg-[var(--bg)]" aria-label={`Administrative removal review for ${member.name}`}>
      <div className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 md:px-4">
        <Button variant="ghost" size="icon" onClick={onBack} aria-label="Back to member details"><ArrowLeft className="size-5" /></Button>
        <Avatar name={member.name} size="sm" />
        <div className="min-w-0 flex-1"><h2 className="truncate text-sm font-semibold">Administrative removal · {member.name}</h2><p className="truncate text-xs text-[var(--text-muted)]">Immediate access action · separate from planned departure</p></div>
        <Badge variant="danger" className="hidden sm:inline-flex">Immediate removal</Badge>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 md:p-4">
        <div className="mx-auto grid max-w-6xl gap-4 lg:grid-cols-[minmax(0,0.9fr)_minmax(28rem,1.1fr)]">
          <div className="space-y-4">
            <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4">
              <div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><p className="text-xs font-medium text-[var(--danger)]">Administrative action</p><h3 className="mt-1 text-base font-semibold">Review before removing access</h3><p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">This action does not create a 30- or 60-day notice. If confirmed in production, organisation access would be revoked after the current impact and authority checks pass.</p></div></div>
            </section>

            {safeguard && <section role="alert" className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><h3 className="text-sm font-semibold">Removal is blocked</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">{member.name} is the current Owner and last eligible Admin in this fixture. Transfer ownership and keep another active Admin before choosing where their work goes.</p></div></div></section>}

            <section>
              <div><h3 className="text-sm font-semibold">What this removal affects</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">The app checks this list again when an administrator confirms the removal.</p></div>
              <div className="mt-3"><ImpactGrid safeguard={safeguard} /></div>
            </section>
          </div>

          <div className="space-y-4">
            <section className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
              <div className="border-b border-[var(--border-subtle)] px-4 py-3"><h3 className="text-sm font-semibold">Choose where the work goes</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Every accountable item needs an explicit destination. Nothing is silently completed.</p></div>
              <div className="divide-y divide-[var(--border-subtle)]">
                {dispositions.map(([label, count, value]) => <label key={label} className="grid gap-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(14rem,0.9fr)] sm:items-center"><span><span className="block text-xs font-medium">{label}</span><span className="mt-0.5 block font-mono text-xs text-[var(--text-muted)]">{count} affected</span></span><select defaultValue={value} className="min-h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-xs outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" disabled={safeguard}><option>{value}</option><option>Return to permitted team queue</option><option>Block removal</option></select></label>)}
              </div>
            </section>

            <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><h3 className="text-sm font-semibold">What will happen</h3><ul className="mt-3 space-y-2 text-xs leading-5 text-[var(--text-secondary)]"><li className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-[var(--success)]" />The person immediately loses access to this organisation.</li><li className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-[var(--success)]" />Their name stays on past work, decisions, and activity.</li><li className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-[var(--success)]" />The app records who receives their open work.</li></ul></section>

            <label className="flex min-h-11 items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--surface)] p-3 text-xs leading-5"><input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} className="mt-0.5 size-4 accent-[var(--accent)]" disabled={safeguard} /><span>I reviewed the work destinations and understand that this is immediate administrative removal, not a departure notice.</span></label>
          </div>
        </div>
      </div>

      <div className="flex shrink-0 items-center justify-end gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><Button variant="outline" onClick={onBack} className="min-w-0 flex-1 sm:flex-none"><span className="sm:hidden">Back</span><span className="hidden sm:inline">Back to member</span></Button><Button variant="destructive" disabled className="min-w-0 flex-1 sm:flex-none"><span className="sm:hidden">{safeguard ? 'Blocked' : acknowledged ? 'Remove member' : 'Confirm review'}</span><span className="hidden sm:inline">{safeguard ? 'Removal blocked' : acknowledged ? 'Remove member — fixture disabled' : 'Review acknowledgement'}</span></Button></div>
    </section>
  )
}

function TeamWorkspace({ mode, onDetailChange }: { mode: FixtureMode; onDetailChange: (open: boolean) => void }) {
  const ordinary = mode === 'member'
  const safeguard = mode === 'safeguard'
  const [view, setView] = useState<TeamView>('members')
  const [selectedId, setSelectedId] = useState<MemberId | null>(null)
  const [mobileDetail, setMobileDetail] = useState(false)
  const [removalMemberId, setRemovalMemberId] = useState<MemberId | null>(null)

  const effectiveSelectedId = safeguard ? 'rishikesh' : selectedId
  const effectiveView: TeamView = ordinary ? 'members' : view
  const selected = members.find((member) => member.id === effectiveSelectedId) ?? null
  const removalMember = members.find((member) => member.id === removalMemberId) ?? null
  const stateMode = mode === 'loading' || mode === 'empty' || mode === 'error' ? mode : null
  const showMobileDetail = mobileDetail && !stateMode

  function selectMember(id: MemberId) {
    setSelectedId(id)
    setMobileDetail(true)
    onDetailChange(true)
  }

  function closeMember() {
    setMobileDetail(false)
    setSelectedId(null)
    onDetailChange(false)
  }

  if (removalMember) {
    return <AdministrativeRemovalWorkspace member={removalMember} safeguard={safeguard} onBack={() => { setRemovalMemberId(null); onDetailChange(true) }} />
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      {!selected && <TeamWorkbar ordinary={ordinary} view={effectiveView} onView={setView} />}
      {selected && <>
        <div className={cn('xl:hidden', showMobileDetail && 'hidden')}><TeamWorkbar ordinary={ordinary} view={effectiveView} onView={setView} /></div>
        <div className="hidden h-14 shrink-0 xl:flex">
          <div className="min-w-0 flex-1"><TeamWorkbar ordinary={ordinary} view={effectiveView} onView={setView} /></div>
          <div className="w-[40%] min-w-[430px] max-w-[580px] shrink-0 border-l border-[var(--border)]"><MemberInspectorHeader member={selected} onBack={closeMember} /></div>
        </div>
      </>}
      <div className="flex min-h-0 flex-1 overflow-hidden">
        <section className={cn('custom-scrollbar h-full min-w-0 flex-1 overflow-y-auto overscroll-contain bg-[var(--surface)] xl:pl-3', showMobileDetail && 'hidden xl:block')} style={{ scrollbarGutter: 'stable' }} aria-label={effectiveView === 'members' ? 'Team members' : 'Departure queue'}>
          {stateMode ? <div className="p-3"><StatePanel mode={stateMode} onRetry={() => undefined} /></div> : effectiveView === 'members' ? <MemberDirectory selectedId={effectiveSelectedId} ordinary={ordinary} condensed={Boolean(selected)} onSelect={selectMember} /> : <DepartureQueue selectedId={effectiveSelectedId} condensed={Boolean(selected)} onSelect={selectMember} />}
        </section>
        {!stateMode && selected && <>
          <div className={cn('flex h-full min-h-0 min-w-0 w-full overflow-hidden bg-[var(--surface)] xl:hidden', !showMobileDetail && 'hidden')}><MemberInspector member={selected} ordinary={ordinary} safeguard={safeguard} onReviewRemoval={() => { setRemovalMemberId(selected.id); onDetailChange(false) }} onBack={closeMember} /></div>
          <div className="hidden h-full min-h-0 min-w-0 w-[40%] min-w-[430px] max-w-[580px] shrink-0 overflow-hidden border-l border-[var(--border)] bg-[var(--surface)] xl:flex"><MemberInspector member={selected} ordinary={ordinary} safeguard={safeguard} headerless onReviewRemoval={() => { setRemovalMemberId(selected.id); onDetailChange(false) }} onBack={closeMember} /></div>
        </>}
      </div>
    </div>
  )
}

function EarlyReleaseDialog({ open, onOpenChange, onPreview }: { open: boolean; onOpenChange: (open: boolean) => void; onPreview: (message: string) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Request an earlier departure</DialogTitle><DialogDescription>Choose a date before 18 Sep 2026. An organisation administrator must approve it; until then, your current departure date stays unchanged.</DialogDescription></DialogHeader>
        <div className="space-y-4"><div><Label htmlFor="release-date">Preferred departure date</Label><Input id="release-date" type="date" defaultValue="2026-09-12" min="2026-09-02" max="2026-09-17" /></div><div><Label htmlFor="release-reason">Optional note</Label><textarea id="release-reason" rows={3} defaultValue="My work handover can be completed before the current departure date." className="w-full resize-y rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" /></div><p className="text-xs leading-5 text-[var(--text-muted)]">You can have one request waiting for a decision at a time. If it is declined, 18 Sep 2026 remains your departure date.</p></div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button onClick={() => { onOpenChange(false); onPreview('Fixture only: the early-release request was not submitted.') }}>Preview request</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function WithdrawDialog({ open, onOpenChange, onPreview }: { open: boolean; onOpenChange: (open: boolean) => void; onPreview: (message: string) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Withdraw departure notice?</DialogTitle><DialogDescription>This cancels your planned departure and any request for an earlier date.</DialogDescription></DialogHeader>
        <div className="rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5 text-[var(--text-secondary)]">Work already moved to another person stays with them. Your organisation administrators will be told that you cancelled the notice.</div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Keep notice</Button><Button variant="destructive" onClick={() => { onOpenChange(false); onPreview('Fixture only: the departure notice was not withdrawn.') }}>Preview withdrawal</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function LeaveOrganisationWorkspace({ safeguard }: { safeguard: boolean }) {
  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 md:p-4">
        <div className="mx-auto grid max-w-6xl gap-3 lg:grid-cols-[minmax(0,3fr)_minmax(22rem,2fr)] lg:items-start">
          <section className="self-stretch rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 lg:flex lg:flex-col lg:justify-center lg:p-5"><div className="flex flex-wrap items-center gap-2"><Badge variant="warning">Before you submit</Badge><span className="text-xs text-[var(--text-muted)]">30 days’ notice</span></div><h2 className="mt-2 text-xl font-semibold">Leave Apex Tax Advocates on 01 Oct 2026</h2><p className="mt-1 max-w-2xl text-xs leading-5 text-[var(--text-muted)]">Your account stays active until that date. Submitting this form gives the organisation time to pass your work to someone else.</p></section>

          <dl className="grid overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] sm:grid-cols-3 lg:grid-cols-1"><div className="border-b border-[var(--border-subtle)] px-4 py-3 sm:border-b-0 sm:border-r lg:border-b lg:border-r-0"><dt className="text-xs text-[var(--text-muted)]">Last day</dt><dd className="mt-1 font-mono text-sm font-semibold">01 Oct 2026</dd></div><div className="border-b border-[var(--border-subtle)] px-4 py-3 sm:border-b-0 sm:border-r lg:border-b lg:border-r-0"><dt className="text-xs text-[var(--text-muted)]">Access ends</dt><dd className="mt-1 text-sm font-medium">At or shortly after midnight IST</dd></div><div className="px-4 py-3"><dt className="text-xs text-[var(--text-muted)]">Until then</dt><dd className="mt-1 text-sm font-medium">You can keep working normally</dd></div></dl>

          {safeguard && <section role="alert" className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4 lg:col-span-2"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><h3 className="text-sm font-semibold">Transfer ownership first</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">You can prepare the notice, but the organisation cannot be left without an Owner. Transfer ownership to an active Admin before departure.</p></div></div></section>}

          <section className="min-w-0 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]"><div className="flex items-end justify-between gap-3 p-4"><div><h3 className="text-sm font-semibold">What needs a new person</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Submitting your notice does not finish this work.</p></div><span className="shrink-0 font-mono text-xs text-[var(--text-muted)]">5 items</span></div><DepartureWorkList embedded /></section>

          <section className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]"><div className="p-4"><h3 className="text-sm font-semibold">Note for your teammates <span className="font-normal text-[var(--text-muted)]">(optional)</span></h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Share useful context, such as where the latest draft is or who is waiting for a reply. The organisation will move the work separately.</p><Label htmlFor="new-departure-handover" className="sr-only">Note for your teammates</Label><textarea id="new-departure-handover" rows={3} placeholder="Add anything the next person should know…" className="mt-3 w-full resize-y rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm leading-6 outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" /></div><div className="border-t border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-4"><h3 className="text-sm font-semibold">What happens next</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">After you submit, this page shows the days remaining and the work still waiting for a new person. You can ask to leave earlier or cancel the notice before your departure is processed.</p></div></section>
        </div>
      </div>
      <div className="flex shrink-0 items-center justify-end gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><Button variant="outline" className="min-w-0 flex-1 sm:flex-none">Cancel</Button><Button disabled className="min-w-0 flex-1 sm:flex-none"><span className="sm:hidden">{safeguard ? 'Ownership required' : 'Submit notice'}</span><span className="hidden sm:inline">{safeguard ? 'Resolve ownership first' : 'Submit departure notice — fixture disabled'}</span></Button></div>
    </div>
  )
}

function MyDepartureWorkspace({ mode }: { mode: FixtureMode }) {
  const [earlyOpen, setEarlyOpen] = useState(false)
  const [withdrawOpen, setWithdrawOpen] = useState(false)
  const [message, setMessage] = useState('')

  if (mode === 'loading' || mode === 'empty' || mode === 'error') {
    return <div className="min-h-0 flex-1 overflow-y-auto p-3 lg:p-4"><StatePanel mode={mode} onRetry={() => undefined} /></div>
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 pb-24 md:pb-4 lg:p-4">
        <div className="mx-auto grid max-w-6xl gap-3 lg:grid-cols-[minmax(0,3fr)_minmax(22rem,2fr)] lg:items-start">
          {message && <div role="status" className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5 lg:col-span-2"><AlertCircle className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" />{message}</div>}

          <section className="self-stretch rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4 lg:flex lg:flex-col lg:justify-center lg:p-5"><div className="flex flex-wrap items-center gap-2"><Badge variant="warning">Departure scheduled</Badge><span className="text-xs text-[var(--text-muted)]">30 days’ notice</span></div><h2 className="mt-2 text-xl font-semibold">17 days until you leave</h2><p className="mt-1 font-mono text-sm">18 Sep 2026 · at or shortly after midnight IST</p><div className="mt-4 hidden flex-wrap gap-2 md:flex"><Button variant="outline" size="sm" onClick={() => setEarlyOpen(true)}>Request earlier date</Button><Button variant="destructive" size="sm" onClick={() => setWithdrawOpen(true)}>Withdraw notice</Button></div></section>

          <dl className="grid overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] sm:grid-cols-3 lg:grid-cols-1"><div className="border-b border-[var(--border-subtle)] px-4 py-3 sm:border-b-0 sm:border-r lg:border-b lg:border-r-0"><dt className="text-xs text-[var(--text-muted)]">Your account</dt><dd className="mt-1 text-sm font-medium">Active until your last day</dd></div><div className="border-b border-[var(--border-subtle)] px-4 py-3 sm:border-b-0 sm:border-r lg:border-b lg:border-r-0"><dt className="text-xs text-[var(--text-muted)]">Work to pass on</dt><dd className="mt-1 text-sm font-medium">5 items need a new person</dd></div><div className="px-4 py-3"><dt className="text-xs text-[var(--text-muted)]">Earlier date</dt><dd className="mt-1 text-sm font-medium">Not requested</dd></div></dl>

          <section className="min-w-0 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]"><div className="flex items-end justify-between gap-3 p-4"><div><h2 className="text-sm font-semibold">What still needs a new person</h2><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Your organisation administrator is arranging this. The work stays open until someone takes it over.</p></div><span className="shrink-0 font-mono text-xs text-[var(--text-muted)]">5 items</span></div><DepartureWorkList scheduled embedded /></section>

          <section className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]"><div className="p-4"><div className="flex flex-wrap items-center justify-between gap-2"><h2 className="text-sm font-semibold">Note for your teammates</h2><Badge variant="success">Shared</Badge></div><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">This gives the next person useful context. It does not move the work.</p><blockquote className="mt-3 border-l-2 border-[var(--accent)] pl-3 text-sm leading-6 text-[var(--text-secondary)]">Please preserve the linked evidence and contact the client before handing over the two important dates.</blockquote></div><div className="border-t border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-4"><h2 className="text-sm font-semibold">When you leave</h2><div className="mt-3 grid gap-3 text-xs leading-5 text-[var(--text-secondary)] sm:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2"><p><span className="block font-medium text-[var(--text-primary)]">Your access ends</span>You can no longer open this organisation or its Matters.</p><p><span className="block font-medium text-[var(--text-primary)]">Your name stays</span>Past work and decisions continue to show that you made them.</p></div></div></section>
        </div>
      </div>
      <div className="fixed inset-x-0 bottom-0 z-20 flex gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3 md:hidden"><Button variant="outline" className="flex-1" onClick={() => setEarlyOpen(true)}>Earlier date</Button><Button variant="destructive" className="flex-1" onClick={() => setWithdrawOpen(true)}>Withdraw notice</Button></div>
      <EarlyReleaseDialog open={earlyOpen} onOpenChange={setEarlyOpen} onPreview={setMessage} />
      <WithdrawDialog open={withdrawOpen} onOpenChange={setWithdrawOpen} onPreview={setMessage} />
    </div>
  )
}

export function OrganisationDepartureTeamConcept() {
  const [mode, setMode] = useState<FixtureMode>('owner')
  const [workspace, setWorkspace] = useState<Workspace>('team')
  const [dark, setDark] = useState(false)
  const [mobileInspectorOpen, setMobileInspectorOpen] = useState(false)

  const workspaceItems = useMemo<Array<{ value: Workspace; label: string }>>(() => [
    { value: 'team', label: 'Team' },
    { value: 'leave-organisation', label: 'Before leaving' },
    { value: 'my-departure', label: 'My departure' },
  ], [])

  return (
    <div className={cn('flex h-dvh flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]', dark && 'dark')}>
      <div className="flex min-h-0 flex-1 overflow-hidden">
        <AppRail />
        <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <WorkspaceHeader workspace={workspace} workspaces={workspaceItems} mode={mode} dark={dark} detailActive={workspace === 'team' && mobileInspectorOpen} onWorkspace={(next) => { setWorkspace(next); setMobileInspectorOpen(false) }} onMode={setMode} onDark={() => setDark(!dark)} />
          {workspace === 'team' ? <TeamWorkspace key={mode} mode={mode} onDetailChange={setMobileInspectorOpen} /> : workspace === 'leave-organisation' ? <LeaveOrganisationWorkspace safeguard={mode === 'safeguard'} /> : <MyDepartureWorkspace mode={mode} />}
        </main>
      </div>
    </div>
  )
}
