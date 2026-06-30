'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { signIn } from '@/lib/actions/auth'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/label'

export default function LoginPage() {
  const [error, setError] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setError(null)
    const formData = new FormData(e.currentTarget)

    startTransition(async () => {
      const result = await signIn(formData)
      if (result?.error) setError(result.error)
    })
  }

  return (
    <>
      <div className="mb-7">
        <h1 className="text-2xl font-bold text-[--text-primary]">Welcome back</h1>
        <p className="mt-1 text-sm text-[--text-muted]">
          Sign in to your GST DMS workspace
        </p>
      </div>

      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
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
          {isPending ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-[--text-muted]">
        Don&apos;t have an account?{' '}
        <Link href="/signup" className="text-[--accent-hover] hover:underline font-medium">
          Create one
        </Link>
      </p>
    </>
  )
}
