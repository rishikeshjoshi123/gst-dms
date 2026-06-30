'use client'

import { useState, useTransition } from 'react'
import { Building2, KeyRound, ArrowRight } from 'lucide-react'
import { createOrganisation, acceptInvite } from '@/lib/actions/org'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'
import { cn } from '@/lib/utils'

type Mode = 'choose' | 'create' | 'invite'

export default function OnboardingPage() {
  const [mode, setMode] = useState<Mode>('choose')
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  function handleCreateOrg(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)
    startTransition(async () => {
      const result = await createOrganisation(formData)
      if (result?.error) setError(result.error)
    })
  }

  function handleAcceptInvite(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const token = (e.currentTarget.elements.namedItem('token') as HTMLInputElement)?.value?.trim()
    if (!token) { setError('Please enter an invite token.'); return }
    startTransition(async () => {
      const result = await acceptInvite(token)
      if (result?.error) setError(result.error)
    })
  }

  return (
    <div className="animate-fade-in">
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-[--text-primary]">Set up your workspace</h1>
        <p className="mt-1 text-sm text-[--text-muted]">
          Create a new organisation or join an existing one
        </p>
      </div>

      {/* Choose mode */}
      {mode === 'choose' && (
        <div className="flex flex-col gap-3">
          <button
            onClick={() => setMode('create')}
            className={cn(
              'group flex items-start gap-4 p-5 rounded-[--radius-lg]',
              'border border-[--border-default] bg-[--bg-overlay]',
              'hover:border-[--accent]/50 hover:bg-[--accent-muted]',
              'transition-all duration-[--duration-base] text-left cursor-pointer'
            )}
          >
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[--radius-md] bg-[--accent-muted] group-hover:bg-[--accent] transition-colors">
              <Building2 size={20} className="text-[--accent] group-hover:text-white transition-colors" />
            </div>
            <div>
              <p className="font-semibold text-[--text-primary]">Create a new organisation</p>
              <p className="text-sm text-[--text-muted] mt-0.5">
                Start a fresh workspace for your law firm or practice
              </p>
            </div>
            <ArrowRight size={18} className="ml-auto self-center text-[--text-muted] group-hover:text-[--text-primary] transition-colors shrink-0" />
          </button>

          <button
            onClick={() => setMode('invite')}
            className={cn(
              'group flex items-start gap-4 p-5 rounded-[--radius-lg]',
              'border border-[--border-default] bg-[--bg-overlay]',
              'hover:border-[--accent]/50 hover:bg-[--accent-muted]',
              'transition-all duration-[--duration-base] text-left cursor-pointer'
            )}
          >
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[--radius-md] bg-[--bg-muted] group-hover:bg-[--accent-muted] transition-colors">
              <KeyRound size={20} className="text-[--text-muted] group-hover:text-[--accent] transition-colors" />
            </div>
            <div>
              <p className="font-semibold text-[--text-primary]">Join with an invite</p>
              <p className="text-sm text-[--text-muted] mt-0.5">
                Enter an invite token sent to your email
              </p>
            </div>
            <ArrowRight size={18} className="ml-auto self-center text-[--text-muted] group-hover:text-[--text-primary] transition-colors shrink-0" />
          </button>
        </div>
      )}

      {/* Create org */}
      {mode === 'create' && (
        <div className="animate-fade-in">
          <button
            onClick={() => { setMode('choose'); setError(null) }}
            className="mb-5 text-sm text-[--text-muted] hover:text-[--text-primary] flex items-center gap-1 transition-colors"
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

      {/* Accept invite */}
      {mode === 'invite' && (
        <div className="animate-fade-in">
          <button
            onClick={() => { setMode('choose'); setError(null) }}
            className="mb-5 text-sm text-[--text-muted] hover:text-[--text-primary] flex items-center gap-1 transition-colors"
          >
            ← Back
          </button>
          <form onSubmit={handleAcceptInvite} className="flex flex-col gap-4">
            <FormField
              label="Invite token"
              required
              error={error ?? undefined}
            >
              <Input
                id="token"
                name="token"
                type="text"
                placeholder="Paste your invite token here"
                autoFocus
                required
                disabled={isPending}
              />
            </FormField>
            <p className="text-xs text-[--text-muted]">
              Check your invitation email for the token, or ask your admin to resend it.
            </p>
            <Button type="submit" size="lg" className="w-full mt-1" loading={isPending}>
              {isPending ? 'Joining…' : 'Join organisation'}
            </Button>
          </form>
        </div>
      )}
    </div>
  )
}
