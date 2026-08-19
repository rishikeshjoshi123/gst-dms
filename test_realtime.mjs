import { createClient } from '@supabase/supabase-js'
import WebSocket from 'ws'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || 'http://localhost:54321'
const SUPABASE_ANON_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY

console.log('URL:', SUPABASE_URL)
console.log('ANON_KEY length:', SUPABASE_ANON_KEY?.length)

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: false
  },
  realtime: {
    transport: WebSocket
  }
})

console.log('Connecting to Realtime for staged_documents...')

const channel = supabase.channel('staged_docs_changes')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'staged_documents' }, (payload) => {
    console.log('🔥 REALTIME EVENT RECEIVED:', JSON.stringify(payload, null, 2))
  })
  .subscribe((status, err) => {
    console.log('Subscription status:', status)
    if (err) console.error('Subscription error:', err)
  })

// Keep script running
setInterval(() => {}, 1000)
