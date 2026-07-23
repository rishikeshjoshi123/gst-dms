import { SupabaseClient } from '@supabase/supabase-js'

export async function findClient(supabase: SupabaseClient, orgId: string, aiResult: any) {
  // 1. Match GSTIN
  if (aiResult.gstin) {
    const { data } = await supabase.from('clients').select('id, name').eq('org_id', orgId).eq('gstin', aiResult.gstin).is('deleted_at', null).maybeSingle()
    if (data) return data
  }
  // 2. Match PAN
  if (aiResult.pan_number) {
    const { data } = await supabase.from('clients').select('id, name').eq('org_id', orgId).eq('pan', aiResult.pan_number).is('deleted_at', null).maybeSingle()
    if (data) return data
  }
  // 3. Fuzzy match Client Name
  if (aiResult.client_name) {
    const { data } = await supabase.from('clients').select('id, name').eq('org_id', orgId).ilike('name', `%${aiResult.client_name}%`).is('deleted_at', null).maybeSingle()
    if (data) return data
  }
  return null
}
