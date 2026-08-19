'use server'

import { createClient, createServiceClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { getCurrentOrgId } from './org'

export async function updateModelPricing(modelName: string, inputPrice: number, outputPrice: number) {
  const supabase = await createClient()

  // Ensure authenticated
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  const orgId = await getCurrentOrgId()
  if (!orgId) return { error: 'No active organisation.' }

  const { data: membership } = await supabase
    .from('org_members')
    .select('role')
    .eq('org_id', orgId)
    .eq('user_id', user.id)
    .maybeSingle()
  if (membership?.role !== 'admin') return { error: 'Only organisation admins can update pricing.' }

  const db = createServiceClient()
  const { error } = await db
    .from('model_pricing')
    .upsert({ 
      model_name: modelName,
      input_price_per_1m: inputPrice, 
      output_price_per_1m: outputPrice,
      updated_at: new Date().toISOString()
    }, { onConflict: 'model_name' })

  if (error) {
    console.error('Update pricing error:', error)
    return { error: error.message }
  }

  revalidatePath('/usage')
  return { success: true }
}
