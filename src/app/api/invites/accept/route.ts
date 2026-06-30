import { NextRequest, NextResponse } from 'next/server'
import { acceptInvite } from '@/lib/actions/org'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const token = searchParams.get('token')

  if (!token) {
    return NextResponse.redirect(`${origin}/login?error=missing_token`)
  }

  // If not logged in, redirect to login with token preserved
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return NextResponse.redirect(
      `${origin}/login?next=/api/invites/accept?token=${encodeURIComponent(token)}`
    )
  }

  // Use the server action to accept the invite
  const result = await acceptInvite(token)
  if (result?.error) {
    return NextResponse.redirect(
      `${origin}/onboarding?invite_error=${encodeURIComponent(result.error)}`
    )
  }

  // acceptInvite redirects to /dashboard on success
  return NextResponse.redirect(`${origin}/dashboard`)
}
