import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createHash, randomBytes, randomUUID } from 'node:crypto'

const INTENT_COOKIE = 'organisation_invitation_intent'
const NEXT_COOKIE = 'organisation_invitation_next'
const hash = (value: string) => createHash('sha256').update(value).digest('hex')
const safePath = (value: string | null | undefined) => value?.startsWith('/') && !value.startsWith('//') ? value : '/dashboard'

function clearIntent(response: NextResponse) {
  response.cookies.set(INTENT_COOKIE, '', { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', maxAge: 0, path: '/' })
  response.cookies.set(NEXT_COOKIE, '', { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', maxAge: 0, path: '/' })
  return response
}

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url)
  const token = searchParams.get('token')
  const cookieIntent = request.cookies.get(INTENT_COOKIE)?.value
  const intentNext = safePath(request.cookies.get(NEXT_COOKIE)?.value)

  if (!token && !cookieIntent) {
    return clearIntent(NextResponse.redirect(`${origin}/onboarding?invite_error=invalid_invitation`))
  }

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    if (!token && cookieIntent) return NextResponse.redirect(`${origin}/login`)
    const nonce = randomBytes(32).toString('base64url')
    await (supabase.rpc as any)('begin_organisation_invitation_accept_intent', { p_selector_hash: hash(token ?? ''), p_nonce_hash: hash(nonce) })
    const response = NextResponse.redirect(`${origin}/login`)
    response.cookies.set(INTENT_COOKIE, nonce, { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', maxAge: 20 * 60, path: '/' })
    response.cookies.set(NEXT_COOKIE, safePath(searchParams.get('next')), { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', maxAge: 20 * 60, path: '/' })
    return response
  }

  const params = cookieIntent
    ? { p_nonce_hash: hash(cookieIntent ?? ''), p_idempotency_key: randomUUID() }
    : { p_selector_hash: hash(token ?? ''), p_idempotency_key: randomUUID() }
  const { data } = await (supabase.rpc as any)('accept_organisation_invite', params)
  const result = data?.[0]
  const accepted = result?.code === 'accepted'
  const response = clearIntent(NextResponse.redirect(`${origin}${accepted ? (searchParams.get('next') ? safePath(searchParams.get('next')) : intentNext) : '/onboarding?invite_error=invalid_invitation'}`))
  if (accepted && result.org_id) response.cookies.set('current_org_id', result.org_id, { httpOnly: true, sameSite: 'lax', secure: process.env.NODE_ENV === 'production', path: '/', maxAge: 60 * 60 * 24 * 365 })
  return response
}
