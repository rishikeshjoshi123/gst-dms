'use client'

import { useCallback, useRef, useState, useTransition } from 'react'
import { Building2, LogOut, Mail, X } from 'lucide-react'
import { acceptInvite, createOrganisation, rejectInvite } from '@/lib/actions/org'
import { signOut } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'
import { FormField } from '@/components/ui/label'
import { Input } from '@/components/ui/input'

type PendingInvite = { id: string; role: string; orgName: string }

export function OnboardingClient({
  invites: initialInvites,
  invalidInvite,
}: {
  invites: PendingInvite[]
  invalidInvite: boolean
}) {
  const [invites, setInvites] = useState(initialInvites)
  const [error, setError] = useState<string | null>(
    invalidInvite ? 'That invitation is unavailable. Review the invitations linked to your verified email below.' : null,
  )
  const creationIdempotencyKey = useRef<HTMLInputElement | null>(null)
  const [isPending, startTransition] = useTransition()

  const setCreationIdempotencyKey = useCallback((input: HTMLInputElement | null) => {
    creationIdempotencyKey.current = input
    if (input && !input.value) input.value = crypto.randomUUID()
  }, [])

  function accept(inviteId: string) {
    setError(null)
    startTransition(async () => {
      const result = await acceptInvite(inviteId)
      if (result?.error) setError(result.error)
    })
  }

  function reject(inviteId: string) {
    setError(null)
    startTransition(async () => {
      const result = await rejectInvite(inviteId)
      if (result?.error) return setError(result.error)
      setInvites((current) => current.filter((invite) => invite.id !== inviteId))
    })
  }

  function create(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError(null)
    const formData = new FormData(event.currentTarget)
    startTransition(async () => {
      const result = await createOrganisation(formData)
      if (result?.error) setError(result.error)
    })
  }

  return (
    <div className="space-y-7">
      <header className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-bold text-[var(--text-primary)]">Set up your workspace</h1>
          <p className="mt-1 text-sm leading-relaxed text-[var(--text-muted)]">
            Join an organisation that invited you, or create a new organisation.
          </p>
        </div>
        <Button variant="outline" size="sm" className="shrink-0" onClick={() => startTransition(() => signOut())} disabled={isPending}>
          <LogOut aria-hidden="true" size={14} /><span className="hidden sm:inline">Log out</span>
        </Button>
      </header>

      {error && <p role="alert" className="rounded-[var(--radius-md)] border border-[var(--danger)] bg-[var(--danger-muted)] p-3 text-sm text-[var(--danger)]">{error}</p>}

      <section aria-labelledby="pending-invitations-heading" className="space-y-3">
        <div>
          <h2 id="pending-invitations-heading" className="text-base font-semibold text-[var(--text-primary)]">Pending invitations</h2>
          <p className="mt-1 text-sm text-[var(--text-muted)]">Invitations for your verified email appear here.</p>
        </div>
        {invites.length === 0 ? (
          <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)] p-4">
            <p className="text-sm font-medium text-[var(--text-primary)]">No pending invitations</p>
            <p className="mt-1 text-sm text-[var(--text-muted)]">You can create an organisation below and invite your team later.</p>
          </div>
        ) : invites.map((invite) => (
          <article key={invite.id} className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-4">
            <div className="flex min-w-0 items-start gap-3">
              <span className="flex size-11 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]"><Mail aria-hidden="true" size={18} /></span>
              <div className="min-w-0 flex-1">
                <h3 className="break-words text-sm font-semibold text-[var(--text-primary)]">{invite.orgName}</h3>
                <p className="mt-1 text-xs text-[var(--text-muted)]">Invited as {invite.role}</p>
              </div>
            </div>
            <div className="mt-3 flex flex-wrap justify-end gap-2">
              <Button variant="outline" onClick={() => reject(invite.id)} disabled={isPending} aria-label={`Decline invitation to ${invite.orgName}`}>
                <X aria-hidden="true" size={14} />Decline
              </Button>
              <Button onClick={() => accept(invite.id)} disabled={isPending} loading={isPending}>Accept invitation</Button>
            </div>
          </article>
        ))}
      </section>

      <section aria-labelledby="create-organisation-heading" className="border-t border-[var(--border)] pt-6">
        <div className="mb-4 flex items-start gap-3">
          <span className="flex size-11 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-secondary)]"><Building2 aria-hidden="true" size={18} /></span>
          <div>
            <h2 id="create-organisation-heading" className="text-base font-semibold text-[var(--text-primary)]">Create organisation</h2>
            <p className="mt-1 text-sm text-[var(--text-muted)]">Start a separate workspace only when none of the invitations above is the organisation you need.</p>
          </div>
        </div>
        <form onSubmit={create} className="space-y-4">
          <input ref={setCreationIdempotencyKey} type="hidden" name="idempotency_key" />
          <FormField htmlFor="organisation_name" label="Organisation name" required hint="Use the name your team will recognise.">
            <Input id="organisation_name" name="name" required minLength={2} maxLength={200} autoComplete="organization" disabled={isPending} />
          </FormField>
          <Button type="submit" size="lg" className="w-full sm:w-auto" loading={isPending} disabled={isPending}>Create organisation</Button>
        </form>
      </section>
    </div>
  )
}
