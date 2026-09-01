'use client'

import { useMemo, useState } from 'react'
import {
  AlertCircle,
  ArrowLeft,
  CalendarClock,
  Check,
  ChevronRight,
  ClipboardCheck,
  Clock3,
  FileCheck2,
  Gavel,
  Inbox,
  ListFilter,
  LockKeyhole,
  Menu,
  Moon,
  RefreshCw,
  Search,
  ShieldAlert,
  Sun,
  UserPlus,
  Users,
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
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { cn } from '@/lib/utils'

type FixtureMode = 'owner' | 'member' | 'safeguard' | 'loading' | 'empty' | 'error'
type Workspace = 'team' | 'my-departure'
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
  { label: 'Open Tasks', value: '3', detail: 'Reassign or return to the team queue', icon: ClipboardCheck },
  { label: 'Review assignments', value: '1', detail: 'Reassign or return to the Review queue', icon: FileCheck2 },
  { label: 'Verified deadlines', value: '2', detail: 'An accountable active member is required', icon: CalendarClock },
  { label: 'Matter responsibility', value: '2', detail: 'Choose an eligible active member', icon: Gavel },
  { label: 'Internal-cost grants', value: '1', detail: 'Revoked when membership access ends', icon: LockKeyhole },
  { label: 'Privileged coverage', value: 'Safe', detail: 'Owner and another eligible Admin remain', icon: ShieldAlert },
]

const fixtureOptions: Array<{ value: FixtureMode; label: string }> = [
  { value: 'owner', label: 'Owner/Admin · ready' },
  { value: 'member', label: 'Ordinary member · privacy' },
  { value: 'safeguard', label: 'Current Owner · safeguard' },
  { value: 'loading', label: 'Loading' },
  { value: 'empty', label: 'Empty result' },
  { value: 'error', label: 'Unavailable / error' },
]

function PreviewBanner({
  mode,
  onModeChange,
  dark,
  onDarkChange,
}: {
  mode: FixtureMode
  onModeChange: (mode: FixtureMode) => void
  dark: boolean
  onDarkChange: (dark: boolean) => void
}) {
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-[var(--warning)] bg-[var(--warning-muted)] px-3 py-2 lg:flex-nowrap lg:px-4">
      <Badge variant="warning" className="shrink-0">Local fixture preview</Badge>
      <p className="min-w-48 flex-1 text-xs leading-5 text-[var(--text-secondary)]">
        UI review only. No membership changes, commands, jobs, notifications, or scheduled departures run here.
      </p>
      <label className="flex min-h-11 min-w-0 flex-1 items-center gap-2 text-xs lg:max-w-xs">
        <span className="shrink-0 font-medium">Preview state</span>
        <select
          value={mode}
          onChange={(event) => onModeChange(event.target.value as FixtureMode)}
          className="min-h-11 min-w-0 flex-1 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-xs text-[var(--text-primary)] outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"
        >
          {fixtureOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
        </select>
      </label>
      <Button variant="outline" size="sm" onClick={() => onDarkChange(!dark)} aria-pressed={dark}>
        {dark ? <Sun className="size-4" /> : <Moon className="size-4" />}
        {dark ? 'Light preview' : 'Dark preview'}
      </Button>
    </div>
  )
}

function AppRail() {
  return (
    <aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-2 text-[var(--sidebar-text)] lg:flex" aria-label="Concept navigation">
      <div className="flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Gavel className="size-5" /></div>
      <button type="button" aria-label="Today" className="mt-5 flex size-11 items-center justify-center rounded-[var(--radius-sm)] hover:bg-[var(--sidebar-hover)]"><Inbox className="size-5" /></button>
      <button type="button" aria-label="Team" className="mt-1 flex size-11 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]"><Users className="size-5" /></button>
      <div className="mt-auto flex size-10 items-center justify-center rounded-full border border-[var(--sidebar-border,var(--border))] text-xs font-semibold">RJ</div>
    </aside>
  )
}

function WorkspaceHeader({ workspace }: { workspace: Workspace }) {
  return (
    <header className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 lg:min-h-12 lg:px-5">
      <button type="button" aria-label="Open navigation" className="flex size-11 items-center justify-center rounded-[var(--radius-sm)] lg:hidden"><Menu className="size-5" /></button>
      <div className="min-w-0">
        <h1 className="truncate text-base font-semibold lg:text-lg">{workspace === 'team' ? 'Team' : 'My departure'}</h1>
        <p className="truncate text-xs text-[var(--text-muted)]">Apex Tax Advocates · Organisation workspace</p>
      </div>
      <div className="ml-auto hidden items-center gap-2 text-xs text-[var(--text-muted)] sm:flex">
        <span>Fixture clock</span>
        <span className="font-mono text-[var(--text-primary)]">01 Sep 2026 · 09:00 IST</span>
      </div>
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

function MemberStatus({ member }: { member: Member }) {
  return <Badge fixedWidth="xl" variant={member.status === 'Serving notice' ? 'warning' : 'success'}>{member.status}</Badge>
}

function MemberDirectory({ selectedId, onSelect }: { selectedId: MemberId; onSelect: (id: MemberId) => void }) {
  return (
    <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <Table className="hidden md:table">
        <TableHeader sticky>
          <TableRow><TableHead>Person</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead><TableHead>Joined</TableHead><TableHead className="text-right">Action</TableHead></TableRow>
        </TableHeader>
        <TableBody>
          {members.map((member) => (
            <TableRow key={member.id} interactive selected={member.id === selectedId}>
              <TableCell><div className="flex min-w-0 items-center gap-3"><Avatar name={member.name} size="sm" /><div className="min-w-0"><div className="flex min-w-0 items-center gap-2"><span className="truncate font-medium" title={member.name}>{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</div><p className="max-w-[24rem] truncate text-xs text-[var(--text-muted)]" title={`${member.email} · ${member.title}`}>{member.email} · {member.title}</p></div></div></TableCell>
              <TableCell><Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge></TableCell>
              <TableCell><MemberStatus member={member} /></TableCell>
              <TableCell className="whitespace-nowrap font-mono text-xs text-[var(--text-secondary)]">{member.joined}</TableCell>
              <TableCell className="text-right"><Button variant="ghost" size="sm" onClick={() => onSelect(member.id)}>View member<ChevronRight className="size-4" /></Button></TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      <div className="divide-y divide-[var(--border-subtle)] md:hidden">
        {members.map((member) => (
          <button key={member.id} type="button" onClick={() => onSelect(member.id)} className="flex min-h-20 w-full items-center gap-3 p-3 text-left hover:bg-[var(--surface-hover)]">
            <Avatar name={member.name} size="sm" />
            <span className="min-w-0 flex-1"><span className="flex min-w-0 items-center gap-2"><span className="truncate text-sm font-semibold">{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</span><span className="mt-1 flex flex-wrap gap-1.5"><Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge><MemberStatus member={member} /></span></span>
            <ChevronRight className="size-4 shrink-0 text-[var(--text-muted)]" />
          </button>
        ))}
      </div>
    </div>
  )
}

function DepartureQueue({ onSelect }: { onSelect: (id: MemberId) => void }) {
  const rows = [
    { id: 'ananya' as const, name: 'Ananya Kapoor', effective: '18 Sep 2026', remaining: '17 days', handover: 'In progress', request: 'None' },
    { id: 'devika' as const, name: 'Devika Rao', effective: '01 Oct 2026', remaining: '30 days', handover: 'Not started', request: 'Early release pending' },
  ]
  return (
    <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <div className="border-b border-[var(--border-subtle)] px-4 py-3"><h2 className="text-sm font-semibold">Current departure cases</h2><p className="mt-0.5 text-xs text-[var(--text-muted)]">Private to callers with Owner/Admin departure access.</p></div>
      <div className="divide-y divide-[var(--border-subtle)]">
        {rows.map((row) => <button key={row.id} type="button" onClick={() => onSelect(row.id)} className="grid min-h-20 w-full gap-2 p-4 text-left hover:bg-[var(--surface-hover)] sm:grid-cols-[minmax(0,1fr)_auto_auto] sm:items-center"><span className="min-w-0"><span className="block truncate text-sm font-semibold">{row.name}</span><span className="mt-1 block text-xs text-[var(--text-muted)]">Handover · {row.handover}</span></span><span><span className="block font-mono text-xs font-medium">{row.effective}</span><span className="block text-xs text-[var(--text-muted)]">{row.remaining} remaining</span></span><span className="flex items-center justify-between gap-2 sm:justify-end"><Badge fixedWidth="xl" variant={row.request === 'None' ? 'muted' : 'warning'}>{row.request}</Badge><ChevronRight className="size-4 text-[var(--text-muted)]" /></span></button>)}
      </div>
    </div>
  )
}

function ImpactGrid({ safeguard = false }: { safeguard?: boolean }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {impact.map((item) => {
        const Icon = item.icon
        const privileged = item.label === 'Privileged coverage'
        return <div key={item.label} className={cn('rounded-[var(--radius-sm)] border p-3', safeguard && privileged ? 'border-[var(--danger)] bg-[var(--danger-muted)]' : 'border-[var(--border-subtle)] bg-[var(--surface)]')}><div className="flex items-center gap-2"><Icon className={cn('size-4', safeguard && privileged ? 'text-[var(--danger)]' : 'text-[var(--text-muted)]')} /><span className="text-xs font-medium text-[var(--text-secondary)]">{item.label}</span><span className="ml-auto font-mono text-sm font-semibold">{safeguard && privileged ? 'Blocked' : item.value}</span></div><p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">{safeguard && privileged ? 'Transfer ownership and retain an eligible Admin before execution.' : item.detail}</p></div>
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

function RemovalReviewDialog({ open, onOpenChange, member, safeguard }: { open: boolean; onOpenChange: (open: boolean) => void; member: Member; safeguard: boolean }) {
  const [acknowledged, setAcknowledged] = useState(false)
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[calc(100dvh-2rem)] overflow-y-auto sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>Review administrative removal</DialogTitle>
          <DialogDescription>Fixture confirmation for {member.name}. Nothing is submitted, scheduled, notified, or changed.</DialogDescription>
        </DialogHeader>
        {safeguard && <div role="alert" className="mb-4 flex gap-3 rounded-[var(--radius-sm)] border border-[var(--danger)] bg-[var(--danger-muted)] p-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><p className="text-sm font-semibold">Removal is blocked</p><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">This member is the current Owner and last eligible Admin in the safeguard fixture. Transfer ownership and restore privileged coverage first.</p></div></div>}
        <div className="space-y-4">
          <section><h3 className="text-sm font-semibold">Affected work</h3><p className="mt-1 text-xs text-[var(--text-muted)]">The command must recalculate this projection before accepting any confirmation.</p><div className="mt-3"><ImpactGrid safeguard={safeguard} /></div></section>
          <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)]">
            <div className="border-b border-[var(--border-subtle)] px-3 py-2.5"><h3 className="text-sm font-semibold">Required disposition</h3></div>
            <div className="divide-y divide-[var(--border-subtle)]">
              {[
                ['Open Tasks (3)', 'Reassign to Devika Rao'],
                ['Review assignment (1)', 'Return to Review queue'],
                ['Verified deadlines (2)', 'Reassign to Devika Rao'],
                ['Matter responsibility (2)', 'Reassign to Devika Rao'],
              ].map(([label, value]) => <label key={label} className="grid gap-2 px-3 py-3 sm:grid-cols-[minmax(0,1fr)_minmax(12rem,0.9fr)] sm:items-center"><span className="text-xs font-medium">{label}</span><select defaultValue={value} className="min-h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 text-xs outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" disabled={safeguard}><option>{value}</option><option>Return to permitted team queue</option><option>Block removal</option></select></label>)}
            </div>
          </section>
          <label className="flex min-h-11 items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3 text-xs leading-5"><input type="checkbox" checked={acknowledged} onChange={(event) => setAcknowledged(event.target.checked)} className="mt-0.5 size-4 accent-[var(--accent)]" disabled={safeguard} /><span>I confirm these explicit dispositions. Historical authorship remains; current access and incompatible grants would be revoked by the future governed command.</span></label>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel review</Button>
          <Button variant="destructive" disabled>Remove member — fixture disabled</Button>
        </DialogFooter>
        {!safeguard && acknowledged && <p className="mt-2 text-right text-xs text-[var(--warning)]">The final action is intentionally inert in this local preview.</p>}
      </DialogContent>
    </Dialog>
  )
}

function MemberInspector({ member, ordinary, safeguard, onBack }: { member: Member; ordinary: boolean; safeguard: boolean; onBack: () => void }) {
  const [reviewOpen, setReviewOpen] = useState(false)
  return (
    <aside className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-[var(--bg)] xl:max-w-[38rem] xl:border-l xl:border-[var(--border-subtle)]" aria-label={`${member.name} detail`}>
      <div className="flex shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-3">
        <Button variant="ghost" size="icon" onClick={onBack} aria-label="Back to team list" className="xl:hidden"><ArrowLeft className="size-5" /></Button>
        <Avatar name={member.name} size="md" />
        <div className="min-w-0 flex-1"><div className="flex min-w-0 items-center gap-2"><h2 className="truncate text-sm font-semibold" title={member.name}>{member.name}</h2>{member.owner && <Badge variant="warning">Owner</Badge>}</div><p className="truncate text-xs text-[var(--text-muted)]" title={member.title}>{member.title}</p></div>
        <Badge fixedWidth="md" variant={member.role === 'Admin' ? 'default' : 'outline'}>{member.role}</Badge>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 lg:p-4">
        <div className="space-y-3">
          {ordinary ? <PrivacyPanel /> : (
            <>
              {member.status === 'Serving notice' && <section className="rounded-[var(--radius-md)] border border-[var(--warning)] bg-[var(--warning-muted)] p-4"><div className="flex items-start gap-3"><Clock3 className="mt-0.5 size-5 shrink-0 text-[var(--warning)]" /><div><div className="flex flex-wrap items-center gap-2"><h3 className="text-sm font-semibold">Departure scheduled</h3><Badge variant="warning">17 days</Badge></div><p className="mt-1 font-mono text-xs">18 Sep 2026 · 12:00 am IST (UTC+05:30)</p><p className="mt-2 text-xs leading-5 text-[var(--text-secondary)]">30-day membership notice snapshot · Handover in progress · No early-release request pending.</p></div></div></section>}
              {safeguard && <section role="alert" className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-4"><div className="flex items-start gap-3"><ShieldAlert className="mt-0.5 size-5 shrink-0 text-[var(--danger)]" /><div><h3 className="text-sm font-semibold">Owner and last-Admin safeguard</h3><p className="mt-1 text-xs leading-5 text-[var(--text-secondary)]">This administrative removal cannot proceed. Transfer ownership to an eligible active Admin and retain privileged coverage first.</p></div></div></section>}
              <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><div className="flex items-end justify-between gap-3"><div><h3 className="text-sm font-semibold">Affected-member impact</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Fixture projection for explicit reassignment and access reconciliation.</p></div><span className="font-mono text-xs text-[var(--text-muted)]">Revision 14</span></div><div className="mt-3"><ImpactGrid safeguard={safeguard} /></div></section>
              <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><h3 className="text-sm font-semibold">Handover</h3><div className="mt-3 space-y-3 text-xs"><div className="flex items-center gap-3"><span className="flex size-7 items-center justify-center rounded-full bg-[var(--success-muted)] text-[var(--success)]"><Check className="size-4" /></span><span className="min-w-0 flex-1"><span className="block font-medium">Member handover note received</span><span className="text-[var(--text-muted)]">Operational summary supplied to administrators</span></span></div><div className="flex items-center gap-3"><span className="flex size-7 items-center justify-center rounded-full bg-[var(--warning-muted)] text-[var(--warning)]"><Clock3 className="size-4" /></span><span className="min-w-0 flex-1"><span className="block font-medium">Disposition confirmation required</span><span className="text-[var(--text-muted)]">Tasks, Review, deadlines, and Matter responsibility remain open</span></span></div></div></section>
            </>
          )}
        </div>
      </div>
      {!ordinary && <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3"><Button variant="outline" disabled={safeguard}>Change role</Button><Button variant="destructive" onClick={() => setReviewOpen(true)}>{safeguard ? 'Review blocked removal' : 'Review administrative removal'}</Button></div>}
      <RemovalReviewDialog open={reviewOpen} onOpenChange={setReviewOpen} member={member} safeguard={safeguard} />
    </aside>
  )
}

function TeamWorkspace({ mode }: { mode: FixtureMode }) {
  const ordinary = mode === 'member'
  const safeguard = mode === 'safeguard'
  const [view, setView] = useState<TeamView>('members')
  const [selectedId, setSelectedId] = useState<MemberId>(safeguard ? 'rishikesh' : ordinary ? 'devika' : 'ananya')
  const [mobileDetail, setMobileDetail] = useState(false)

  const effectiveSelectedId = safeguard ? 'rishikesh' : selectedId
  const effectiveView: TeamView = ordinary ? 'members' : view
  const selected = members.find((member) => member.id === effectiveSelectedId) ?? members[0]
  const stateMode = mode === 'loading' || mode === 'empty' || mode === 'error' ? mode : null
  const showMobileDetail = mobileDetail && !stateMode

  function selectMember(id: MemberId) {
    setSelectedId(id)
    setMobileDetail(true)
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className={cn('shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 lg:px-4', showMobileDetail && 'hidden xl:block')}>
        <div className="flex flex-wrap items-center gap-2 lg:flex-nowrap">
          <SegmentedControl value={effectiveView} onChange={setView} label="Team views" items={ordinary ? [{ value: 'members', label: 'Members', count: 5 }] : [{ value: 'members', label: 'Members', count: 5 }, { value: 'departures', label: 'Departure queue', count: 2 }]} />
          <label className="relative min-w-48 flex-1 lg:max-w-md"><span className="sr-only">Search team members</span><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input placeholder={effectiveView === 'members' ? 'Search people or authorised email' : 'Search departure cases'} className="pl-9" /></label>
          <Button variant="outline" size="sm"><ListFilter className="size-4" />Filters</Button>
          {!ordinary && <Button size="sm"><UserPlus className="size-4" />Invite member</Button>}
        </div>
        {ordinary && <p className="mt-2 text-xs text-[var(--text-muted)]">Departure queue and another member’s departure details are not available to ordinary members.</p>}
      </div>
      <div className="relative flex min-h-0 flex-1 overflow-hidden">
        <section className={cn('min-w-0 flex-1 overflow-y-auto overscroll-contain p-3 lg:p-4', showMobileDetail && 'hidden xl:block')} aria-label={effectiveView === 'members' ? 'Team members' : 'Departure queue'}>
          <div className="mx-auto max-w-6xl">
            {stateMode ? <StatePanel mode={stateMode} onRetry={() => undefined} /> : effectiveView === 'members' ? <MemberDirectory selectedId={effectiveSelectedId} onSelect={selectMember} /> : <DepartureQueue onSelect={selectMember} />}
          </div>
        </section>
        {!stateMode && (showMobileDetail || !ordinary) && <div className={cn('min-w-0 flex-1 xl:flex-none', !showMobileDetail && ordinary && 'hidden')}><MemberInspector member={selected} ordinary={ordinary} safeguard={safeguard} onBack={() => setMobileDetail(false)} /></div>}
      </div>
    </div>
  )
}

function EarlyReleaseDialog({ open, onOpenChange, onPreview }: { open: boolean; onOpenChange: (open: boolean) => void; onPreview: (message: string) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Request early release</DialogTitle><DialogDescription>This fixture accepts a date earlier than 18 Sep 2026 for Owner/Admin review. It does not submit a request.</DialogDescription></DialogHeader>
        <div className="space-y-4"><div><Label htmlFor="release-date">Desired effective date</Label><Input id="release-date" type="date" defaultValue="2026-09-12" min="2026-09-02" max="2026-09-17" /></div><div><Label htmlFor="release-reason">Optional reason</Label><textarea id="release-reason" rows={3} defaultValue="Handover can be completed before the original effective date." className="w-full resize-y rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" /></div><p className="text-xs leading-5 text-[var(--text-muted)]">At most one request may be pending, with three attempts per active departure case. A decline keeps the original date.</p></div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button onClick={() => { onOpenChange(false); onPreview('Fixture only: the early-release request was not submitted.') }}>Preview request</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function WithdrawDialog({ open, onOpenChange, onPreview }: { open: boolean; onOpenChange: (open: boolean) => void; onPreview: (message: string) => void }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader><DialogTitle>Withdraw departure notice?</DialogTitle><DialogDescription>The future command would cancel scheduled offboarding and any pending early-release request. Deliberate handover reassignments already made would not be reversed.</DialogDescription></DialogHeader>
        <div className="rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5 text-[var(--text-secondary)]">Withdrawal remains available only until offboarding execution begins. Owner/Admin receive a mandatory durable notification intent from the governed command.</div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Keep notice</Button><Button variant="destructive" onClick={() => { onOpenChange(false); onPreview('Fixture only: the departure notice was not withdrawn.') }}>Preview withdrawal</Button></DialogFooter>
      </DialogContent>
    </Dialog>
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
      <div className="hidden shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-4 py-2 md:flex">
        <div className="min-w-0 flex-1"><p className="text-sm font-semibold">Departure notice · Ananya Kapoor</p><p className="text-xs text-[var(--text-muted)]">Access remains active until governed offboarding executes.</p></div>
        <Button variant="outline" size="sm" onClick={() => setEarlyOpen(true)}>Request early release</Button>
        <Button variant="destructive" size="sm" onClick={() => setWithdrawOpen(true)}>Withdraw notice</Button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain p-3 pb-24 md:pb-4 lg:p-4">
        <div className="mx-auto max-w-5xl space-y-3">
          {message && <div role="status" className="flex items-start gap-2 rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5"><AlertCircle className="mt-0.5 size-4 shrink-0 text-[var(--warning)]" />{message}</div>}
          <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
            <div className="grid gap-4 border-b border-[var(--border-subtle)] p-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
              <div><Badge variant="warning">Scheduled departure</Badge><h2 className="mt-3 text-xl font-semibold">17 whole days remaining</h2><p className="mt-1 font-mono text-sm">18 Sep 2026 · 12:00 am IST (UTC+05:30)</p><p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">Calculated at the fixture time 01 Sep 2026, 09:00 IST from the accepted 30-day membership notice snapshot.</p></div>
              <div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] px-4 py-3"><span className="block text-xs text-[var(--text-muted)]">Handover</span><span className="mt-1 flex items-center gap-2 text-sm font-semibold"><Clock3 className="size-4 text-[var(--warning)]" />In progress</span></div>
            </div>
            <div className="grid gap-3 p-4 sm:grid-cols-3"><div><span className="text-xs text-[var(--text-muted)]">Original effective date</span><span className="mt-1 block font-mono text-sm">18 Sep 2026</span></div><div><span className="text-xs text-[var(--text-muted)]">Early release</span><span className="mt-1 block text-sm">No request pending</span></div><div><span className="text-xs text-[var(--text-muted)]">Access state</span><span className="mt-1 block text-sm">Active until execution</span></div></div>
          </section>
          <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><h2 className="text-sm font-semibold">Your affected work</h2><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">You can see your own impact. Owner/Admin coordinate required dispositions; no item is silently completed.</p><div className="mt-3"><ImpactGrid /></div></section>
          <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 className="text-sm font-semibold">Handover plan</h2><p className="mt-1 text-xs text-[var(--text-muted)]">This note is fixture content and is not saved.</p></div><Badge variant="warning">2 dispositions pending</Badge></div><div className="mt-4 space-y-3"><div className="flex items-start gap-3"><span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-[var(--success-muted)] text-[var(--success)]"><Check className="size-4" /></span><div><p className="text-sm font-medium">Handover note supplied</p><p className="text-xs leading-5 text-[var(--text-muted)]">Open evidence locations and procedural context are listed for the receiving team.</p></div></div><div className="flex items-start gap-3"><span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-[var(--warning-muted)] text-[var(--warning)]"><Clock3 className="size-4" /></span><div><p className="text-sm font-medium">Administrator disposition in progress</p><p className="text-xs leading-5 text-[var(--text-muted)]">Verified deadlines and Matter responsibility still require an eligible active member.</p></div></div></div><Label htmlFor="handover-note" className="mt-5">Handover note</Label><textarea id="handover-note" rows={4} defaultValue="Please preserve the linked evidence and reassign the two accountable deadlines before the effective date." className="w-full resize-y rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-3 py-2 text-sm leading-6 outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]" /></section>
          <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] p-4"><h2 className="text-sm font-semibold">What happens at offboarding</h2><p className="mt-2 text-xs leading-5 text-[var(--text-muted)]">Organisation access, authenticated loaders and actions, new signed asset issuance, realtime eligibility, personal delivery schedules, and incompatible Matter grants are revoked. Historical authorship and the portable account profile remain. The product promises execution at or shortly after the midnight-IST boundary, not at an exact second.</p></section>
        </div>
      </div>
      <div className="fixed inset-x-0 bottom-0 z-20 flex gap-2 border-t border-[var(--border-subtle)] bg-[var(--surface)] p-3 md:hidden"><Button variant="outline" className="flex-1" onClick={() => setEarlyOpen(true)}>Request early release</Button><Button variant="destructive" className="flex-1" onClick={() => setWithdrawOpen(true)}>Withdraw notice</Button></div>
      <EarlyReleaseDialog open={earlyOpen} onOpenChange={setEarlyOpen} onPreview={setMessage} />
      <WithdrawDialog open={withdrawOpen} onOpenChange={setWithdrawOpen} onPreview={setMessage} />
    </div>
  )
}

export function OrganisationDepartureTeamConcept() {
  const [mode, setMode] = useState<FixtureMode>('owner')
  const [workspace, setWorkspace] = useState<Workspace>('team')
  const [dark, setDark] = useState(false)

  const workspaceItems = useMemo<Array<{ value: Workspace; label: string }>>(() => [
    { value: 'team', label: 'Team workspace' },
    { value: 'my-departure', label: 'My departure' },
  ], [])

  return (
    <div className={cn('flex h-dvh flex-col overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]', dark && 'dark')}>
      <PreviewBanner mode={mode} onModeChange={setMode} dark={dark} onDarkChange={setDark} />
      <div className="flex min-h-0 flex-1 overflow-hidden">
        <AppRail />
        <main className="flex min-w-0 flex-1 flex-col overflow-hidden">
          <WorkspaceHeader workspace={workspace} />
          <div className="shrink-0 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-2 lg:px-4">
            <SegmentedControl value={workspace} onChange={setWorkspace} label="Concept surfaces" items={workspaceItems} />
          </div>
          {workspace === 'team' ? <TeamWorkspace mode={mode} /> : <MyDepartureWorkspace mode={mode} />}
        </main>
      </div>
    </div>
  )
}
