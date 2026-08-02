'use client'

import { useState } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Edit2, Check, X, Loader2 } from 'lucide-react'
import { updateModelPricing } from '@/lib/actions/pricing'
import { toast } from 'sonner'

type PricingRow = {
  model_name: string
  input_price_per_1m: number
  output_price_per_1m: number
}

export function PricingManager({ initialPricing, readOnly = false }: { initialPricing: PricingRow[], readOnly?: boolean }) {
  const [pricing, setPricing] = useState<PricingRow[]>(initialPricing)
  const [editingModel, setEditingModel] = useState<string | null>(null)
  const [isSaving, setIsSaving] = useState(false)
  const [editValues, setEditValues] = useState<{ input: string, output: string }>({ input: '', output: '' })

  const startEdit = (p: PricingRow) => {
    if (readOnly) return
    setEditingModel(p.model_name)
    setEditValues({
      input: p.input_price_per_1m.toString(),
      output: p.output_price_per_1m.toString()
    })
  }

  const cancelEdit = () => {
    setEditingModel(null)
    setEditValues({ input: '', output: '' })
  }

  const saveEdit = async (modelName: string) => {
    const inputVal = parseFloat(editValues.input)
    const outputVal = parseFloat(editValues.output)

    if (isNaN(inputVal) || isNaN(outputVal)) {
      toast.error('Please enter valid numeric values.')
      return
    }

    setIsSaving(true)
    const res = await updateModelPricing(modelName, inputVal, outputVal)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success(`Pricing for ${modelName} updated!`)
      setPricing(prev => prev.map(p => p.model_name === modelName ? { ...p, input_price_per_1m: inputVal, output_price_per_1m: outputVal } : p))
      setEditingModel(null)
    }
    setIsSaving(false)
  }

  return (
    <Card className="shadow-sm border-[var(--border)] bg-[var(--surface)] mt-8 text-[var(--text-primary)]">
      <CardHeader className="pb-2 border-b border-[var(--border)]">
        <CardTitle className="text-[16px] font-[600] text-[var(--text-primary)]">Model Pricing ($ USD per 1M tokens)</CardTitle>
      </CardHeader>
      <CardContent className="pt-4">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="bg-[var(--bg)] text-[var(--text-muted)] font-medium border-b border-[var(--border)]">
              <tr>
                <th className="px-6 py-3 rounded-tl-lg">Model Name</th>
                <th className="px-6 py-3">Input Price</th>
                <th className={`px-6 py-3 ${readOnly ? 'rounded-tr-lg' : ''}`}>Output Price</th>
                {!readOnly && <th className="px-6 py-3 rounded-tr-lg w-24">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border)]">
              {pricing.map((p) => {
                const isEditing = !readOnly && editingModel === p.model_name
                return (
                  <tr key={p.model_name} className="hover:bg-[var(--surface-hover)] transition-colors">
                    <td className="px-6 py-4 font-medium text-[var(--text-primary)]">
                      {p.model_name}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-secondary)]">
                      {isEditing ? (
                        <input
                          type="number"
                          step="0.0001"
                          value={editValues.input}
                          onChange={(e) => setEditValues(prev => ({ ...prev, input: e.target.value }))}
                          className="w-24 text-sm bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] focus:ring-2 focus:ring-[var(--primary)] outline-none rounded px-2 py-1 shadow-sm"
                        />
                      ) : (
                        `$${Number(p.input_price_per_1m).toFixed(4)}`
                      )}
                    </td>
                    <td className="px-6 py-4 text-[var(--text-secondary)]">
                      {isEditing ? (
                        <input
                          type="number"
                          step="0.0001"
                          value={editValues.output}
                          onChange={(e) => setEditValues(prev => ({ ...prev, output: e.target.value }))}
                          className="w-24 text-sm bg-[var(--bg)] text-[var(--text-primary)] border border-[var(--border-strong)] focus:ring-2 focus:ring-[var(--primary)] outline-none rounded px-2 py-1 shadow-sm"
                        />
                      ) : (
                        `$${Number(p.output_price_per_1m).toFixed(4)}`
                      )}
                    </td>
                    {!readOnly && (
                      <td className="px-6 py-4">
                        {isEditing ? (
                          <div className="flex items-center gap-2">
                            <button onClick={() => saveEdit(p.model_name)} disabled={isSaving} className="text-green-600 hover:text-green-700">
                              {isSaving ? <Loader2 size={16} className="animate-spin" /> : <Check size={16} />}
                            </button>
                            <button onClick={cancelEdit} disabled={isSaving} className="text-red-500 hover:text-red-600">
                              <X size={16} />
                            </button>
                          </div>
                        ) : (
                          <button 
                            onClick={() => startEdit(p)}
                            className="text-[var(--primary)] hover:bg-[var(--primary)]/10 p-1.5 rounded transition-colors"
                            title="Edit pricing"
                          >
                            <Edit2 size={14} />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                )
              })}
            </tbody>
          </table>
          {pricing.length === 0 && (
             <div className="p-4 text-center text-sm text-[var(--text-muted)]">No pricing data found.</div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
