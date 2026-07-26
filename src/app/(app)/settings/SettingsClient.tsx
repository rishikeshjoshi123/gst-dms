'use client'

import { useState, useTransition } from 'react'
import { UserPlus, Mail, ShieldCheck, User, UserMinus, Crown, Building2, Users, Settings as SettingsIcon } from 'lucide-react'
import { inviteMember } from '@/lib/actions/org'
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

interface Member {
  user_id: string
  role: 'admin' | 'associate' | 'viewer'
  email: string
  full_name: string | null
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
  members: Member[]
  pendingInvites: Invite[]
  currentUserRole: string
}

const roleIcon: Record<string, React.ElementType> = {
  admin: Crown,
  associate: User,
  viewer: UserMinus,
}

export function SettingsClient({
  orgId,
  orgName,
  members,
  pendingInvites,
  currentUserRole,
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
        ;(e.target as HTMLFormElement).reset()
      }
    })
  }

  return (
    <div className="flex-1 flex flex-col min-h-0 overflow-y-auto custom-scrollbar animate-fade-in -mt-2">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Settings' }]} />

      <div className="max-w-4xl w-full mx-auto space-y-6 pb-12">
        {/* Organisation Info Card */}
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 shadow-xs">
          <div className="flex items-center gap-4 mb-6 pb-4 border-b border-[var(--border)]">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-[var(--primary)]/10 text-[var(--primary)] border border-[var(--primary)]/20 shrink-0">
              <Building2 size={24} />
            </div>
            <div>
              <h2 className="text-lg font-bold text-[var(--text-primary)]">Organisation Details</h2>
              <p className="text-xs text-[var(--text-muted)]">Active workspace profile and membership overview</p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl bg-[var(--bg)] border border-[var(--border)] flex flex-col gap-1">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider">Organisation Name</span>
              <span className="text-base font-semibold text-[var(--text-primary)]">{orgName}</span>
            </div>
            <div className="p-4 rounded-xl bg-[var(--bg)] border border-[var(--border)] flex flex-col gap-1">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider">Active Members</span>
              <span className="text-base font-semibold text-[var(--text-primary)]">{members.length} member{members.length !== 1 ? 's' : ''}</span>
            </div>
          </div>
        </div>

        {/* Team Members Card */}
        <div className="rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-6 shadow-xs">
          <div className="flex items-center justify-between mb-6 pb-4 border-b border-[var(--border)]">
            <div className="flex items-center gap-4">
              <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20 shrink-0">
                <Users size={24} />
              </div>
              <div>
                <h2 className="text-lg font-bold text-[var(--text-primary)]">Team Members</h2>
                <p className="text-xs text-[var(--text-muted)]">People with access to this organisation</p>
              </div>
            </div>

            {currentUserRole === 'admin' && (
              <button
                type="button"
                onClick={() => { setInviteOpen(true); setInviteError(null); setInviteSuccess(false) }}
                className="group relative inline-flex items-center gap-2 px-4 py-2 rounded-full text-xs font-semibold text-white bg-gradient-to-r from-blue-600 via-indigo-600 to-blue-700 hover:from-blue-500 hover:via-indigo-500 hover:to-blue-600 shadow-md shadow-blue-500/25 hover:shadow-lg hover:shadow-blue-500/40 hover:scale-[1.03] active:scale-[0.97] transition-all duration-200 cursor-pointer border border-blue-400/30"
              >
                <UserPlus size={14} className="transition-transform duration-200 group-hover:scale-110" />
                <span>Invite Member</span>
              </button>
            )}
          </div>

          <div className="space-y-3">
            {members.map((member) => {
              const RoleIcon = roleIcon[member.role] ?? User
              return (
                <div
                  key={member.user_id}
                  className="flex items-center justify-between p-3.5 px-4 rounded-xl border border-[var(--border)] bg-[var(--bg)] hover:border-[var(--border-strong)] transition-all"
                >
                  <div className="flex items-center gap-3.5 min-w-0 flex-1">
                    <Avatar
                      name={member.full_name || member.email}
                      size="sm"
                    />
                    <div className="flex flex-col min-w-0 flex-1">
                      <span className="text-sm font-semibold text-[var(--text-primary)] truncate">
                        {member.full_name ?? member.email}
                      </span>
                      {member.full_name && (
                        <span className="text-xs text-[var(--text-muted)] truncate">{member.email}</span>
                      )}
                    </div>
                  </div>

                  <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold uppercase tracking-wider ${
                    member.role === 'admin'
                      ? 'bg-amber-500/10 text-amber-600 border border-amber-500/30'
                      : 'bg-[var(--surface-hover)] text-[var(--text-secondary)] border border-[var(--border)]'
                  }`}>
                    <RoleIcon size={12} />
                    {member.role}
                  </span>
                </div>
              )
            })}
          </div>

          {/* Pending invites */}
          {pendingInvites.length > 0 && (
            <div className="mt-6 pt-5 border-t border-[var(--border)]">
              <h3 className="text-xs font-bold uppercase tracking-wider text-[var(--text-muted)] mb-3">
                Pending Invitations ({pendingInvites.length})
              </h3>
              <div className="space-y-2.5">
                {pendingInvites.map((invite) => (
                  <div
                    key={invite.id}
                    className="flex items-center justify-between p-3 px-4 rounded-xl bg-[var(--bg)] border border-[var(--border)]"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-500/10 border border-amber-500/20 text-amber-600 shrink-0">
                        <Mail size={15} />
                      </div>
                      <div className="flex flex-col min-w-0 flex-1">
                        <span className="text-xs font-medium text-[var(--text-primary)] truncate">{invite.invited_email}</span>
                        <span className="text-[10px] text-[var(--text-muted)]">
                          Expires {new Date(invite.expires_at).toLocaleDateString()}
                        </span>
                      </div>
                    </div>

                    <span className="px-2.5 py-0.5 rounded-full text-[10px] font-bold uppercase tracking-wider bg-amber-500/10 text-amber-600 border border-amber-500/20">
                      Pending
                    </span>
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
                <option value="admin">Admin — full access</option>
              </select>
            </FormField>

            {inviteSuccess && (
              <div className="flex items-center gap-2 text-xs font-semibold text-emerald-600 bg-emerald-500/10 border border-emerald-500/20 rounded-lg p-3">
                <ShieldCheck size={16} />
                Invitation sent successfully!
              </div>
            )}

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
