import assert from 'node:assert/strict'
import test from 'node:test'

import { NextRequest } from 'next/server'
import { NextResponse } from 'next/server'
import { readFileSync } from 'node:fs'

import { copySupabaseCookies, proxy } from './proxy'

const proxySource = readFileSync(new URL('./proxy.ts', import.meta.url), 'utf8')

test('developer review routes do not require a Supabase session', async () => {
  for (const pathname of ['/dev', '/dev/design-system', '/dev/review-workspace-concept']) {
    const response = await proxy(new NextRequest(`http://localhost:3000${pathname}`))

    assert.equal(response.status, 200)
    assert.equal(response.headers.get('location'), null)
  }
})

test('redirect and JSON responses preserve every refreshed Supabase cookie option', () => {
  const supabaseResponse = NextResponse.next()
  supabaseResponse.cookies.set({ name: 'sb-access-token', value: 'refreshed', path: '/', httpOnly: true, sameSite: 'lax', secure: true, maxAge: 120 })
  supabaseResponse.cookies.set({ name: 'sb-refresh-token', value: '', path: '/', httpOnly: true, expires: new Date(0) })

  for (const response of [NextResponse.redirect('http://localhost:3000/login'), NextResponse.json({ error: 'denied' }, { status: 403 })]) {
    const copied = copySupabaseCookies(response, supabaseResponse)
    const access = copied.cookies.get('sb-access-token')
    const refresh = copied.cookies.get('sb-refresh-token')
    assert.equal(access?.value, 'refreshed')
    assert.equal(access?.path, '/')
    assert.equal(access?.httpOnly, true)
    assert.equal(access?.sameSite, 'lax')
    assert.equal(access?.secure, true)
    assert.equal(access?.maxAge, 120)
    assert.equal(refresh?.value, '')
    assert.equal(refresh?.expires ? new Date(refresh.expires).getTime() : undefined, 0)
  }
})

test('every post-auth proxy denial or redirect copies Supabase cookies and revalidation remains public', () => {
  assert.equal(proxySource.match(/return copySupabaseCookies\(/g)?.length, 4)
  assert.match(proxySource, /'\/api\/revalidate'/)
  assert.match(proxySource, /NextResponse\.json\(\{ error: 'Organisation access is unavailable\.' \}, \{ status: 403 \}\)/)
})
