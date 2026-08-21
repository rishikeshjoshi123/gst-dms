'use client'

import { useState, useTransition, useEffect } from 'react'
import { Building2, Mail, ArrowRight, LogOut, X } from 'lucide-react'
import { createOrganisation, acceptInvite, rejectInvite, getMyPendingInvites } from '@/lib/actions/org'
import { signOut } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
import { cn } from '@/lib/utils'
import { toast } from 'sonner'

type Mode = 'choose' | 'create'

interface PendingInvite {
  id: string
  role: string
  orgName: string
}

export default function OnboardingPage() {
  const [mode, setMode] = useState<Mode>('choose')
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  
  const [invites, setInvites] = useState<PendingInvite[]>([])
  const [loadingInvites, setLoadingInvites] = useState(true)

  useEffect(() => {
    async function fetchInvites() {
      try {
        const data = await getMyPendingInvites()
        setInvites(data)
      } catch (err) {
        console.error(err)
      } finally {
        setLoadingInvites(false)
      }
    }
    fetchInvites()
  }, [])

  function handleCreateOrg(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    startTransition(async () => {
      const result = await createOrganisation(formData)
      if (result?.error) setError(result.error)
    })
  }

  function handleAcceptInvite(inviteId: string) {
    setError(null)
    startTransition(async () => {
      const result = await acceptInvite(inviteId)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success('Successfully joined the organization.')
      }
    })
  }

  function handleRejectInvite(inviteId: string) {
    startTransition(async () => {
      const result = await rejectInvite(inviteId)
      if (result?.error) {
        toast.error(result.error)
      } else {
        toast.success('Invite rejected.')
        setInvites(invites.filter(inv => inv.id !== inviteId))
      }
    })
  }

  function handleLogout() {
    startTransition(async () => {
      await signOut()
    })
  }

  return (
    <div className="animate-fade-in">
      <div className="flex items-start justify-between mb-7 gap-4">
        <div>
          <h1 className="text-2xl font-bold text-[var(--text-primary)]">Set up your workspace</h1>
          <p className="mt-1 text-sm text-[var(--text-muted)]">
            Create a new organisation or join an existing one
          </p>
        </div>
        <Button 
          variant="outline" 
          size="sm" 
          className="text-[var(--text-secondary)] hover:text-[var(--danger)] hover:border-[var(--danger)] hover:bg-[var(--danger-muted)] transition-colors shrink-0"
          onClick={handleLogout}
          disabled={isPending}
        >
          <LogOut size={14} className="mr-1.5" />
          Log out
        </Button>
      </div>

      {/* Choose mode & Pending Invites */}
      {mode === 'choose' && (
        <div className="flex flex-col gap-6">
          
          {/* Pending Invites Section */}
          {!loadingInvites && invites.length > 0 && (
            <div className="space-y-3">
              <h2 className="text-sm font-semibold text-[var(--text-muted)] uppercase tracking-wider">Pending Invites</h2>
              <div className="space-y-3">
                {invites.map(invite => (
                  <div key={invite.id} className="flex items-center justify-between p-4 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg-overlay)]">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-full bg-[var(--accent-muted)] flex items-center justify-center shrink-0">
                        <Mail size={16} className="text-[var(--accent)]" />
                      </div>
                      <div>
                        <p className="font-semibold text-[var(--text-primary)] text-sm">{invite.orgName}</p>
                        <p className="text-xs text-[var(--text-muted)]">Invited you as <span className="font-medium">{invite.role}</span></p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Button 
                        size="icon" 
                        variant="outline" 
                        className="h-11 w-11 sm:h-8 sm:w-8 text-[var(--danger)] hover:bg-[var(--danger-muted)] border-[color-mix(in_srgb,var(--danger)_30%,transparent)]"
                        onClick={() => handleRejectInvite(invite.id)}
                        disabled={isPending}
                        title="Reject Invite"
                        aria-label={`Reject invitation to ${invite.orgName}`}
                      >
                        <X size={14} />
                      </Button>
                      <Button 
                        size="sm" 
                        className="h-11 px-3 sm:h-8"
                        onClick={() => handleAcceptInvite(invite.id)}
                        disabled={isPending}
                        loading={isPending}
                      >
                        Accept
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="space-y-3">
            <h2 className="text-sm font-semibold text-[var(--text-muted)] uppercase tracking-wider">
              {invites.length > 0 ? 'Or Create Your Own' : 'Get Started'}
            </h2>
            <button
              onClick={() => setMode('create')}
              type="button"
              className={cn(
                'group flex items-start gap-4 p-5 rounded-[var(--radius-md)] w-full',
                'border border-[var(--border)] bg-[var(--bg-overlay)]',
                'hover:border-[var(--accent)] hover:bg-[var(--accent-muted)]',
                'transition-all duration-[var(--duration-base)] text-left cursor-pointer'
              )}
            >
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-md)] bg-[var(--accent-muted)] group-hover:bg-[var(--accent)] transition-colors">
                <Building2 size={20} className="text-[var(--accent)] group-hover:text-[var(--on-accent)] transition-colors" />
              </div>
              <div>
                <p className="font-semibold text-[var(--text-primary)]">Create a new organisation</p>
                <p className="text-sm text-[var(--text-muted)] mt-0.5">
                  Start a fresh workspace for your law firm or practice
                </p>
              </div>
              <ArrowRight size={18} className="ml-auto self-center text-[var(--text-muted)] group-hover:text-[var(--text-primary)] transition-colors shrink-0" />
            </button>
          </div>
        </div>
      )}

      {/* Create org */}
      {mode === 'create' && (
        <div className="animate-fade-in">
          <button
            onClick={() => { setMode('choose'); setError(null) }}
            type="button"
            className="mb-5 flex min-h-11 items-center gap-1 text-sm text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)]"
          >
            ← Back
          </button>
          <form onSubmit={handleCreateOrg} className="flex flex-col gap-4">
            <FormField
              label="Organisation name"
              required
              error={error ?? undefined}
            >
              <Input
                id="name"
                name="name"
                type="text"
                placeholder="e.g. Tax Advocate Associates"
                autoFocus
                required
                minLength={2}
                maxLength={120}
                disabled={isPending}
              />
            </FormField>
            <Button type="submit" size="lg" className="w-full mt-1" loading={isPending}>
              {isPending ? 'Creating workspace…' : 'Create workspace'}
            </Button>
          </form>
        </div>
      )}
    </div>
  )
}
