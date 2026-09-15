import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import type { Database } from './lib/supabase/database.types'

/**
 * Proxy (formerly Middleware): refreshes expired sessions and enforces auth on protected routes.
 * In Next.js 16+, this file is named proxy.ts and exports a named `proxy` function.
 * Must run on every request that touches auth state.
 */
export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Local fixture and design-system pages never read production data. Keep the
  // entire developer-review namespace independent of Supabase session state so
  // new concepts do not need to be added to an authentication allowlist.
  if (pathname === '/dev' || pathname.startsWith('/dev/')) {
    return NextResponse.next({ request })
  }

  let supabaseResponse = NextResponse.next({
    request,
  })

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({
            request,
          })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // IMPORTANT: Avoid writing any logic between createServerClient and
  // supabase.auth.getUser(). A simple mistake could make it very hard to debug
  // issues with users being randomly logged out.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Public routes that don't require auth
  const publicRoutes = [
    '/login',
    '/signup',
    '/auth/callback',
    '/api/invites/accept',
    '/contact',
    '/api/revalidate',
  ]
  const isPublicRoute = pathname === '/' || publicRoutes.some((route) => route === '/api/invites/accept' ? pathname === route : pathname === route || pathname.startsWith(`${route}/`))

  if (!user && !isPublicRoute) {
    // Redirect unauthenticated users to login
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.searchParams.set('next', `${pathname}${request.nextUrl.search}`)
    return NextResponse.redirect(url)
  }

  const isOnboarding = pathname === '/onboarding' || pathname.startsWith('/onboarding/')
  let hasExactActiveContext = false
  if (user) {
    const { data: contexts, error } = await supabase.rpc('get_my_organisation_context')
    hasExactActiveContext = !error && (contexts ?? []).length === 1 && contexts?.[0]?.state === 'active'
  }

  if (user && (pathname === '/login' || pathname === '/signup')) {
    // A valid Auth session may belong to a suspended member. Route it to the
    // existing non-disclosing onboarding state instead of the protected shell.
    const url = request.nextUrl.clone()
    url.pathname = hasExactActiveContext ? '/dashboard' : '/onboarding'
    return NextResponse.redirect(url)
  }

  // Proxy is the Next 16 request boundary. Unlike a cached layout it runs for
  // RSC/client-navigation requests as well as full document requests.
  if (user && !isPublicRoute && !isOnboarding && !hasExactActiveContext) {
    if (pathname.startsWith('/api/')) {
      return NextResponse.json({ error: 'Organisation access is unavailable.' }, { status: 403 })
    }
    const url = request.nextUrl.clone()
    url.pathname = '/onboarding'
    url.search = ''
    return NextResponse.redirect(url)
  }

  // IMPORTANT: must return supabaseResponse, not NextResponse.next()
  return supabaseResponse
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization)
     * - favicon.ico
     * - public folder
     */
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
