'use client'

import { useState, useTransition } from 'react'
import { UserPlus, Mail, User, UserMinus, Crown, Building2, Users, X } from 'lucide-react'
import { inviteMember, deleteInvite, resendInvite } from '@/lib/actions/org'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Avatar } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { toast } from 'sonner'

interface Member {
  membership_id: string
  role: 'admin' | 'associate' | 'viewer'
  email: string | null
  full_name: string | null
  professional_title: string | null
  is_owner: boolean
  state: 'active' | 'suspended' | 'removed'
  joined_at: string
}

interface Invite {
  id: string
  invited_email: string
  role: 'admin' | 'associate' | 'viewer'
  status: string
  expires_at: string
}

interface SettingsClientProps {
  orgId: string
  orgName: string
  currentMembershipId: string
  currentUserRole: string
  capabilities: string[]
  members: Member[]
  pendingInvites: Invite[]
}

const roleIcon: Record<string, React.ElementType> = {
  admin: Crown,
  associate: User,
  viewer: UserMinus,
}

export function SettingsClient({
  orgId,
  orgName,
  currentMembershipId,
  currentUserRole,
  capabilities,
  members,
  pendingInvites,
}: SettingsClientProps) {
  const [inviteOpen, setInviteOpen] = useState(false)
  const [inviteError, setInviteError] = useState<string | null>(null)
  const [inviteSuccess, setInviteSuccess] = useState(false)
  const [isPending, startTransition] = useTransition()
  

  function handleInvite(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setInviteError(null)
    setInviteSuccess(false)
    const formData = new FormData(e.currentTarget)

    startTransition(async () => {
      const result = await inviteMember(formData)
      if (result?.error) {
        setInviteError(result.error)
      } else {
        setInviteSuccess(true)
        toast.success('Invitation sent successfully!')
        ;(e.target as HTMLFormElement).reset()
        setInviteOpen(false)
      }
    })
  }

  function handleRevokeInvite(inviteId: string) {
    startTransition(async () => {
      const result = await deleteInvite(inviteId)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success('Invite revoked.')
      }
    })
  }

  function handleResendInvite(inviteId: string) {
    startTransition(async () => {
      const result = await resendInvite(inviteId)
      if (result?.error) toast.error(result.error)
      else toast.success('Invitation resent.')
    })
  }

  return (
    <div className="flex-1 flex flex-col min-h-0 overflow-y-auto custom-scrollbar animate-fade-in -mt-2">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Settings' }]} />

      <div className="max-w-4xl w-full mx-auto space-y-4 pb-12">
        {/* Organisation Info Card */}
        <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 shadow-xs">
          <div className="flex items-center gap-3 mb-4 pb-3 border-b border-[var(--border)]">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--primary)]/10 text-[var(--primary)] border border-[var(--primary)]/20 shrink-0">
              <Building2 size={16} />
            </div>
            <div>
              <h2 className="text-base font-bold text-[var(--text-primary)] leading-tight">Organisation Details</h2>
              <p className="text-[11px] text-[var(--text-muted)]">Workspace profile</p>
            </div>
          </div>

          <div className="flex items-center gap-4 text-sm">
            <div className="flex-1 px-3 py-2 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex justify-between items-center">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider">Organisation Name</span>
              <span className="font-semibold text-[var(--text-primary)]">{orgName}</span>
            </div>
            <div className="flex-1 px-3 py-2 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex justify-between items-center">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider">Active Members</span>
              <span className="font-semibold text-[var(--text-primary)]">{members.length} member{members.length !== 1 ? 's' : ''}</span>
            </div>
          </div>
        </div>

        {/* Team Members Card */}
        <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 shadow-xs">
          <div className="flex items-center justify-between mb-4 pb-3 border-b border-[var(--border)]">
            <div className="flex items-center gap-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--primary)] border border-[color-mix(in_srgb,var(--primary)_20%,transparent)] shrink-0">
                <Users size={16} className="text-[var(--primary)]" />
              </div>
              <div>
                <h2 className="text-base font-bold text-[var(--text-primary)] leading-tight">Team Members</h2>
                <p className="text-[11px] text-[var(--text-muted)]">Manage access</p>
              </div>
            </div>

            {(capabilities.includes('team.invite.standard') || capabilities.includes('team.invite.admin')) && (
              <Button
                size="sm"
                onClick={() => { setInviteOpen(true); setInviteError(null); setInviteSuccess(false) }}
                className="h-7 px-3 text-[11px] gap-1.5"
              >
                <UserPlus size={12} />
                Invite
              </Button>
            )}
          </div>

          <div className="space-y-1.5">
            {members.map((member) => {
              const RoleIcon = roleIcon[member.role] ?? User
              const isTargetOwner = member.is_owner

              return (
                <div
                  key={member.membership_id}
                  className="flex items-center justify-between py-1.5 px-3 rounded-lg hover:bg-[var(--bg)] transition-colors group"
                >
                  <div className="flex items-center gap-3 min-w-0 flex-1">
                    <Avatar
                      name={member.full_name || member.email || 'Team member'}
                      size="sm"
                    />
                    <div className="flex flex-col min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-[var(--text-primary)] truncate leading-tight">
                          {member.full_name ?? member.email ?? 'Team member'}
                        </span>
                        {isTargetOwner && (
                          <span className="text-[10px] font-medium text-[var(--warning)] bg-[var(--warning-muted)] px-1.5 py-0.5 rounded-[var(--radius-sm)]">Owner</span>
                        )}
                      </div>
                      {(member.professional_title || member.email) && (
                        <span className="text-[11px] text-[var(--text-muted)] truncate leading-none mt-0.5">{member.professional_title ?? member.email}</span>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-3">
                    <span className={`inline-flex items-center gap-1 text-[11px] font-medium ${
                      member.role === 'admin'
                        ? 'text-[var(--warning)]'
                        : 'text-[var(--text-secondary)]'
                    }`}>
                      <RoleIcon size={12} />
                      <span className="capitalize">{member.role}</span>
                    </span>

                    <div className="w-6" />
                  </div>
                </div>
              )
            })}
          </div>

          {/* Pending invites */}
          {pendingInvites.length > 0 && (
            <div className="mt-4 pt-3 border-t border-[var(--border)]">
              <h3 className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 px-3">
                Pending Invitations ({pendingInvites.length})
              </h3>
              <div className="space-y-1">
                {pendingInvites.map((invite) => (
                  <div
                    key={invite.id}
                    className="flex items-center justify-between py-1.5 px-3 rounded-lg hover:bg-[var(--bg)] transition-colors group"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <div className="flex h-7 w-7 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--warning-muted)] text-[var(--warning)] shrink-0">
                        <Mail size={12} />
                      </div>
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-xs font-medium text-[var(--text-primary)] truncate leading-tight">{invite.invited_email}</span>
                        <span className="text-[10px] text-[var(--text-muted)] leading-none mt-0.5">
                          {invite.status === 'rejected' ? 'Rejected' : `Expires ${new Date(invite.expires_at).toLocaleDateString()}`}
                        </span>
                      </div>
                    </div>

                    <div className="flex items-center gap-3">
                      <span className={`text-[10px] font-medium capitalize ${
                        invite.status === 'rejected' 
                          ? 'text-[var(--danger)]'
                          : 'text-[var(--warning)]'
                      }`}>
                        {invite.status}
                      </span>
                      {invite.status === 'pending' && (capabilities.includes('team.invite.standard') || capabilities.includes('team.invite.admin')) ? (
                        <Button variant="outline" size="sm" onClick={() => handleResendInvite(invite.id)} disabled={isPending} className="h-7 px-2 text-[10px]">
                          Resend invitation
                        </Button>
                      ) : null}
                      {invite.status === 'pending' && (capabilities.includes('team.invite.standard') || capabilities.includes('team.invite.admin')) ? (
                        <Button
                          size="icon"
                          variant="ghost"
                          onClick={() => handleRevokeInvite(invite.id)}
                          disabled={isPending}
                          className="h-6 w-6 text-[var(--text-muted)] hover:text-[var(--danger)] hover:bg-[var(--danger-muted)] opacity-0 group-hover:opacity-100 transition-all"
                          title="Revoke Invite"
                        >
                          <X size={14} />
                        </Button>
                      ) : (
                        <div className="w-6" /> // spacer
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Invite dialog */}
      <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
        <DialogContent className="sm:max-w-md bg-[var(--surface)] border border-[var(--border)] text-[var(--text-primary)]">
          <DialogHeader>
            <DialogTitle className="text-lg font-bold text-[var(--text-primary)]">Invite Team Member</DialogTitle>
            <DialogDescription className="text-xs text-[var(--text-muted)]">
              Send an email invitation to add a new colleague to {orgName}.
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={handleInvite} className="flex flex-col gap-4 mt-2">
            <FormField label="Email address" required error={inviteError ?? undefined}>
              <Input
                id="invite-email"
                name="email"
                type="email"
                placeholder="colleague@lawfirm.com"
                required
                autoFocus
                disabled={isPending}
                className="bg-[var(--bg)] border-[var(--border-strong)] text-[var(--text-primary)]"
              />
            </FormField>

            <FormField label="Role">
              <select
                id="invite-role"
                name="role"
                defaultValue="associate"
                disabled={isPending}
                className="w-full h-10 px-3.5 rounded-md text-sm bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none transition-all cursor-pointer"
              >
                <option value="associate">Associate — can view and edit</option>
                <option value="viewer">Viewer — read-only access</option>
                {capabilities.includes('team.invite.admin') && <option value="admin">Admin — full access</option>}
              </select>
            </FormField>

            <DialogFooter className="mt-2">
              <Button variant="outline" type="button" onClick={() => setInviteOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={isPending} className="bg-[var(--primary)] text-white">
                {isPending ? 'Sending...' : 'Send Invite'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

    </div>
  )
}
