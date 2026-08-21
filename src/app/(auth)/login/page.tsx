'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { signIn, type SignInState } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'

export default function LoginPage() {
  const initialState: SignInState = { error: null }
  const [state, formAction, isPending] = useActionState(signIn, initialState)

  return (
    <>
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-[var(--text-primary)]">Welcome back</h1>
        <p className="mt-1 text-sm text-[var(--text-muted)]">
          Sign in to your GST DMS workspace
        </p>
      </div>

      <form action={formAction} className="flex flex-col gap-4">
        <FormField label="Email address" required>
          <Input
            id="email"
            name="email"
            type="email"
            placeholder="you@lawfirm.com"
            autoComplete="email"
            required
            disabled={isPending}
          />
        </FormField>

        <FormField label="Password" required>
          <Input
            id="password"
            name="password"
            type="password"
            placeholder="Enter your password"
            autoComplete="current-password"
            required
            disabled={isPending}
          />
        </FormField>

        {state.error && (
          <div className="rounded-[var(--radius-md)] bg-[var(--danger-muted)] border border-[color-mix(in_srgb,var(--danger)_30%,transparent)] px-4 py-3 text-sm text-[var(--danger)] animate-fade-in">
            {state.error}
          </div>
        )}

        <Button
          type="submit"
          size="lg"
          className="mt-1 w-full"
          loading={isPending}
        >
          {isPending ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-[var(--text-muted)]">
        Don&apos;t have an account?{' '}
        <Link href="/signup" className="text-[var(--primary)] hover:underline font-medium">
          Create one
        </Link>
      </p>
    </>
  )
}
