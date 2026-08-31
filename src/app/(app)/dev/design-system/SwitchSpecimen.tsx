'use client'

import { useState } from 'react'

import { Switch } from '@/components/ui/switch'

export function SwitchSpecimen() {
  const [checked, setChecked] = useState(false)

  return (
    <div className="mt-3 flex flex-wrap gap-5 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="flex items-center gap-3">
        <Switch checked={checked} onCheckedChange={setChecked} aria-label="Example binary setting" />
        <span className="text-sm">{checked ? 'On' : 'Off'}</span>
      </div>
      <div className="flex items-center gap-3">
        <Switch checked={false} disabled aria-label="Example setting unavailable" />
        <span className="text-sm text-[var(--text-muted)]">Unavailable</span>
      </div>
    </div>
  )
}
