import { createServerClient } from '@supabase/ssr'
import { createClient as createSupabaseClient } from '@supabase/supabase-js'
import { cookies } from 'next/headers'
import type { Database } from './database.types'

// Polyfill WebSocket for environments like Trigger.dev (running on older Node)
// where Supabase-js instantiates Realtime client on constructor.
if (typeof global !== 'undefined' && !global.WebSocket) {
  (global as any).WebSocket = class {};
}

/**
 * Server Component / Server Action Supabase client.
 * Uses cookie store to maintain session server-side.
 */
export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // setAll called from Server Component — safe to ignore.
            // Proxy (middleware) handles session refresh.
          }
        },
      },
    }
  )
}

/**
 * Service-role client for Trigger.dev jobs and admin operations.
 * NEVER expose to client. Only use server-side.
 */
export function createServiceClient() {
  return createSupabaseClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  )
}
