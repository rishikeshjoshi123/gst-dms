import { NextRequest, NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      const { data: contexts } = await supabase.rpc('get_my_organisation_context')
      const cookieStore = await cookies()
      cookieStore.delete('organisation_invitation_intent')
      cookieStore.delete('organisation_invitation_next')
      redirect(contexts?.some((context) => context.state === 'active') ? '/dashboard' : '/onboarding')
    }
  }

  return NextResponse.redirect(`${origin}/login?error=auth_callback_failed`)
}
