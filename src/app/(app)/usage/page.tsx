import { createClient, createServiceClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { PricingManager } from '@/components/usage/PricingManager'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'

export default async function UsagePage() {
  const supabase = await createClient()

  // Get user and verify auth
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Use service client to fetch ALL system-wide AI usage logs (Dev Mode)
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

  // Calculate aggregates
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  
  const thisWeek = new Date()
  thisWeek.setDate(thisWeek.getDate() - thisWeek.getDay())
  thisWeek.setHours(0, 0, 0, 0)

  const thisMonth = new Date()
  thisMonth.setDate(1)
  thisMonth.setHours(0, 0, 0, 0)

  const metrics = {
    today: { cost: 0, input: 0, output: 0 },
    week: { cost: 0, input: 0, output: 0 },
    month: { cost: 0, input: 0, output: 0 },
  }

  const uniqueModels = new Set<string>()

  logs.forEach(log => {
    const cost = Number(log.total_cost_usd || 0)
    const logDate = new Date(log.created_at)
    
    uniqueModels.add(log.model_name)

    if (logDate >= today) {
      metrics.today.cost += cost
      metrics.today.input += log.input_tokens || 0
      metrics.today.output += log.output_tokens || 0
    }
    if (logDate >= thisWeek) {
      metrics.week.cost += cost
      metrics.week.input += log.input_tokens || 0
      metrics.week.output += log.output_tokens || 0
    }
    if (logDate >= thisMonth) {
      metrics.month.cost += cost
      metrics.month.input += log.input_tokens || 0
      metrics.month.output += log.output_tokens || 0
    }
  })

  // Ensure all models that have logs appear in the pricing manager
  const pricingData = modelPricing || []
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
      <div className="p-8 max-w-7xl mx-auto space-y-8">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-[24px] font-[600] text-[var(--text-primary)]">Token Usage & Server Costs</h1>
            <p className="text-[14px] text-[var(--text-secondary)] mt-1">Track server-wide processing API utilization across all operations & tests.</p>
          </div>

          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-md bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 text-xs font-semibold shrink-0">
            <span className="h-2 w-2 rounded-full bg-amber-500 animate-pulse" />
            [Dev Mode] Showing System-Wide Server Costs (All Orgs & Background Tasks)
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Today Metrics */}
          <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
            <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]">
              <CardTitle className="text-[14px] font-[600] text-[var(--text-primary)]">Today</CardTitle>
            </CardHeader>
            <CardContent className="pt-4 space-y-4">
              <div>
                <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
                <div className="text-[28px] font-[700] text-[var(--text-primary)]">${metrics.today.cost.toFixed(4)}</div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Input Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.today.input.toLocaleString()}</div>
                </div>
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Output Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.today.output.toLocaleString()}</div>
                </div>
                <div className="col-span-2 border-t border-[var(--border)] pt-2">
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Total Tokens</div>
                  <div className="text-[16px] font-[600] text-[var(--text-primary)]">{(metrics.today.input + metrics.today.output).toLocaleString()}</div>
                </div>
              </div>
            </CardContent>
          </Card>
          
          {/* This Week Metrics */}
          <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
            <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]">
              <CardTitle className="text-[14px] font-[600] text-[var(--text-primary)]">This Week</CardTitle>
            </CardHeader>
            <CardContent className="pt-4 space-y-4">
              <div>
                <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
                <div className="text-[28px] font-[700] text-[var(--text-primary)]">${metrics.week.cost.toFixed(4)}</div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Input Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.week.input.toLocaleString()}</div>
                </div>
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Output Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.week.output.toLocaleString()}</div>
                </div>
                <div className="col-span-2 border-t border-[var(--border)] pt-2">
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Total Tokens</div>
                  <div className="text-[16px] font-[600] text-[var(--text-primary)]">{(metrics.week.input + metrics.week.output).toLocaleString()}</div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* This Month Metrics */}
          <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] text-[var(--text-primary)]">
            <CardHeader className="pb-2 border-b border-[var(--border)] bg-[var(--bg)]">
              <CardTitle className="text-[14px] font-[600] text-[var(--text-primary)]">This Month</CardTitle>
            </CardHeader>
            <CardContent className="pt-4 space-y-4">
              <div>
                <div className="text-[10px] font-[600] text-[var(--text-muted)] uppercase tracking-wider mb-1">Total Cost</div>
                <div className="text-[28px] font-[700] text-[var(--text-primary)]">${metrics.month.cost.toFixed(4)}</div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Input Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.month.input.toLocaleString()}</div>
                </div>
                <div>
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Output Tokens</div>
                  <div className="text-[14px] font-[600] text-[var(--text-secondary)]">{metrics.month.output.toLocaleString()}</div>
                </div>
                <div className="col-span-2 border-t border-[var(--border)] pt-2">
                  <div className="text-[10px] font-[500] text-[var(--text-muted)] uppercase">Total Tokens</div>
                  <div className="text-[16px] font-[600] text-[var(--text-primary)]">{(metrics.month.input + metrics.month.output).toLocaleString()}</div>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="bg-[var(--surface)] rounded-lg shadow-sm border border-[var(--border)] overflow-hidden">
          <div className="px-6 py-4 border-b border-[var(--border)] bg-[var(--bg)]">
            <h2 className="text-[16px] font-[600] text-[var(--text-primary)]">Recent Server Operations</h2>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-[14px]">
              <thead className="bg-[var(--bg)] text-[12px] uppercase text-[var(--text-muted)] font-[500] border-b border-[var(--border)]">
                <tr>
                  <th className="px-6 py-3">Timestamp</th>
                  <th className="px-6 py-3">Operation</th>
                  <th className="px-6 py-3">Model</th>
                  <th className="px-6 py-3">Tokens (In / Out)</th>
                  <th className="px-6 py-3">Cost (USD)</th>
                  <th className="px-6 py-3">Document</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--border)]">
                {logs.map((log) => (
                  <tr key={log.id} className="hover:bg-[var(--surface-hover)] transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap text-[var(--text-secondary)]">
                      {new Date(log.created_at).toLocaleString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false })}
                    </td>
                    <td className="px-6 py-4">
                      <span className="inline-flex items-center px-2 py-1 rounded bg-[var(--bg)] border border-[var(--border)] text-[12px] font-medium text-[var(--text-primary)]">
                        {log.operation_type}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-[var(--text-primary)]">
                      {log.model_name}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-secondary)]">
                      {log.input_tokens?.toLocaleString()} / {log.output_tokens?.toLocaleString()}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-primary)] font-medium">
                      ${Number(log.total_cost_usd || 0).toFixed(6)}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-secondary)]">
                      {(log as any).documents?.reference_number || 'N/A'}
                    </td>
                  </tr>
                ))}
                {logs.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-6 py-8 text-center text-[var(--text-muted)]">
                      No operations recorded yet.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
        <PricingManager initialPricing={pricingData} />
      </div>
    </div>
  )
}
