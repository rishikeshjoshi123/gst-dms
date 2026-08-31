'use client'

import { useState } from 'react'
import {
  Activity,
  ArchiveRestore,
  Bell,
  Check,
  ChevronDown,
  ChevronRight,
  Database,
  FolderOpen,
  Gavel,
  Inbox,
  KeyRound,
  LayoutDashboard,
  ListFilter,
  LogOut,
  Mail,
  Menu,
  Monitor,
  MoreHorizontal,
  Moon,
  Palette,
  Search,
  Settings,
  Sun,
  Trash2,
  UserCog,
  UserMinus,
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
import { Switch } from '@/components/ui/switch'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { cn } from '@/lib/utils'

type AdminView = 'team' | 'organisation' | 'personal'
type TeamView = 'members' | 'invitations'
type OrganisationSection = 'profile' | 'operations'
type MemberState = 'Active' | 'Suspended'

const members = [
  { id: 'rj', name: 'Rishikesh Joshi', email: 'rishikesh@apextax.in', title: 'Founding partner', initials: 'RJ', role: 'Admin', owner: true, state: 'Active' as MemberState, joined: '18 Jun 2026', work: '6 open responsibilities' },
  { id: 'ak', name: 'Ananya Kapoor', email: 'ananya@apextax.in', title: 'Senior associate', initials: 'AK', role: 'Associate', owner: false, state: 'Active' as MemberState, joined: '21 Jun 2026', work: '4 open responsibilities' },
  { id: 'ms', name: 'Meera Shah', email: 'meera@apextax.in', title: 'Associate', initials: 'MS', role: 'Associate', owner: false, state: 'Active' as MemberState, joined: '02 Jul 2026', work: '2 open responsibilities' },
  { id: 'vs', name: 'Vikram Singh', email: 'vikram@apextax.in', title: 'Client reviewer', initials: 'VS', role: 'Viewer', owner: false, state: 'Active' as MemberState, joined: '14 Jul 2026', work: 'No assigned work' },
  { id: 'np', name: 'Nisha Patel', email: 'nisha@apextax.in', title: 'Associate', initials: 'NP', role: 'Associate', owner: false, state: 'Suspended' as MemberState, joined: '19 Jul 2026', work: 'Access paused · 1 task reassigned' },
]

const invitations = [
  { id: '1', email: 'arjun@apextax.in', role: 'Associate', state: 'Pending', sent: 'Today, 09:42', expires: '02 Sep 2026', invitedBy: 'Rishikesh Joshi' },
  { id: '2', email: 'priya@apextax.in', role: 'Viewer', state: 'Expired', sent: '11 Aug 2026', expires: '18 Aug 2026', invitedBy: 'Ananya Kapoor' },
  { id: '3', email: 'finance@apextax.in', role: 'Viewer', state: 'Revoked', sent: '05 Aug 2026', expires: '12 Aug 2026', invitedBy: 'Rishikesh Joshi' },
]

function AppRail({ view, onChange }: { view: AdminView; onChange: (view: AdminView) => void }) {
  const main = [
    { label: 'Today', icon: LayoutDashboard },
    { label: 'Document Hub', icon: Inbox },
    { label: 'Matters', icon: FolderOpen },
    { label: 'Activity', icon: Activity },
  ]

  return (
    <aside className="hidden w-16 shrink-0 flex-col items-center border-r border-[var(--sidebar-border,var(--border))] bg-[var(--sidebar-bg)] py-2 text-[var(--sidebar-text)] lg:flex">
      <div className="mb-4 flex size-10 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--sidebar-text-active)]">
        <Gavel className="size-5" />
      </div>
      {main.map(({ label, icon: Icon }) => (
        <button key={label} type="button" aria-label={label} className="mb-1 flex size-11 items-center justify-center rounded-[var(--radius-sm)] hover:bg-[var(--sidebar-hover)]">
          <Icon className="size-5" />
        </button>
      ))}
      <div className="my-2 h-px w-8 bg-[var(--sidebar-border,var(--border))]" />
      <button type="button" onClick={() => onChange('team')} aria-label="Team" className={cn('mb-1 flex size-11 items-center justify-center rounded-[var(--radius-sm)]', view === 'team' ? 'bg-[var(--sidebar-active)] text-[var(--sidebar-text-active)]' : 'hover:bg-[var(--sidebar-hover)]')}>
        <Users className="size-5" />
      </button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild><button type="button" aria-label="Open account menu" className="mt-auto flex size-10 items-center justify-center rounded-full border border-[var(--sidebar-border,var(--border))] text-xs font-semibold">RJ</button></DropdownMenuTrigger>
        <DropdownMenuContent align="end"><DropdownMenuItem onClick={() => onChange('personal')}><Settings className="size-4" />My settings</DropdownMenuItem></DropdownMenuContent>
      </DropdownMenu>
    </aside>
  )
}

function AppHeader({ view, onChange }: { view: AdminView; onChange: (view: AdminView) => void }) {
  const [appearance, setAppearance] = useState('System')
  const label = view === 'team' ? 'Team' : view === 'organisation' ? 'Organisation settings' : 'My settings'
  return (
    <>
      <div className="hidden h-11 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-5 text-sm lg:flex">
        <span className="text-[var(--text-muted)]">Apex Tax Advocates</span>
        <ChevronRight className="size-4 text-[var(--text-muted)]" />
        <span>{label}</span>
        <div className="ml-auto flex items-center gap-3">
          <div className="flex h-8 w-64 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] px-3 text-xs text-[var(--text-muted)]">
            <Search className="size-4" />Search CaseChain <span className="ml-auto">⌘ K</span>
          </div>
          <Bell className="size-4" />
          <DropdownMenu>
            <DropdownMenuTrigger asChild><button type="button" aria-label="Open account menu" className="flex min-h-10 items-center gap-1 rounded-[var(--radius-sm)] px-1 hover:bg-[var(--surface-hover)]"><span className="flex size-8 items-center justify-center rounded-full bg-[var(--accent-muted)] text-xs font-semibold text-[var(--accent)]">RJ</span><ChevronDown className="size-4" /></button></DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-72">
              <DropdownMenuLabel><span className="block text-sm font-semibold">Rishikesh Joshi</span><span className="mt-0.5 block text-xs font-normal text-[var(--text-muted)]">rishikesh@apextax.in</span></DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuLabel><span className="block text-xs font-medium text-[var(--text-muted)]">Apex Tax Advocates</span><span className="mt-0.5 block text-sm">Owner · Admin</span></DropdownMenuLabel>
              <DropdownMenuSeparator />
              <DropdownMenuLabel className="pb-1 text-xs text-[var(--text-muted)]">Appearance</DropdownMenuLabel>
              <div role="group" aria-label="Appearance" className="mx-2 mb-2 grid grid-cols-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-0.5">{[{ label: 'System', icon: Monitor }, { label: 'Light', icon: Sun }, { label: 'Dark', icon: Moon }].map(({ label: item, icon: Icon }) => <button key={item} type="button" onClick={() => setAppearance(item)} className={cn('flex min-h-9 items-center justify-center gap-1 rounded-[calc(var(--radius-sm)-2px)] text-xs', appearance === item ? 'bg-[var(--surface)] shadow-xs' : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)]')}><Icon className="size-3.5" />{item}</button>)}</div>
              <DropdownMenuItem onClick={() => onChange('personal')}><Settings className="size-4" />My settings</DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem destructive><LogOut className="size-4" />Sign out</DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>
      <header className="flex min-h-14 shrink-0 items-center gap-3 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 lg:hidden">
        <button type="button" aria-label="Open navigation" className="flex size-11 items-center justify-center lg:hidden"><Menu className="size-6" /></button>
        <div className="min-w-0">
          <h1 className="truncate text-lg font-semibold">{label}</h1>
          <p className="truncate text-xs text-[var(--text-muted)]">Apex Tax Advocates · Organisation workspace</p>
        </div>
        <div className="ml-auto flex items-center gap-1"><DropdownMenu><DropdownMenuTrigger asChild><Button variant="outline" size="icon" aria-label="More navigation"><MoreHorizontal className="size-5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuLabel>Navigate</DropdownMenuLabel><DropdownMenuItem onClick={() => onChange('team')}><Users className="size-4" />Team</DropdownMenuItem><DropdownMenuItem onClick={() => onChange('personal')}><Settings className="size-4" />My settings</DropdownMenuItem><DropdownMenuItem onClick={() => onChange('organisation')}><ArchiveRestore className="size-4" />Organisation settings</DropdownMenuItem></DropdownMenuContent></DropdownMenu></div>
      </header>
    </>
  )
}

function CompactTabs<T extends string>({ value, items, onChange, label }: { value: T; items: Array<{ value: T; label: string; count?: number }>; onChange: (value: T) => void; label: string }) {
  return (
    <div role="tablist" aria-label={label} className="flex min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-0.5">
      {items.map((item) => (
        <button key={item.value} type="button" role="tab" aria-selected={value === item.value} onClick={() => onChange(item.value)} className={cn('flex min-h-11 min-w-0 items-center gap-1.5 rounded-[calc(var(--radius-sm)-2px)] px-3 text-xs font-medium lg:min-h-9', value === item.value ? 'bg-[var(--surface)] text-[var(--text-primary)] shadow-xs' : 'text-[var(--text-muted)] hover:bg-[var(--surface-hover)]')}>
          <span className="truncate">{item.label}</span>
          {item.count !== undefined && <span className={cn('flex size-4 shrink-0 items-center justify-center rounded-full text-[9px] font-semibold', value === item.value ? 'bg-[var(--accent)] text-[var(--on-accent)]' : 'bg-[var(--surface)] text-[var(--text-muted)]')}>{item.count}</span>}
        </button>
      ))}
    </div>
  )
}

function Workbar({ views, middle, actions }: { views: React.ReactNode; middle?: React.ReactNode; actions: React.ReactNode }) {
  return (
    <div className="flex min-h-14 shrink-0 flex-wrap items-center gap-x-2 gap-y-1 border-b border-[var(--border-subtle)] bg-[var(--surface)] px-3 py-1.5 lg:flex-nowrap lg:px-4 lg:py-0">
      <div className="min-w-0 shrink-0">{views}</div>
      <div className="min-w-0 flex-1 basis-48 lg:basis-auto">{middle}</div>
      <div className="flex w-full min-w-0 flex-wrap items-center justify-end gap-2 lg:ml-auto lg:w-auto lg:flex-nowrap">{actions}</div>
    </div>
  )
}

function SearchBox({ placeholder }: { placeholder: string }) {
  return <label className="relative block w-full max-w-md"><span className="sr-only">{placeholder}</span><Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--text-muted)]" /><Input placeholder={placeholder} className="pl-9" /></label>
}

function MemberTable({ onSelect }: { onSelect: (id: string) => void }) {
  return (
    <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <table className="hidden w-full border-collapse text-left md:table">
        <thead className="bg-[var(--bg-overlay)] text-[10px] uppercase tracking-wide text-[var(--text-muted)]">
          <tr><th className="px-4 py-2.5">Person</th><th className="px-4 py-2.5">Role</th><th className="px-4 py-2.5">Status</th><th className="px-4 py-2.5">Joined</th><th className="px-4 py-2.5">Current responsibility</th><th className="w-10"><span className="sr-only">Open</span></th></tr>
        </thead>
        <tbody className="divide-y divide-[var(--border-subtle)]">
          {members.map((member) => (
            <tr key={member.id} tabIndex={0} onClick={() => onSelect(member.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onSelect(member.id) } }} className={cn('cursor-pointer outline-none hover:bg-[var(--surface-hover)] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--accent-ring)]', member.state === 'Suspended' && 'text-[var(--text-disabled)]')}>
              <td className="px-4 py-3"><div className="flex items-center gap-3"><Avatar name={member.name} size="sm" /><div className="min-w-0"><div className="flex items-center gap-2"><span className="truncate text-sm font-medium">{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</div><div className="truncate text-xs text-[var(--text-muted)]">{member.email} · {member.title}</div></div></div></td>
              <td className="px-4 py-3"><Badge variant={member.role === 'Admin' ? 'default' : 'outline'} fixedWidth="md">{member.role}</Badge></td>
              <td className="px-4 py-3"><Badge variant={member.state === 'Active' ? 'success' : 'muted'} fixedWidth="lg">{member.state}</Badge></td>
              <td className="whitespace-nowrap px-4 py-3 text-xs text-[var(--text-secondary)]">{member.joined}</td>
              <td className="px-4 py-3 text-xs text-[var(--text-secondary)]">{member.work}</td>
              <td className="pr-3"><ChevronRight className="size-4 text-[var(--text-muted)]" /></td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="divide-y divide-[var(--border-subtle)] md:hidden">
        {members.map((member) => (
          <button key={member.id} type="button" onClick={() => onSelect(member.id)} className={cn('flex min-h-20 w-full items-center gap-3 p-3 text-left', member.state === 'Suspended' && 'text-[var(--text-disabled)]')}>
            <Avatar name={member.name} size="sm" />
            <div className="min-w-0 flex-1"><div className="flex items-center gap-2"><span className="truncate text-sm font-semibold">{member.name}</span>{member.owner && <Badge variant="warning">Owner</Badge>}</div><div className="mt-1 flex items-center gap-2"><Badge variant={member.role === 'Admin' ? 'default' : 'outline'} fixedWidth="md">{member.role}</Badge><Badge variant={member.state === 'Active' ? 'success' : 'muted'} fixedWidth="lg">{member.state}</Badge></div></div>
            <ChevronRight className="size-4 text-[var(--text-muted)]" />
          </button>
        ))}
      </div>
    </div>
  )
}

function InvitationTable({ showHistory }: { showHistory: boolean }) {
  const visibleInvitations = showHistory ? invitations : invitations.filter((invite) => invite.state === 'Pending')
  return (
    <div className="overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]">
      <table className="hidden w-full border-collapse text-left md:table">
        <thead className="bg-[var(--bg-overlay)] text-[10px] uppercase tracking-wide text-[var(--text-muted)]"><tr><th className="px-4 py-2.5">Email</th><th className="px-4 py-2.5">Role</th><th className="px-4 py-2.5">Status</th><th className="px-4 py-2.5">Sent</th><th className="px-4 py-2.5">Expires</th><th className="px-4 py-2.5">Invited by</th><th className="w-12"><span className="sr-only">Actions</span></th></tr></thead>
        <tbody className="divide-y divide-[var(--border-subtle)]">{visibleInvitations.map((invite) => <tr key={invite.id} className={cn(invite.state !== 'Pending' && 'text-[var(--text-disabled)]')}><td className="px-4 py-3 text-sm font-medium">{invite.email}</td><td className="px-4 py-3"><Badge variant="outline" fixedWidth="md">{invite.role}</Badge></td><td className="px-4 py-3"><Badge variant={invite.state === 'Pending' ? 'warning' : 'muted'} fixedWidth="md">{invite.state}</Badge></td><td className="px-4 py-3 text-xs">{invite.sent}</td><td className="px-4 py-3 text-xs">{invite.expires}</td><td className="px-4 py-3 text-xs">{invite.invitedBy}</td><td><Button variant="ghost" size="icon" aria-label={`Actions for ${invite.email}`}><MoreHorizontal className="size-4" /></Button></td></tr>)}</tbody>
      </table>
      <div className="divide-y divide-[var(--border-subtle)] md:hidden">{visibleInvitations.map((invite) => <div key={invite.id} className={cn('flex min-h-24 items-center gap-3 p-4', invite.state !== 'Pending' && 'text-[var(--text-disabled)]')}><div className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)]"><Mail className="size-4" /></div><div className="min-w-0 flex-1"><div className="truncate text-sm font-semibold">{invite.email}</div><div className="mt-1 flex items-center gap-2"><Badge variant="outline" fixedWidth="md">{invite.role}</Badge><Badge variant={invite.state === 'Pending' ? 'warning' : 'muted'} fixedWidth="md">{invite.state}</Badge></div><div className="mt-1 text-xs text-[var(--text-muted)]">Expires {invite.expires}</div></div><Button variant="ghost" size="icon" aria-label={`Actions for ${invite.email}`}><MoreHorizontal className="size-4" /></Button></div>)}</div>
    </div>
  )
}

function MemberInspector({ id, onClose }: { id: string; onClose: () => void }) {
  const member = members.find((item) => item.id === id) ?? members[0]
  const [action, setAction] = useState<'suspend' | 'remove' | null>(null)
  const impact = member.id === 'ak' ? '3 open tasks, 1 Review assignment, 2 accountable deadlines, and 1 Matter cost grant' : 'their current task, Review, deadline, and Matter grant assignments'
  return (
    <aside className="flex min-h-0 flex-1 flex-col bg-[var(--surface)] xl:relative xl:w-full xl:max-w-sm xl:shrink-0 xl:border-l xl:border-[var(--border-subtle)]">
      <div className="flex h-14 shrink-0 items-center gap-2 border-b border-[var(--border-subtle)] px-4"><Button variant="ghost" size="sm" className="-ml-2 xl:hidden" onClick={onClose}><ChevronRight className="size-4 rotate-180" />Back to members</Button><UserCog className="hidden size-4 text-[var(--accent)] xl:block" /><span className="hidden text-sm font-semibold xl:inline">Member access</span><Button variant="ghost" size="icon" className="ml-auto hidden xl:inline-flex" onClick={onClose} aria-label="Close member details"><X className="size-4" /></Button></div>
      <div className="min-h-0 flex-1 overflow-y-auto p-4">
        <div className="flex items-start gap-3"><Avatar name={member.name} size="lg" /><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><h2 className="text-lg font-semibold">{member.name}</h2>{member.owner && <Badge variant="warning">Owner</Badge>}</div><p className="text-xs text-[var(--text-muted)]">{member.email}</p><p className="mt-0.5 text-xs text-[var(--text-muted)]">{member.title}</p></div></div>
        <div className="mt-4 grid grid-cols-2 gap-2"><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs text-[var(--text-muted)]">Role</div><div className="mt-1 text-sm font-semibold">{member.role}</div></div><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><div className="text-xs text-[var(--text-muted)]">Access</div><div className="mt-1 text-sm font-semibold">{member.state}</div></div></div>
        <section className="mt-5"><h3 className="text-sm font-semibold">Offboarding impact</h3><p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">Checked live before any role, suspension, or removal command.</p><div className="mt-3 overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-subtle)]">{[['Open tasks', member.id === 'ak' ? '3' : '0'], ['Review assignments', member.id === 'ak' ? '1' : '0'], ['Accountable deadlines', member.id === 'ak' ? '2' : '0'], ['Private cost grants', member.id === 'ak' ? '1 Matter · Edit' : 'None']].map(([label, value]) => <div key={label} className="flex items-center border-b border-[var(--border-subtle)] px-3 py-2.5 last:border-b-0"><span className="text-xs text-[var(--text-muted)]">{label}</span><span className="ml-auto text-sm font-medium">{value}</span></div>)}</div></section>
        <section className="mt-5"><h3 className="text-sm font-semibold">Access history</h3><div className="mt-3 space-y-3"><div className="flex gap-3"><span className="mt-1 size-2 rounded-full bg-[var(--success)]" /><div><div className="text-sm font-medium">Joined as {member.role}</div><div className="text-xs text-[var(--text-muted)]">{member.joined} · Invitation accepted</div></div></div><div className="flex gap-3"><span className="mt-1 size-2 rounded-full bg-[var(--accent)]" /><div><div className="text-sm font-medium">Matter cost access updated</div><div className="text-xs text-[var(--text-muted)]">18 Aug · Apex Auto Components</div></div></div></div></section>
      </div>
      {!member.owner && <div className="flex shrink-0 flex-wrap gap-2 border-t border-[var(--border-subtle)] p-3"><Button variant="outline" className="flex-1">Change role</Button>{member.state === 'Suspended' ? <Button variant="outline" className="flex-1"><ArchiveRestore className="size-4" />Reactivate</Button> : <Button variant="outline" className="flex-1" onClick={() => setAction('suspend')}><UserMinus className="size-4" />Suspend</Button>}<Button variant="destructive" onClick={() => setAction('remove')}><Trash2 className="size-4" />Remove</Button></div>}
      <Dialog open={action !== null} onOpenChange={(open) => !open && setAction(null)}><DialogContent className="sm:max-w-lg"><DialogHeader><DialogTitle>{action === 'remove' ? `Remove ${member.name}?` : `Suspend ${member.name}?`}</DialogTitle><DialogDescription>{action === 'remove' ? 'Removal revokes current organisation access and personal delivery schedules. Historical work remains attributed.' : 'Suspension immediately pauses organisation access and eligible delivery while preserving the membership for later reactivation.'}</DialogDescription></DialogHeader><div className="rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg-overlay)] p-3 text-sm leading-6"><span className="font-medium">Impact to resolve:</span> {impact}. Work must be reassigned to an eligible active member or returned to a permitted team queue; nothing is silently completed.</div><DialogFooter><Button variant="outline" onClick={() => setAction(null)}>Cancel</Button><Button variant={action === 'remove' ? 'destructive' : 'default'} onClick={() => setAction(null)}>{action === 'remove' ? 'Remove member' : 'Continue to reassignment'}</Button></DialogFooter></DialogContent></Dialog>
    </aside>
  )
}

function InviteDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const [role, setRole] = useState('Associate')
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader><DialogTitle>Invite team member</DialogTitle><DialogDescription>The invitation expires in seven days. Organisation permissions remain the upper limit for every feature.</DialogDescription></DialogHeader>
        <div className="space-y-4"><label className="block"><span className="mb-1.5 block text-xs font-medium">Work email</span><Input type="email" placeholder="colleague@firm.in" /></label><fieldset><legend className="mb-1.5 text-xs font-medium">Organisation role</legend><div className="grid grid-cols-3 gap-2">{['Associate', 'Viewer', 'Admin'].map((item) => <button key={item} type="button" onClick={() => setRole(item)} className={cn('min-h-16 rounded-[var(--radius-sm)] border p-2 text-left', role === item ? 'border-[var(--accent)] bg-[var(--accent-muted)]' : 'border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]')}><span className="block text-sm font-semibold">{item}</span><span className="mt-1 block text-[10px] leading-4 text-[var(--text-muted)]">{item === 'Viewer' ? 'Read only' : item === 'Associate' ? 'Ordinary case work' : 'Owner-authorised admin'}</span></button>)}</div></fieldset>{role === 'Admin' && <div className="rounded-[var(--radius-sm)] border border-[var(--warning)] bg-[var(--warning-muted)] p-3 text-xs leading-5 text-[var(--warning)]">Only the Owner can invite an Admin. Admins can manage organisation policy and ordinary members.</div>}</div>
        <DialogFooter><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button onClick={() => onOpenChange(false)}><Mail className="size-4" />Send invitation</Button></DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function TeamWorkspace({ onChange }: { onChange: (view: AdminView) => void }) {
  const [teamView, setTeamView] = useState<TeamView>('members')
  const [selectedMember, setSelectedMember] = useState<string | null>(null)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [showInvitationHistory, setShowInvitationHistory] = useState(false)
  return (
    <div className="relative flex min-h-0 flex-1 flex-col overflow-hidden">
      <div className={cn(selectedMember && 'hidden xl:block')}><Workbar views={<CompactTabs value={teamView} onChange={setTeamView} label="Team views" items={[{ value: 'members', label: 'Members', count: 5 }, { value: 'invitations', label: 'Invitations', count: 1 }]} />} middle={<SearchBox placeholder={teamView === 'members' ? 'Search members' : 'Search invitations'} />} actions={<>{teamView === 'invitations' && <Button variant="outline" size="sm" onClick={() => setShowInvitationHistory((value) => !value)}>{showInvitationHistory ? 'Pending only' : 'Show history'}</Button>}<Button variant="outline" size="sm" onClick={() => onChange('organisation')}>Organisation settings</Button><Button variant="outline" size="sm"><ListFilter className="size-4" />Filters</Button><Button size="sm" onClick={() => setInviteOpen(true)}><UserPlus className="size-4" />Invite member</Button></>} /></div>
      <div className="relative flex min-h-0 flex-1 overflow-hidden">
        <div className={cn('min-w-0 flex-1 overflow-y-auto p-3 lg:p-4', selectedMember && 'hidden xl:block')}><div className="mx-auto max-w-7xl">{teamView === 'members' ? <MemberTable onSelect={setSelectedMember} /> : <InvitationTable showHistory={showInvitationHistory} />}</div></div>
        {selectedMember && <MemberInspector id={selectedMember} onClose={() => setSelectedMember(null)} />}
      </div>
      <InviteDialog open={inviteOpen} onOpenChange={setInviteOpen} />
    </div>
  )
}

function SettingField({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return <label className="grid gap-1.5 sm:grid-cols-[190px_minmax(0,1fr)] sm:items-start"><span className="pt-2"><span className="block text-sm font-medium">{label}</span>{hint && <span className="mt-0.5 block text-xs leading-5 text-[var(--text-muted)]">{hint}</span>}</span><span className="[&>button]:min-h-11 [&>button]:lg:min-h-10">{children}</span></label>
}

function SettingsPanel({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return <section className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)]"><div className="border-b border-[var(--border-subtle)] px-4 py-3"><h2 className="text-sm font-semibold">{title}</h2>{description && <p className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">{description}</p>}</div><div className="space-y-4 p-4">{children}</div></section>
}

function OrganisationContent({ section }: { section: OrganisationSection }) {
  const [autoPurge, setAutoPurge] = useState(false)
  if (section === 'profile') return <div className="space-y-3"><SettingsPanel title="Organisation profile" description="Visible to active members and used in invitations."><SettingField label="Display name"><Input defaultValue="Apex Tax Advocates" /></SettingField><SettingField label="Registered name" hint="Optional legal or firm name"><Input defaultValue="Apex Tax Advocates LLP" /></SettingField><SettingField label="Established on" hint="Historical information, not the CaseChain creation date"><Input type="date" defaultValue="1998-08-14" /></SettingField><SettingField label="Short tagline" hint="Used only in profile and invitation contexts"><Input defaultValue="Clarity in indirect-tax disputes" maxLength={120} /></SettingField></SettingsPanel><SettingsPanel title="Regional defaults"><SettingField label="Timezone"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-3 text-sm">Asia/Kolkata <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Locale and date"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-3 text-sm">English (India) · DD MMM YYYY <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Currency"><Input value="INR · Indian Rupee" readOnly /></SettingField></SettingsPanel></div>
  return <div className="space-y-3"><SettingsPanel title="Storage" description="Platform limits are visible here but cannot be raised by an organisation administrator."><div className="flex items-end gap-3"><span className="flex size-9 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><Database className="size-4" /></span><div className="min-w-0 flex-1"><div className="flex items-center text-sm"><span className="font-semibold">64.2 MB used</span><span className="ml-auto text-xs text-[var(--text-muted)]">100 MB entitlement</span></div><div className="mt-2 h-2 overflow-hidden rounded-[var(--radius-sm)] bg-[var(--bg-overlay)]"><div className="h-full w-[64%] bg-[var(--accent)]" /></div></div></div></SettingsPanel><SettingsPanel title="Trash retention" description="Changes apply to future deletions unless existing entries are explicitly extended."><SettingField label="Retention"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">Manual permanent deletion only <ChevronDown className="ml-auto size-4" /></button></SettingField><div className="flex items-start gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] p-3"><ArchiveRestore className="mt-0.5 size-4 text-[var(--text-muted)]" /><div className="min-w-0 flex-1"><div className="text-sm font-medium">Automatically delete after the retention period</div><div className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">Off by default. Legal holds and active blockers always prevent permanent deletion.</div></div><Switch checked={autoPurge} onCheckedChange={setAutoPurge} aria-label="Automatically delete after the retention period" /></div></SettingsPanel><SettingsPanel title="Organisation defaults"><SettingField label="Weekly digest" hint="Members may override non-mandatory email"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">Monday · 08:30 · Asia/Kolkata <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Deadline reminders"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">14, 7, 3 and 1 day before <ChevronDown className="ml-auto size-4" /></button></SettingField></SettingsPanel></div>
}

function OrganisationWorkspace() {
  const [section, setSection] = useState<OrganisationSection>('profile')
  return <div className="flex min-h-0 flex-1 flex-col overflow-hidden"><Workbar views={<CompactTabs value={section} onChange={setSection} label="Organisation settings sections" items={[{ value: 'profile', label: 'Profile' }, { value: 'operations', label: 'Operations' }]} />} middle={<span className="hidden text-xs text-[var(--text-muted)] lg:inline">Created in CaseChain 18 Jun 2026</span>} actions={<Button size="sm"><Check className="size-4" />Save changes</Button>} /><div className="min-h-0 flex-1 overflow-y-auto p-3 lg:p-4"><div className="mx-auto max-w-4xl"><OrganisationContent section={section} /></div></div></div>
}

function PreferenceRow({ title, description, checked: initial = false }: { title: string; description: string; checked?: boolean }) {
  const [checked, setChecked] = useState(initial)
  return <div className="flex items-start gap-3 border-b border-[var(--border-subtle)] pb-3 last:border-b-0 last:pb-0"><div className="min-w-0 flex-1"><div className="text-sm font-medium">{title}</div><div className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">{description}</div></div><Switch checked={checked} onCheckedChange={setChecked} aria-label={title} /></div>
}

function PersonalWorkspace({ onChange }: { onChange: (view: AdminView) => void }) {
  const [appearance, setAppearance] = useState('System')
  return <div className="flex min-h-0 flex-1 flex-col overflow-hidden"><Workbar views={<div className="flex min-h-11 items-center gap-2 text-sm font-medium"><UserCog className="size-4 text-[var(--accent)]" /><span>Profile &amp; preferences</span></div>} middle={<span className="block truncate text-xs text-[var(--text-muted)]">Private profile, appearance, and notification preferences</span>} actions={<Button size="sm"><Check className="size-4" />Save changes</Button>} /><div className="min-h-0 flex-1 overflow-y-auto p-3 lg:p-4"><div className="mx-auto max-w-4xl space-y-3"><div className="flex items-center gap-3 rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--surface)] px-4 py-3"><div className="min-w-0 flex-1"><div className="text-sm font-medium">Apex Tax Advocates</div><div className="text-xs text-[var(--text-muted)]">Organisation · Owner · Admin</div></div><Button variant="outline" size="sm" onClick={() => onChange('organisation')}>Organisation settings</Button></div><SettingsPanel title="Personal profile" description="Your teammate identity across CaseChain."><div className="flex items-center gap-3"><Avatar name="Rishikesh Joshi" size="lg" /><div><div className="text-sm font-medium">RJ</div><p className="mt-0.5 text-xs text-[var(--text-muted)]">Initials are generated from your display name</p></div></div><SettingField label="Display name"><Input defaultValue="Rishikesh Joshi" /></SettingField><SettingField label="Professional title"><Input defaultValue="Founding partner" /></SettingField><SettingField label="Email" hint="Changes require verification"><div className="flex gap-2"><Input value="rishikesh@apextax.in" readOnly /><Button variant="outline">Change</Button></div></SettingField><SettingField label="Personal timezone"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">Asia/Kolkata <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Locale and date"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">English (India) · DD MMM YYYY <ChevronDown className="ml-auto size-4" /></button></SettingField></SettingsPanel><SettingsPanel title="Account access"><div className="flex items-center gap-3"><span className="flex size-9 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)]"><KeyRound className="size-4" /></span><div className="min-w-0 flex-1"><div className="text-sm font-medium">Password</div><div className="text-xs text-[var(--text-muted)]">Managed through a secure verification flow</div></div><Button variant="outline">Change password</Button></div></SettingsPanel><SettingsPanel title="Appearance" description="Civic Ink uses the same semantic interface in light and dark appearances."><div className="grid grid-cols-3 gap-2">{['System', 'Light', 'Dark'].map((item) => <button key={item} type="button" onClick={() => setAppearance(item)} className={cn('min-h-20 rounded-[var(--radius-sm)] border p-3 text-left', appearance === item ? 'border-[var(--accent)] bg-[var(--accent-muted)]' : 'border-[var(--border-subtle)] hover:bg-[var(--surface-hover)]')}><Palette className="size-4" /><span className="mt-3 block text-sm font-semibold">{item}</span></button>)}</div><div className="flex items-start gap-2 rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] p-3 text-xs leading-5 text-[var(--text-muted)]"><Monitor className="mt-0.5 size-4 shrink-0" /><span>Motion follows your device accessibility setting. CaseChain keeps useful transitions subtle and removes nonessential animation when reduced motion is requested.</span></div></SettingsPanel><SettingsPanel title="Direct email" description="Optional direct email is Off for every family by default. Mandatory security delivery is always sent and is not a preference."><PreferenceRow title="Mentions" description="Optional direct email · Off. Email me when a teammate directly mentions me in a note." /><PreferenceRow title="Task and Review assignments" description="Optional direct email · Off. Email me when work is assigned or escalated to me." /><PreferenceRow title="Verified deadline reminders" description="Optional direct email · Off. Uses my selected lead times and quiet hours." /><SettingField label="Deadline lead times"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">14, 7, 3 and 1 day before <ChevronDown className="ml-auto size-4" /></button></SettingField><PreferenceRow title="Assigned failures" description="Optional direct email · Off. Only failures that require my action." /></SettingsPanel><SettingsPanel title="Weekly digest" description="One deterministic weekly email; it is Off by default and not a Dashboard card."><PreferenceRow title="Send weekly digest" description="Optional direct email · Off. Open work, verified dates, mentions, Review, and a restrained activity summary." /><SettingField label="Included families"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">Open work, verified dates, mentions and Review <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Schedule and timezone"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">Monday · 08:30 · Asia/Kolkata <ChevronDown className="ml-auto size-4" /></button></SettingField><SettingField label="Quiet hours"><button type="button" className="flex min-h-10 w-full items-center rounded-[var(--radius-sm)] border border-[var(--border)] px-3 text-sm">21:00–07:30 <ChevronDown className="ml-auto size-4" /></button></SettingField></SettingsPanel></div></div></div>
}

export function OrganisationAdminConcept() {
  const [view, setView] = useState<AdminView>('team')
  return <div className="flex h-dvh overflow-hidden bg-[var(--bg)] text-[var(--text-primary)]"><AppRail view={view} onChange={setView} /><main className="flex min-w-0 flex-1 flex-col overflow-hidden"><AppHeader view={view} onChange={setView} />{view === 'team' ? <TeamWorkspace onChange={setView} /> : view === 'organisation' ? <OrganisationWorkspace /> : <PersonalWorkspace onChange={setView} />}</main></div>
}
