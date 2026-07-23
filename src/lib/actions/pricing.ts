'use server'

import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function updateModelPricing(modelName: string, inputPrice: number, outputPrice: number) {
  const supabase = await createClient()

  // Ensure authenticated
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: 'Not authenticated.' }

  // Check if they are admin, or just allow any org member for now
  // For simplicity, we just allow authenticated users. In production you'd check role.

  const { error } = await supabase
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
