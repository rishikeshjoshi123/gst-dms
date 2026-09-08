'use client'

import { useEffect, useState, useTransition } from 'react'
import { LogOut, Mail, X } from 'lucide-react'
import { toast } from 'sonner'
import { acceptInvite, getMyPendingInvites, rejectInvite } from '@/lib/actions/org'
import { signOut } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'

interface PendingInvite {
  id: string
  role: string
  orgName: string
}

export default function OnboardingPage() {
  const [invites, setInvites] = useState<PendingInvite[]>([])
  const [loadingInvites, setLoadingInvites] = useState(true)
  const [isPending, startTransition] = useTransition()

  useEffect(() => {
    let cancelled = false
    void getMyPendingInvites()
      .then((data) => {
        if (!cancelled) setInvites(data)
      })
      .catch(() => {
        if (!cancelled) toast.error('Invitations could not be loaded. Refresh and try again.')
      })
      .finally(() => {
        if (!cancelled) setLoadingInvites(false)
      })
    return () => {
      cancelled = true
    }
  }, [])

  function handleAcceptInvite(inviteId: string) {
    startTransition(async () => {
      const result = await acceptInvite(inviteId)
      if (result?.error) toast.error(result.error)
    })
  }

  function handleRejectInvite(inviteId: string) {
    startTransition(async () => {
      const result = await rejectInvite(inviteId)
      if (result?.error) {
        toast.error(result.error)
        return
      }
      setInvites((current) => current.filter((invite) => invite.id !== inviteId))
      toast.success('Invitation declined.')
    })
  }

  function handleLogout() {
    startTransition(async () => {
      await signOut()
    })
  }

  return (
    <div className="animate-fade-in">
      <div className="mb-7 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)]">Join your organisation</h1>
          <p className="mt-1 text-sm text-[var(--text-muted)]">
            CaseChain pilot access is available through an organisation invitation.
          </p>
        </div>
        <Button
          variant="outline"
          size="sm"
          className="shrink-0 text-[var(--text-secondary)] transition-colors hover:border-[var(--danger)] hover:bg-[var(--danger-muted)] hover:text-[var(--danger)]"
          onClick={handleLogout}
          disabled={isPending}
        >
          <LogOut size={14} className="mr-1.5" />
          Log out
        </Button>
      </div>

      {loadingInvites ? (
        <p className="py-8 text-center text-sm text-[var(--text-muted)]" role="status">
          Checking invitations…
        </p>
      ) : invites.length === 0 ? (
        <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-5">
          <h2 className="font-semibold text-[var(--text-primary)]">Invitation required</h2>
          <p className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
            Open the invitation link sent by your organisation administrator. If the link has expired, ask them to send a new invitation.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Pending invitations
          </h2>
          {invites.map((invite) => (
            <div key={invite.id} className="flex items-center justify-between gap-3 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-4">
              <div className="flex min-w-0 items-center gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[var(--accent-muted)]">
                  <Mail size={16} className="text-[var(--accent)]" />
                </div>
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-[var(--text-primary)]">{invite.orgName}</p>
                  <p className="text-xs text-[var(--text-muted)]">Invited as {invite.role}</p>
                </div>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <Button
                  size="icon"
                  variant="outline"
                  className="h-11 w-11 border-[color-mix(in_srgb,var(--danger)_30%,transparent)] text-[var(--danger)] hover:bg-[var(--danger-muted)]"
                  onClick={() => handleRejectInvite(invite.id)}
                  disabled={isPending}
                  title="Decline invitation"
                  aria-label={`Decline invitation to ${invite.orgName}`}
                >
                  <X size={14} />
                </Button>
                <Button
                  className="h-11 px-3"
                  onClick={() => handleAcceptInvite(invite.id)}
                  disabled={isPending}
                  loading={isPending}
                >
                  Accept invitation
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
