import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const requestedNext = searchParams.get('next')
  const next = requestedNext?.startsWith('/') && !requestedNext.startsWith('//') ? requestedNext : '/onboarding'

  if (code) {
    const supabase = await createClient()
    const { error } = await supabase.auth.exchangeCodeForSession(code)
    if (!error) {
      const intent = request.cookies.get('organisation_invitation_intent')?.value
      return NextResponse.redirect(`${origin}${intent ? '/api/invites/accept' : next}`)
    }
  }

  // Something went wrong — send to login with error hint
  return NextResponse.redirect(`${origin}/login?error=auth_callback_failed`)
}
