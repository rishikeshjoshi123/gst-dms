import { SupabaseClient } from '@supabase/supabase-js'

export async function logUsage(
  supabase: SupabaseClient,
  params: {
    orgId: string,
    userId?: string | null,
    docId?: string | null,
    operationType: string,
    modelName: string,
    inputTokens?: number,
    outputTokens?: number
  }
) {
  try {
    const { data: pricing } = await supabase
      .from('model_pricing')
      .select('input_price_per_1m, output_price_per_1m')
      .eq('model_name', params.modelName)
      .maybeSingle()

    let totalCost = 0
    if (pricing) {
      const inCost = ((params.inputTokens || 0) / 1000000) * Number(pricing.input_price_per_1m)
      const outCost = ((params.outputTokens || 0) / 1000000) * Number(pricing.output_price_per_1m)
      totalCost = inCost + outCost
    }

    await supabase.from('ai_usage_logs').insert({
      org_id: params.orgId,
      user_id: params.userId || null,
      document_id: params.docId || null,
      operation_type: params.operationType,
      model_name: params.modelName,
      input_tokens: params.inputTokens || 0,
      output_tokens: params.outputTokens || 0,
      total_cost_usd: totalCost
    })
  } catch (err) {
    console.error('[logUsage] Failed to log AI usage:', err)
  }
}
