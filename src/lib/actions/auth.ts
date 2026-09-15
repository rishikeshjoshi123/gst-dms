'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { z } from 'zod'

const signupSchema = z.object({
  fullName: z.string().trim().min(2).max(200).refine((value) => !/[\u0000-\u001f\u007f]/.test(value)),
  email: z.string().trim().toLowerCase().email().max(320),
  password: z.string().min(8).max(72),
  confirmPassword: z.string(),
}).refine((value) => value.password === value.confirmPassword)

export async function signUp(formData: FormData) {
  const parsed = signupSchema.safeParse({
    fullName: formData.get('full_name'),
    email: formData.get('email'),
    password: formData.get('password'),
    confirmPassword: formData.get('confirm_password'),
  })
  if (!parsed.success) {
    return { error: 'Enter a valid name, email address, and matching password of 8 to 72 characters.' }
  }

  const supabase = await createClient()
  const { data, error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      data: { full_name: parsed.data.fullName },
      emailRedirectTo: new URL('/auth/callback?next=/onboarding', process.env.NEXT_PUBLIC_APP_URL ?? 'http://127.0.0.1:3000').toString(),
    },
  })

  if (error) {
    return { error: 'The account could not be created. Check the details and try again.' }
  }

  if (data.session) redirect('/onboarding')
  return { success: true }
}

export type SignInState = { error: string | null }

export async function signIn(_previousState: SignInState, formData: FormData): Promise<SignInState> {
  const supabase = await createClient()
  const email = String(formData.get('email') ?? '').trim().toLowerCase()
  const password = String(formData.get('password') ?? '')
  if (!z.string().email().max(320).safeParse(email).success || password.length<1 || password.length>72) {
    return { error: 'The email or password is incorrect.' }
  }

  const { error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: 'The email or password is incorrect.' }
  }

  // Canonical context is authoritative for active/suspended routing.
  const { data: { user } } = await supabase.auth.getUser()
  if (user) {
    const { data: contexts } = await supabase.rpc('get_my_organisation_context')
    const contextRows = contexts ?? []
    if (contextRows.length !== 1) redirect('/onboarding')
    const context = contextRows[0]
    if (context?.state === 'suspended') {
      redirect('/onboarding')
    }
    if (context?.state === 'active') {
      // Save current org into cookie
      const { cookies } = await import('next/headers')
      const cookieStore = await cookies()
      cookieStore.set('current_org_id', context.org_id, {
        httpOnly: true,
        path: '/',
        maxAge: 60 * 60 * 24 * 365, // 1 year
      })
      redirect('/dashboard')
    }
  }

  redirect('/onboarding')
}

export async function signOut() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  const { cookies } = await import('next/headers')
  const cookieStore = await cookies()
  cookieStore.delete('current_org_id')
  redirect('/login')
}
