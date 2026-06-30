'use client'

import { useState, useTransition } from 'react'
import { UserPlus, Mail, ShieldCheck, User, UserMinus, Crown } from 'lucide-react'
import { inviteMember } from '@/lib/actions/org'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
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

const roleVariant: Record<string, 'default' | 'warning' | 'muted'> = {
  admin:     'default',
  associate: 'muted',
  viewer:    'muted',
}

const roleIcon: Record<string, React.ElementType> = {
  admin:     Crown,
  associate: User,
  viewer:    UserMinus,
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
    <div className="max-w-3xl mx-auto px-8 py-8 space-y-8">
      {/* Page header */}
      <div className="animate-fade-in">
        <h1 className="text-2xl font-bold text-[--text-primary]">Settings</h1>
        <p className="mt-1 text-sm text-[--text-muted]">Manage your organisation and team</p>
      </div>

      {/* Org info */}
      <section className="animate-fade-in bg-[--bg-surface] rounded-[--radius-xl] border border-[--border-subtle] p-6">
        <h2 className="text-sm font-semibold text-[--text-primary] mb-4">Organisation</h2>
        <div className="flex items-center gap-4">
          <div className="flex h-12 w-12 items-center justify-center rounded-[--radius-lg] bg-[--accent-muted] text-lg font-bold text-[--accent]">
            {orgName.charAt(0).toUpperCase()}
          </div>
          <div>
            <p className="font-semibold text-[--text-primary]">{orgName}</p>
            <p className="text-xs text-[--text-muted]">{members.length} member{members.length !== 1 ? 's' : ''}</p>
          </div>
        </div>
      </section>

      {/* Members */}
      <section className="animate-fade-in bg-[--bg-surface] rounded-[--radius-xl] border border-[--border-subtle] p-6">
        <div className="flex items-center justify-between mb-5">
          <h2 className="text-sm font-semibold text-[--text-primary]">Members</h2>
          {currentUserRole === 'admin' && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => { setInviteOpen(true); setInviteError(null); setInviteSuccess(false) }}
            >
              <UserPlus size={14} />
              Invite member
            </Button>
          )}
        </div>

        <div className="space-y-3">
          {members.map((member) => {
            const RoleIcon = roleIcon[member.role] ?? User
            return (
              <div
                key={member.user_id}
                className="flex items-center gap-3 py-2.5 px-3 rounded-[--radius-md] hover:bg-[--bg-overlay] transition-colors"
              >
                <Avatar
                  name={member.full_name || member.email}
                  size="sm"
                />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-[--text-primary] truncate">
                    {member.full_name ?? member.email}
                  </p>
                  {member.full_name && (
                    <p className="text-xs text-[--text-muted] truncate">{member.email}</p>
                  )}
                </div>
                <Badge variant={roleVariant[member.role]}>
                  <RoleIcon size={10} />
                  {member.role}
                </Badge>
              </div>
            )
          })}
        </div>

        {/* Pending invites */}
        {pendingInvites.length > 0 && (
          <div className="mt-5 pt-5 border-t border-[--border-subtle]">
            <p className="text-xs font-semibold uppercase tracking-wider text-[--text-muted] mb-3">
              Pending invites
            </p>
            <div className="space-y-2">
              {pendingInvites.map((invite) => (
                <div
                  key={invite.id}
                  className="flex items-center gap-3 py-2.5 px-3 rounded-[--radius-md] bg-[--bg-overlay]"
                >
                  <div className="flex h-8 w-8 items-center justify-center rounded-full bg-[--bg-muted]">
                    <Mail size={14} className="text-[--text-muted]" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-[--text-secondary] truncate">{invite.invited_email}</p>
                    <p className="text-[10px] text-[--text-muted]">
                      Expires {new Date(invite.expires_at).toLocaleDateString('en-IN')}
                    </p>
                  </div>
                  <Badge variant="warning" dot>pending</Badge>
                </div>
              ))}
            </div>
          </div>
        )}
      </section>

      {/* Invite dialog */}
      <Dialog open={inviteOpen} onOpenChange={setInviteOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Invite team member</DialogTitle>
            <DialogDescription>
              They will receive an email with instructions to join {orgName}.
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={handleInvite} className="flex flex-col gap-4">
            <FormField label="Email address" required error={inviteError ?? undefined}>
              <Input
                id="invite-email"
                name="email"
                type="email"
                placeholder="colleague@lawfirm.com"
                required
                autoFocus
                disabled={isPending}
              />
            </FormField>

            <FormField label="Role">
              <select
                id="invite-role"
                name="role"
                defaultValue="associate"
                disabled={isPending}
                className="w-full h-10 px-3.5 rounded-[--radius-md] text-sm bg-[--bg-overlay] text-[--text-primary] border border-[--border-default] focus:border-[--accent] focus:ring-2 focus:ring-[--accent-ring] outline-none transition-all"
              >
                <option value="associate">Associate — can view and edit</option>
                <option value="viewer">Viewer — read-only access</option>
                <option value="admin">Admin — full access</option>
              </select>
            </FormField>

            {inviteSuccess && (
              <div className="flex items-center gap-2 text-sm text-[--success] bg-[--success-muted] rounded-[--radius-md] px-4 py-3 animate-fade-in">
                <ShieldCheck size={16} />
                Invitation sent successfully!
              </div>
            )}

            <DialogFooter>
              <Button variant="outline" type="button" onClick={() => setInviteOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" loading={isPending}>
                Send invite
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}
