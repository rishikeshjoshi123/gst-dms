import { Building2 } from 'lucide-react'
import { BreadcrumbSetter } from '@/components/nav/BreadcrumbSetter'
import type { TrashRetentionPolicy } from '@/lib/trash/retention-policy'
import { TrashRetentionSettingsSection } from './TrashRetentionSettingsSection'

interface SettingsClientProps {
  orgName: string
  retentionPolicy: TrashRetentionPolicy | null
  retentionPolicyLoadError: boolean
}

export function SettingsClient({
  orgName,
  retentionPolicy,
  retentionPolicyLoadError,
}: SettingsClientProps) {
  return (
    <div className="flex-1 flex flex-col min-h-0 overflow-y-auto custom-scrollbar animate-fade-in -mt-2">
      <BreadcrumbSetter breadcrumbs={[{ label: 'Settings' }]} />

      <div className="max-w-4xl w-full mx-auto space-y-4 pb-12">
        {/* Organisation Info Card */}
        <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-4 shadow-xs">
          <div className="flex items-center gap-3 mb-4 pb-3 border-b border-[var(--border)]">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[var(--primary)]/10 text-[var(--primary)] border border-[var(--primary)]/20 shrink-0">
              <Building2 size={16} />
            </div>
            <div>
              <h2 className="text-base font-bold text-[var(--text-primary)] leading-tight">Organisation Details</h2>
              <p className="text-[11px] text-[var(--text-muted)]">Workspace profile</p>
            </div>
          </div>

          <div className="flex items-center gap-4 text-sm">
            <div className="flex-1 px-3 py-2 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex justify-between items-center">
              <span className="text-[11px] font-semibold text-[var(--text-muted)] uppercase tracking-wider">Organisation Name</span>
              <span className="font-semibold text-[var(--text-primary)]">{orgName}</span>
            </div>
          </div>
        </div>

        <TrashRetentionSettingsSection
          initialPolicy={retentionPolicy}
          loadError={retentionPolicyLoadError}
        />
      </div>
    </div>
  )
}
