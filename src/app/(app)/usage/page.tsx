import { createClient, createServiceClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import { UsageClientView } from '@/components/usage/UsageClientView'

export default async function UsagePage() {
  const supabase = await createClient()

  // Get user and verify auth
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Development-only platform dashboard: intentionally aggregates every
  // organisation's usage while the product has no separate admin surface.
  // Before production, move this query behind a platform-admin boundary.
  const serviceClient = createServiceClient()
  const { data: logs, error } = await serviceClient
    .from('ai_usage_logs')
    .select('*, documents(reference_number)')
    .order('created_at', { ascending: false })
    .limit(1000)

  if (error) {
    console.error('Error fetching usage logs:', error)
    return <div className="p-8 text-[var(--text-muted)]">Failed to load usage data</div>
  }

  // Fetch model pricing
  const { data: modelPricing } = await supabase
    .from('model_pricing')
    .select('model_name, input_price_per_1m, output_price_per_1m')
    .order('model_name')

  const uniqueModels = new Set<string>()
  logs?.forEach(log => {
    if (log.model_name) uniqueModels.add(log.model_name)
  })

  // Ensure all models that have logs appear in the pricing manager
  const pricingData = modelPricing ? [...modelPricing] : []
  uniqueModels.forEach(model => {
    if (!pricingData.find(p => p.model_name === model)) {
      pricingData.push({
        model_name: model,
        input_price_per_1m: 0,
        output_price_per_1m: 0
      })
    }
  })

  return (
    <div className="flex-1 overflow-auto bg-[var(--bg)] text-[var(--text-primary)]">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Token Usage' }]} />
      <div className="p-8 max-w-7xl mx-auto">
        <UsageClientView logs={logs || []} initialPricing={pricingData} />
      </div>
    </div>
  )
}
