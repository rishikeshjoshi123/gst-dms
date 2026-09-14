'use client'

import { useEffect, useMemo, useRef, useState, useTransition } from 'react'
import Link from 'next/link'
import { ChevronLeft, Mail, Search, UserPlus, UserRound } from 'lucide-react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'

import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { FormField } from '@/components/ui/label'
import { cn, formatDate } from '@/lib/utils'
import { inviteMember, resendInvite, revokeInvite } from '@/lib/actions/org'
import type { TeamDirectoryEntry, TeamDirectoryParams, TeamDirectoryResult } from '@/lib/organisation/team-directory'
import { toast } from 'sonner'

type InvitationState = 'pending' | 'accepted' | 'rejected' | 'expired' | 'revoked' | 'superseded'
type TeamInvitation = { id: string; role: 'admin' | 'associate' | 'viewer'; state: InvitationState; created_at: string; expires_at: string; revision: number; authorized_email: string }

type TeamWorkspaceProps = {
  result: TeamDirectoryResult
  initialQuery: TeamDirectoryParams
  selectedMembershipId?: string
  view: 'members' | 'invitations'
  invitationState: string
  invitations: TeamInvitation[]
  capabilities: string[]
}

const roleLabels = { admin: 'Admin', associate: 'Associate', viewer: 'Viewer' } as const

function memberName(member: TeamDirectoryEntry) {
  return member.display_name ?? 'Profile unavailable'
}

function setSearchValue(current: URLSearchParams, key: string, value?: string) {
  const next = new URLSearchParams(current)
  if (value) next.set(key, value)
  else next.delete(key)
  if (key === 'q' || key === 'role' || key === 'state') { next.delete('page'); next.delete('member') }
  return next
}

function RoleBadge({ member }: { member: TeamDirectoryEntry }) { return <Badge fixedWidth="lg" variant="outline">{roleLabels[member.role]}</Badge> }
function OwnerBadge({ member }: { member: TeamDirectoryEntry }) { return member.is_owner ? <Badge fixedWidth="md" variant="warning">Owner</Badge> : null }
function capabilityLabel(key: string) { return key.split(/[._]/).map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(' ') }

function StateBadge({ state }: { state: TeamDirectoryEntry['state'] }) {
  return <Badge fixedWidth="md" variant={state === 'active' ? 'success' : 'muted'}>{state === 'active' ? 'Active' : 'Suspended'}</Badge>
}

function InvitationStateBadge({ state }: { state: InvitationState }) {
  const variant = state === 'pending' ? 'warning' : state === 'accepted' ? 'success' : state === 'revoked' || state === 'rejected' ? 'danger' : 'muted'
  return <Badge fixedWidth="lg" variant={variant}>{state.charAt(0).toUpperCase()+state.slice(1)}</Badge>
}

function MemberInspector({ member, onBack }: { member: TeamDirectoryEntry; onBack: () => void }) {
  const shownCapabilities = member.capabilities.slice(0, 4)
  const capabilitySummary = member.capabilities.length === 0 ? 'Unavailable' : member.capabilities.length > shownCapabilities.length ? `${shownCapabilities.map(capabilityLabel).join(', ')} and ${member.capabilities.length - shownCapabilities.length} more` : `${shownCapabilities.map(capabilityLabel).join(', ')} (complete)`
  return (
    <aside className="flex min-h-0 flex-1 flex-col border-l border-[var(--border)] bg-[var(--surface)] lg:basis-2/5 lg:max-w-[42%]" aria-label="Member details">
      <header className="shrink-0 border-b border-[var(--border)] p-4">
        <Button variant="ghost" size="sm" className="mb-2 min-h-11 px-2 lg:hidden" onClick={onBack}><ChevronLeft size={16} />Back to members</Button><Button variant="ghost" size="sm" className="mb-2 hidden min-h-11 px-2 lg:inline-flex" onClick={onBack}>Close details</Button>
        <div className="flex items-center gap-3">
          <Avatar name={member.display_name ?? undefined} size="lg" />
          <div className="min-w-0">
            <h2 className="truncate text-section-heading text-[var(--text-primary)]">{memberName(member)}</h2>
            <p className="mt-0.5 truncate text-caption text-[var(--text-muted)]">{member.professional_title ?? 'Professional title unavailable'}</p>
          </div>
        </div>
      </header>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto p-4">
        <dl className="space-y-4 text-body">
          <div><dt className="text-caption text-[var(--text-muted)]">Email</dt><dd className="mt-1 break-words text-[var(--text-primary)]">{member.authorised_email ?? 'Unavailable'}</dd></div>
          <div><dt className="text-caption text-[var(--text-muted)]">Joined</dt><dd className="mt-1 text-[var(--text-primary)]">{formatDate(member.joined_at)}</dd></div>
          <div><dt className="text-caption text-[var(--text-muted)]">Role</dt><dd className="mt-1 flex gap-2"><RoleBadge member={member} /><OwnerBadge member={member} /></dd></div>
          <div><dt className="text-caption text-[var(--text-muted)]">Status</dt><dd className="mt-1"><StateBadge state={member.state} /></dd></div>
          <div><dt className="text-caption text-[var(--text-muted)]">Access summary</dt><dd className="mt-1 break-words text-[var(--text-primary)]">{capabilitySummary}</dd></div>
        </dl>
      </div>
    </aside>
  )
}

function InviteMemberDialog({ open, onOpenChange, canInviteAdmin }: { open: boolean; onOpenChange: (open: boolean) => void; canInviteAdmin: boolean }) {
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const [role, setRole] = useState<'associate' | 'viewer' | 'admin'>('associate')
  const idempotencyKey = useRef(crypto.randomUUID())

  function submit(formData: FormData) {
    setError(null)
    formData.set('role', role)
    formData.set('idempotency_key', idempotencyKey.current)
    startTransition(async () => {
      const result = await inviteMember(formData)
      if (result.error) { setError(result.error); return }
      toast.success('Invitation sent.')
      idempotencyKey.current = crypto.randomUUID()
      onOpenChange(false)
    })
  }

  function setOpen(next: boolean) {
    if (!next && !isPending) { setError(null); setRole('associate'); idempotencyKey.current=crypto.randomUUID() }
    onOpenChange(next)
  }

  const roles = [
    { value: 'associate' as const, label: 'Associate', detail: 'Can carry out ordinary case work.' },
    { value: 'viewer' as const, label: 'Viewer', detail: 'Can read authorised organisation work.' },
    ...(canInviteAdmin ? [{ value: 'admin' as const, label: 'Admin', detail: 'Owner-authorised organisation administrator.' }] : []),
  ]
  return <Dialog open={open} onOpenChange={setOpen}>
    <DialogContent className="sm:max-w-xl">
      <DialogHeader><DialogTitle>Invite member</DialogTitle><DialogDescription>Choose access before sending. The invitation expires in seven days and joining remains an explicit choice.</DialogDescription></DialogHeader>
      <form action={submit} className="space-y-4">
        <FormField label="Work email" htmlFor="invite-email" required error={error ?? undefined}>
          <Input id="invite-email" name="email" type="email" autoComplete="email" maxLength={320} required autoFocus disabled={isPending} placeholder="colleague@firm.in" />
        </FormField>
        <fieldset><legend className="mb-2 text-sm font-medium text-[var(--text-primary)]">Organisation role</legend>
          <div className={cn('grid gap-2', canInviteAdmin ? 'sm:grid-cols-3' : 'sm:grid-cols-2')}>
            {roles.map((item) => <button key={item.value} type="button" disabled={isPending} onClick={() => setRole(item.value)} aria-pressed={role===item.value} className={cn('min-h-20 rounded-[var(--radius-sm)] border p-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]', role===item.value ? 'border-[var(--accent)] bg-[var(--accent-muted)]' : 'border-[var(--border-strong)] bg-[var(--surface)] hover:bg-[var(--surface-hover)]', item.value==='admin' && 'border-[var(--warning)]')}><span className="block text-sm font-semibold text-[var(--text-primary)]">{item.label}{item.value==='admin' ? ' · Owner only' : ''}</span><span className="mt-1 block text-caption text-[var(--text-muted)]">{item.detail}</span></button>)}
          </div>
        </fieldset>
        <DialogFooter><Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={isPending}>Cancel</Button><Button type="submit" loading={isPending}><Mail aria-hidden="true" size={16} />Send invitation</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>
}

function InvitationCollection({ invitations, stateFilter, onStateChange }: { invitations: TeamInvitation[]; stateFilter: string; onStateChange: (value: string) => void }) {
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [revokeTarget, setRevokeTarget] = useState<TeamInvitation | null>(null)
  const [isPending, startTransition] = useTransition()

  function resend(invitation: TeamInvitation) {
    setPendingId(invitation.id)
    const key=crypto.randomUUID()
    startTransition(async () => {
      const result=await resendInvite(invitation.id,invitation.revision,key)
      setPendingId(null)
      if(result.error) toast.error(result.error)
      else toast.success('Invitation resent with a new seven-day expiry.')
    })
  }
  function revoke() {
    if (!revokeTarget) return
    const invitation=revokeTarget
    setPendingId(invitation.id)
    const key=crypto.randomUUID()
    startTransition(async () => {
      const result=await revokeInvite(invitation.id,invitation.revision,key)
      setPendingId(null); setRevokeTarget(null)
      if(result.error) toast.error(result.error)
      else toast.success('Invitation revoked.')
    })
  }
  const emptyLabel = stateFilter==='pending' ? 'No pending invitations' : 'No invitations match this history filter'
  return <>
    <div className="flex shrink-0 flex-col gap-2 border-b border-[var(--border)] px-4 py-3 sm:flex-row sm:items-end sm:justify-between">
      <div><h2 className="text-section-heading text-[var(--text-primary)]">Invitations</h2><p className="text-caption text-[var(--text-muted)]">Pending invitations are actionable. Use the filter to inspect terminal history.</p></div>
      <label className="w-full text-caption text-[var(--text-muted)] sm:w-48" htmlFor="invitation-state"><span className="mb-1 block">Invitation status</span><select id="invitation-state" value={stateFilter} onChange={(event)=>onStateChange(event.target.value)} className="min-h-11 w-full rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-body text-[var(--text-primary)]"><option value="pending">Pending</option><option value="accepted">Accepted</option><option value="rejected">Rejected</option><option value="expired">Expired</option><option value="revoked">Revoked</option><option value="superseded">Superseded</option><option value="all">All history</option></select></label>
    </div>
    {invitations.length===0 ? <div className="flex min-h-0 flex-1 items-center justify-center p-8 text-center"><div><Mail aria-hidden="true" className="mx-auto mb-3 text-[var(--text-muted)]"/><h2 className="text-section-heading text-[var(--text-primary)]">{emptyLabel}</h2><p className="mt-1 text-body text-[var(--text-muted)]">{stateFilter==='pending' ? 'Send an invitation when a colleague is ready to join.' : 'Choose another status to review invitation history.'}</p></div></div> : <>
      <div className="custom-scrollbar hidden min-h-0 flex-1 overflow-y-auto lg:block"><Table><TableHeader sticky><TableRow><TableHead>Email</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead><TableHead>Sent</TableHead><TableHead>Expires</TableHead><TableHead>Actions</TableHead></TableRow></TableHeader><TableBody>{invitations.map((invitation)=><TableRow key={invitation.id} className="h-14"><TableCell className="max-w-72 break-all font-medium text-[var(--text-primary)]">{invitation.authorized_email}</TableCell><TableCell><Badge fixedWidth="lg" variant="outline">{roleLabels[invitation.role]}</Badge></TableCell><TableCell><InvitationStateBadge state={invitation.state}/></TableCell><TableCell className="whitespace-nowrap text-caption text-[var(--text-muted)]">{formatDate(invitation.created_at)}</TableCell><TableCell className="whitespace-nowrap text-caption text-[var(--text-muted)]">{formatDate(invitation.expires_at)}</TableCell><TableCell>{invitation.state==='pending' ? <div className="flex gap-2"><Button variant="outline" size="sm" loading={pendingId===invitation.id&&isPending} onClick={()=>resend(invitation)}>Resend</Button><Button variant="destructive" size="sm" disabled={isPending} onClick={()=>setRevokeTarget(invitation)}>Revoke</Button></div> : <span className="text-caption text-[var(--text-muted)]">No action available</span>}</TableCell></TableRow>)}</TableBody></Table></div>
      <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto p-3 lg:hidden" aria-label="Organisation invitations">{invitations.map((invitation)=><article key={invitation.id} className="mb-2 min-w-0 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3"><p className="break-all text-sm font-medium text-[var(--text-primary)]">{invitation.authorized_email}</p><div className="mt-2 flex flex-wrap gap-2"><Badge fixedWidth="lg" variant="outline">{roleLabels[invitation.role]}</Badge><InvitationStateBadge state={invitation.state}/></div><p className="mt-2 text-caption text-[var(--text-muted)]">Sent {formatDate(invitation.created_at)} · Expires {formatDate(invitation.expires_at)}</p>{invitation.state==='pending'&&<div className="mt-3 flex flex-wrap gap-2"><Button variant="outline" size="sm" loading={pendingId===invitation.id&&isPending} onClick={()=>resend(invitation)}>Resend invitation</Button><Button variant="destructive" size="sm" disabled={isPending} onClick={()=>setRevokeTarget(invitation)}>Revoke invitation</Button></div>}</article>)}</div>
    </>}
    <ConfirmDialog isOpen={Boolean(revokeTarget)} onClose={()=>setRevokeTarget(null)} onConfirm={revoke} title="Revoke invitation?" description={`The current link for ${revokeTarget?.authorized_email ?? 'this address'} will stop working. This action is recorded in the administration audit.`} confirmText="Revoke invitation" isPending={isPending}/>
  </>
}

export function TeamWorkspace({ result, initialQuery, selectedMembershipId, view, invitationState, invitations, capabilities }: TeamWorkspaceProps) {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const lastSelected = useRef<string | null>(null)
  const inviteButtonRef=useRef<HTMLButtonElement>(null)
  const [inviteOpen,setInviteOpen]=useState(false)
  const selected = useMemo(() => result.ok ? result.entries.find((member) => member.membership_id === selectedMembershipId) : undefined, [result, selectedMembershipId])
  const hasFilters = Boolean(initialQuery.query || initialQuery.role || initialQuery.state)

  useEffect(() => {
    if (selected || !lastSelected.current) return
    const origin = lastSelected.current
    const frame = requestAnimationFrame(() => {
      document.querySelector<HTMLElement>(`[data-member-id="${origin}"]`)?.focus()
      lastSelected.current = null
    })
    return () => cancelAnimationFrame(frame)
  }, [selected])

  function navigate(next: URLSearchParams) {
    const href = next.size ? `${pathname}?${next.toString()}` : pathname
    router.push(href)
  }
  function select(member: TeamDirectoryEntry) { lastSelected.current = member.membership_id; navigate(setSearchValue(searchParams, 'member', member.membership_id)) }
  function clearSelection() { navigate(setSearchValue(searchParams, 'member')) }
  function clearFilters() { navigate(new URLSearchParams()) }
  function submitSearch(formData: FormData) { navigate(setSearchValue(searchParams, 'q', String(formData.get('q') ?? '').trim())) }
  function changeView(nextView: 'members' | 'invitations') {
    const next=new URLSearchParams()
    if(nextView==='invitations') next.set('view','invitations')
    navigate(next)
  }
  function changeInvitationState(nextState: string) {
    const next=new URLSearchParams(searchParams)
    next.set('view','invitations')
    if(nextState==='pending') next.delete('invite_state'); else next.set('invite_state',nextState)
    navigate(next)
  }
  function setInviteDialogOpen(open:boolean){
    setInviteOpen(open)
    if(!open) requestAnimationFrame(()=>inviteButtonRef.current?.focus())
  }

  const collection = result.ok ? (
    <>
      <div className="grid grid-cols-1 gap-2 border-b border-[var(--border)] px-4 py-2 text-caption text-[var(--text-muted)] sm:grid-cols-[minmax(0,1fr)_minmax(0,10rem)_minmax(0,10rem)] sm:items-end">
        <span className="self-center">{result.total} member{result.total === 1 ? '' : 's'}</span>
        <label className="min-w-0" htmlFor="team-role"><span className="mb-1 block">Role</span><select id="team-role" value={initialQuery.role ?? ''} onChange={(event) => navigate(setSearchValue(searchParams, 'role', event.target.value))} className="min-h-11 w-full min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-body text-[var(--text-primary)]"><option value="">All roles</option><option value="admin">Admin</option><option value="associate">Associate</option><option value="viewer">Viewer</option></select></label>
        <label className="min-w-0" htmlFor="team-state"><span className="mb-1 block">Status</span><select id="team-state" value={initialQuery.state ?? ''} onChange={(event) => navigate(setSearchValue(searchParams, 'state', event.target.value))} className="min-h-11 w-full min-w-0 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-2 text-body text-[var(--text-primary)]"><option value="">All statuses</option><option value="active">Active</option><option value="suspended">Suspended</option></select></label>
      </div>
      {result.entries.length === 0 ? <div className="flex flex-1 items-center justify-center p-8 text-center"><div><UserRound aria-hidden="true" className="mx-auto mb-3 text-[var(--text-muted)]" /><h2 className="text-section-heading text-[var(--text-primary)]">{hasFilters ? 'No matching members' : 'No team members yet'}</h2><p className="mt-1 text-body text-[var(--text-muted)]">{hasFilters ? 'Try changing your search or filters.' : 'An administrator can invite the first colleague from Team.'}</p>{hasFilters && <Button variant="outline" className="mt-4" onClick={clearFilters}>Clear filters</Button>}</div></div> : <>
        <div className="custom-scrollbar hidden min-h-0 flex-1 overflow-y-auto lg:block">
          <Table><TableHeader sticky><TableRow><TableHead>Person</TableHead><TableHead>Role</TableHead><TableHead>Status</TableHead><TableHead>Joined</TableHead></TableRow></TableHeader><TableBody>
            {result.entries.map((member) => <TableRow key={member.membership_id} interactive selected={selected?.membership_id === member.membership_id} className="h-12 cursor-pointer" onClick={() => select(member)}><TableCell className="py-0"><button data-member-id={member.membership_id} type="button" onClick={(event) => { event.stopPropagation(); select(member) }} className="flex h-12 max-w-full items-center gap-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><Avatar name={member.display_name ?? undefined} size="sm" /><span className="min-w-0"><span className="block truncate font-medium text-[var(--text-primary)]">{memberName(member)}</span><span className="block truncate text-caption text-[var(--text-muted)]">{member.professional_title ?? 'Professional title unavailable'}</span></span></button></TableCell><TableCell className="py-0"><div className="flex gap-1"><RoleBadge member={member} /><OwnerBadge member={member} /></div></TableCell><TableCell className="py-0"><StateBadge state={member.state} /></TableCell><TableCell className="whitespace-nowrap py-0 text-caption text-[var(--text-muted)]">{formatDate(member.joined_at)}</TableCell></TableRow>)}
          </TableBody></Table>
        </div>
        <div className="custom-scrollbar min-h-0 flex-1 overflow-y-auto p-3 lg:hidden" aria-label="Team members list">{result.entries.map((member) => <button data-member-id={member.membership_id} key={member.membership_id} type="button" onClick={() => select(member)} className="mb-2 flex min-h-12 w-full items-center gap-3 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]"><Avatar name={member.display_name ?? undefined} size="sm" /><span className="min-w-0 flex-1"><span className="block truncate font-medium text-[var(--text-primary)]">{memberName(member)}</span><span className="block truncate text-caption text-[var(--text-muted)]">{member.professional_title ?? 'Professional title unavailable'}</span><span className="mt-1 flex flex-wrap gap-1"><RoleBadge member={member} /><OwnerBadge member={member} /></span></span><StateBadge state={member.state} /></button>)}</div>
      </>}
      {result.total > result.limit && <div className="flex shrink-0 items-center justify-between border-t border-[var(--border)] px-4 py-2"><Button variant="outline" size="sm" disabled={result.offset === 0} onClick={() => navigate(setSearchValue(searchParams, 'page', String(Math.max(1, result.offset / result.limit))))}>Previous</Button><span className="text-caption text-[var(--text-muted)]">Page {Math.floor(result.offset / result.limit) + 1}</span><Button variant="outline" size="sm" disabled={result.offset + result.limit >= result.total} onClick={() => navigate(setSearchValue(searchParams, 'page', String(Math.floor(result.offset / result.limit) + 2)))}>Next</Button></div>}
    </>
  ) : <div className="flex flex-1 items-center justify-center p-8 text-center"><div><h1 className="text-page-title text-[var(--text-primary)]">Team unavailable</h1><p className="mt-2 text-body text-[var(--text-muted)]">We could not load the members directory. Please try again.</p><Button className="mt-4" onClick={() => router.refresh()}>Try again</Button></div></div>

  const canInvite=capabilities.includes('team.invite.standard')
  return <div className="flex min-h-0 flex-1 flex-col overflow-hidden"><BreadcrumbSetter breadcrumbs={[{ label: 'Team' }]} />
    <header className="shrink-0 border-b border-[var(--border)] bg-[var(--surface)] px-4 py-3">
      <div className="mb-3"><h1 className="text-page-title text-[var(--text-primary)]">Team</h1><p className="text-caption text-[var(--text-muted)]">Members and governed organisation invitations</p></div>
      <div className="flex flex-col gap-3 xl:flex-row xl:items-center">
        <div className="flex shrink-0 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg-overlay)] p-1" role="tablist" aria-label="Team views"><button type="button" role="tab" aria-selected={view==='members'} onClick={()=>changeView('members')} className={cn('min-h-11 rounded-[var(--radius-sm)] px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',view==='members'?'bg-[var(--surface)] text-[var(--text-primary)]':'text-[var(--text-muted)]')}>Members</button>{canInvite&&<button type="button" role="tab" aria-selected={view==='invitations'} onClick={()=>changeView('invitations')} className={cn('min-h-11 rounded-[var(--radius-sm)] px-4 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',view==='invitations'?'bg-[var(--surface)] text-[var(--text-primary)]':'text-[var(--text-muted)]')}>Invitations</button>}</div>
        {view==='members'&&<form action={submitSearch} className="flex min-w-0 flex-1 items-center gap-2" role="search"><label className="sr-only" htmlFor="team-search">Search members</label><div className="relative min-w-0 flex-1"><Search aria-hidden="true" size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)]"/><Input id="team-search" name="q" defaultValue={initialQuery.query} placeholder="Search members" className="pl-9"/></div><Button type="submit" variant="secondary" size="sm">Search</Button>{hasFilters&&<Button type="button" variant="ghost" size="sm" onClick={clearFilters}>Clear filters</Button>}</form>}
        <div className="ml-auto flex flex-wrap items-center justify-end gap-2"><Link href="/settings" className="touch-target inline-flex min-h-11 items-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] px-3 text-xs font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]">Organisation settings</Link>{canInvite&&<Button ref={inviteButtonRef} type="button" size="sm" onClick={()=>setInviteDialogOpen(true)}><UserPlus aria-hidden="true" size={16}/>Invite member</Button>}</div>
      </div>
    </header>
    <div className={cn('flex min-h-0 flex-1 flex-col', selected&&view==='members'&&'lg:flex-row')}><section className={cn('flex min-h-0 flex-1 flex-col',selected&&view==='members'&&'hidden lg:flex lg:basis-3/5')}>{view==='invitations'&&canInvite?<InvitationCollection invitations={invitations} stateFilter={invitationState} onStateChange={changeInvitationState}/>:collection}</section>{selected&&view==='members'&&<MemberInspector member={selected} onBack={clearSelection}/>}</div>
    {canInvite&&<InviteMemberDialog open={inviteOpen} onOpenChange={setInviteDialogOpen} canInviteAdmin={capabilities.includes('team.invite.admin')}/>}
  </div>
}
