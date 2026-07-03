import { createClient } from '@supabase/supabase-js'
import { loadEnvConfig } from '@next/env'
loadEnvConfig(process.cwd())

// Use anon key, login as test user to test RLS
const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!)

async function run() {
  const { data: auth, error: authErr } = await supabase.auth.signInWithPassword({
    email: 'admin@taxcompany.com',
    password: 'password123'
  })
  
  if (authErr) {
    console.error("Auth error:", authErr)
    return
  }
  
  console.log("Logged in:", auth.user.email)
  
  const { data: staged } = await supabase.from('staged_documents').select('id, storage_path').limit(1).single()
  console.log("Found staged doc:", staged?.id)
  
  if (staged?.id) {
    const { data, error } = await supabase.from('staged_documents').delete().eq('id', staged.id).select()
    console.log("Delete result:", data, error)
  }
}
run()
