'use server'

import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function signUp(formData: FormData) {
  const supabase = await createClient()
  const email = formData.get('email') as string
  const password = formData.get('password') as string
  const fullName = formData.get('full_name') as string

  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName },
      emailRedirectTo: `${process.env.NEXT_PUBLIC_APP_URL}/auth/callback`,
    },
  })

  if (error) {
    return { error: error.message }
  }

  // Redirect to onboarding — session established via cookie automatically
  redirect('/onboarding')
}

export type SignInState = { error: string | null }

export async function signIn(_previousState: SignInState, formData: FormData): Promise<SignInState> {
  const supabase = await createClient()
  const email = formData.get('email') as string
  const password = formData.get('password') as string

  const { error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: error.message }
  }

  const cookieStore = await cookies()
  const intent = cookieStore.get('organisation_invitation_intent')?.value
  if (intent) redirect(`/api/invites/accept?next=${encodeURIComponent(cookieStore.get('organisation_invitation_next')?.value ?? '/dashboard')}`)

  // Canonical context is authoritative for active/suspended routing.
  const { data: { user } } = await supabase.auth.getUser()
  if (user) {
    const { data: contexts } = await (supabase.rpc as any)('get_my_organisation_context')
    const context = (contexts ?? [])[0]
    if (context?.state === 'suspended') {
      return { error: 'Access suspended.' }
    }
    if (context?.state === 'active') {
      // Save current org into cookie
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
  const cookieStore = await cookies()
  cookieStore.delete('current_org_id')
  redirect('/login')
}
