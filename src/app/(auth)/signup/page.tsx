'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { signUp } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'

export default function SignupPage() {
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)

    const password = formData.get('password') as string
    const confirm = formData.get('confirm_password') as string
    if (password !== confirm) {
      setError('Passwords do not match.')
      return
    }

    startTransition(async () => {
      const result = await signUp(formData)
      if (result?.error) setError(result.error)
    })
  }

  return (
    <>
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-[--text-primary]">Create your account</h1>
        <p className="mt-1 text-sm text-[--text-muted]">
          Get started with GST Litigation DMS
        </p>
      </div>

      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <FormField label="Full name" required>
          <Input
            id="full_name"
            name="full_name"
            type="text"
            placeholder="John Doe"
            autoComplete="name"
            required
            minLength={2}
            disabled={isPending}
          />
        </FormField>

        <FormField label="Work email" required>
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
            placeholder="Min. 8 characters"
            autoComplete="new-password"
            required
            minLength={8}
            disabled={isPending}
          />
        </FormField>

        <FormField label="Confirm password" required>
          <Input
            id="confirm_password"
            name="confirm_password"
            type="password"
            placeholder="Repeat your password"
            autoComplete="new-password"
            required
            disabled={isPending}
          />
        </FormField>

        {error && (
          <div className="rounded-[--radius-md] bg-[--danger-muted] border border-[--danger]/30 px-4 py-3 text-sm text-[--danger] animate-fade-in">
            {error}
          </div>
        )}

        <Button
          type="submit"
          size="lg"
          className="mt-1 w-full"
          loading={isPending}
        >
          {isPending ? 'Creating account…' : 'Create account'}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-[--text-muted]">
        Already have an account?{' '}
        <Link href="/login" className="text-[var(--primary)] hover:underline font-medium">
          Sign in
        </Link>
      </p>

      <p className="mt-4 text-center text-xs text-[--text-disabled]">
        By signing up, you agree to keep client data confidential.
      </p>
    </>
  )
}
