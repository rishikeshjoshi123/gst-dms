'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Plus, Edit3, Check, X, Loader2, Info, Building, Calendar, AlertTriangle, FileText, ArrowRight, Trash2 } from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { MATTER_STATUS_LABELS, FINANCIAL_YEARS, MatterStatus } from '@/lib/constants'
import { updateMatterDetails, deleteMatterAction } from '@/lib/actions/matter'

export function MatterDetailsTab({ matter }: { matter: any }) {
  const router = useRouter()
  const [isEditing, setIsEditing] = useState(false)
  const [isDeleteModalOpen, setIsDeleteModalOpen] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [title, setTitle] = useState(matter.title || '')
  const [financialYear, setFinancialYear] = useState(matter.financial_year || 'Unknown FY')
  const [status, setStatus] = useState<MatterStatus>(matter.status || 'active')
  const [description, setDescription] = useState(matter.description || '')
  const [isPending, startTransition] = useTransition()

  const handleDeleteMatter = async () => {
    setIsDeleting(true)
    const res = await deleteMatterAction(matter.id)
    setIsDeleting(false)
    if (res.error) {
      toast.error(res.error)
    } else {
      toast.success('Matter deleted successfully')
      setIsDeleteModalOpen(false)
      if (matter.client_id) {
        router.push(`/clients/${matter.client_id}`)
      } else {
        router.push('/matters')
      }
    }
  }

  const isClosed = matter.status === 'closed'
  const isUnknownFY = matter.financial_year === 'Unknown FY' || !matter.financial_year

  const handleSave = () => {
    if (!title.trim() || title.trim().length < 2) {
      toast.error('Title must be at least 2 characters.')
      return
    }

    startTransition(async () => {
      const res = await updateMatterDetails(matter.id, {
        title: title.trim(),
        financialYear,
        status,
        description: description.trim() || null,
      })

      if (res.error) {
        toast.error(res.error)
      } else {
        toast.success('Matter details updated successfully!')
        setIsEditing(false)
      }
    })
  }

  const handleCancel = () => {
    setTitle(matter.title || '')
    setFinancialYear(matter.financial_year || 'Unknown FY')
    setStatus(matter.status || 'active')
    setDescription(matter.description || '')
    setIsEditing(false)
  }

  return (
    <div className="flex flex-col gap-6 w-full max-w-5xl mx-auto py-6 px-1">
      {/* ── Main Overview Card ── */}
        <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-6 p-6 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
        <div className="flex flex-col gap-3 min-w-0 flex-1">
          {/* Status & Warning Badges */}
          <div className="flex flex-wrap items-center gap-2">
            <Badge 
              variant={matter.status === 'active' ? 'default' : 'muted'} 
              className="shrink-0 h-5 py-0 px-2 text-[10px] font-semibold uppercase tracking-wider bg-[var(--surface-hover)] text-[var(--text-primary)] border border-[var(--border)]"
            >
              {MATTER_STATUS_LABELS[matter.status as keyof typeof MATTER_STATUS_LABELS] || matter.status}
            </Badge>

            {isUnknownFY && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[11px] font-semibold uppercase bg-amber-50 text-amber-800 border border-amber-200">
                <AlertTriangle size={12} className="text-amber-600" />
                FY Unknown — Action Required
              </span>
            )}
          </div>

          {/* Title */}
          <h1 className="text-[24px] font-semibold text-[var(--text-primary)] tracking-tight leading-snug">
            {matter.title}
          </h1>

          {/* Quick Metadata */}
          <div className="flex flex-wrap items-center gap-3 text-[14px] text-[var(--text-secondary)] font-normal">
            {matter.matter_code && (
              <span className="font-mono bg-[var(--bg)] px-2 py-0.5 rounded border border-[var(--border)] text-[12px] font-medium text-[var(--text-primary)]">
                {matter.matter_code}
              </span>
            )}

            <span className="flex items-center gap-1 text-[var(--text-primary)] font-medium">
              <Calendar size={14} className="text-[var(--text-muted)]" />
              {isUnknownFY ? (
                <span className="text-amber-700 font-semibold">Unknown FY</span>
              ) : (
                `FY ${matter.financial_year}`
              )}
            </span>

            {matter.clients?.name && (
              <span className="text-[var(--text-secondary)]">
                Client: <strong className="text-[var(--text-primary)]">{matter.clients.name}</strong>
              </span>
            )}
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center gap-3 shrink-0 pt-2 md:pt-0">
          <button
            onClick={() => setIsEditing(true)}
            className="inline-flex items-center justify-center rounded-md text-[14px] font-medium h-10 px-4 bg-[var(--surface)] hover:bg-[var(--surface-hover)] text-[var(--text-primary)] border border-[var(--border)] transition-colors shadow-sm"
          >
            <Edit3 size={15} className="mr-2 text-[var(--text-muted)]" />
            Edit Details
          </button>

          <button
            onClick={() => setIsDeleteModalOpen(true)}
            className="inline-flex items-center justify-center rounded-md text-[14px] font-medium h-10 px-3 bg-[var(--surface)] hover:bg-red-500/10 text-red-600 border border-red-500/30 transition-colors shadow-sm"
            title="Delete Matter"
          >
            <Trash2 size={15} className="mr-1.5 text-red-600" />
            Delete
          </button>

          {!isClosed && (
            <Link
              href={`/inbox?matterId=${matter.id}`}
              className="inline-flex items-center justify-center rounded-md text-[14px] font-semibold h-10 px-5 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white shadow-sm transition-colors"
            >
              <Plus size={16} className="mr-2" />
              Upload Documents
            </Link>
          )}
        </div>
      </div>

      {/* ── Warning Banner for Unknown FY ── */}
      {isUnknownFY && !isEditing && (
        <div className="flex items-center justify-between p-4 rounded-lg bg-amber-50 border border-amber-200 text-amber-900 shadow-sm">
          <div className="flex items-center gap-3">
            <AlertTriangle size={20} className="text-amber-600 shrink-0" />
            <div>
              <p className="text-[14px] font-semibold">Financial Year is not assigned</p>
              <p className="text-[12px] text-amber-800">
                This matter was created without an FY. Updating the Financial Year ensures future uploaded documents auto-assign to this case.
              </p>
            </div>
          </div>
          <button
            onClick={() => setIsEditing(true)}
            className="shrink-0 text-[12px] font-semibold bg-amber-600 hover:bg-amber-700 text-white px-3 py-1.5 rounded transition-colors"
          >
            Update FY Now
          </button>
        </div>
      )}

      {/* ── Detail Cards Grid ── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Left Card: Client & Entity Details */}
        <div className="flex flex-col p-6 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
          <div className="flex items-center gap-2 mb-5 border-b border-[var(--border)] pb-3">
            <Building size={18} className="text-[var(--text-muted)]" />
            <h2 className="text-[16px] font-semibold text-[var(--text-primary)]">Client & Entity Info</h2>
          </div>

          <div className="flex flex-col gap-4">
            <div className="flex flex-col">
              <span className="text-[12px] font-medium text-[var(--text-muted)] uppercase tracking-wider mb-1">
                Client Name
              </span>
              {matter.client_id ? (
                <Link 
                  href={`/clients/${matter.client_id}`}
                  className="text-[14px] font-semibold text-[var(--primary)] hover:underline flex items-center gap-1 group"
                >
                  {matter.clients?.name || 'View Client Profile'}
                  <ArrowRight size={14} className="opacity-0 group-hover:opacity-100 transition-opacity" />
                </Link>
              ) : (
                <span className="text-[14px] font-normal text-[var(--text-primary)]">Unassigned</span>
              )}
            </div>

            {matter.clients?.gstin && (
              <div className="flex flex-col">
                <span className="text-[12px] font-medium text-[var(--text-muted)] uppercase tracking-wider mb-1">
                  GSTIN
                </span>
                <span className="text-[14px] font-mono text-[var(--text-primary)] bg-[var(--bg)] px-2 py-1 rounded border border-[var(--border)] w-fit">
                  {matter.clients.gstin}
                </span>
              </div>
            )}

            {matter.clients?.pan && (
              <div className="flex flex-col">
                <span className="text-[12px] font-medium text-[var(--text-muted)] uppercase tracking-wider mb-1">
                  PAN
                </span>
                <span className="text-[14px] font-mono text-[var(--text-primary)] bg-[var(--bg)] px-2 py-1 rounded border border-[var(--border)] w-fit">
                  {matter.clients.pan}
                </span>
              </div>
            )}

            <div className="flex flex-col pt-2 border-t border-[var(--border)]">
              <span className="text-[12px] font-medium text-[var(--text-muted)] uppercase tracking-wider mb-1">
                Matter Code
              </span>
              <span className="text-[14px] font-mono font-medium text-[var(--text-primary)]">
                {matter.matter_code || 'Auto-generated on creation'}
              </span>
            </div>
          </div>
        </div>

        {/* Right Card: Matter Synopsis */}
        <div className="flex flex-col p-6 rounded-lg bg-[var(--surface)] border border-[var(--border)] shadow-sm">
          <div className="flex items-center justify-between mb-5 border-b border-[var(--border)] pb-3">
            <div className="flex items-center gap-2">
              <Info size={18} className="text-[var(--text-muted)]" />
              <h2 className="text-[16px] font-semibold text-[var(--text-primary)]">Matter Synopsis</h2>
            </div>
            <button
              onClick={() => setIsEditing(true)}
              className="text-[12px] font-medium text-[var(--primary)] hover:underline"
            >
              Edit Synopsis
            </button>
          </div>

          {matter.description ? (
            <p className="text-[14px] font-normal text-[var(--text-primary)] leading-relaxed whitespace-pre-wrap">
              {matter.description}
            </p>
          ) : (
            <div className="flex flex-col items-center justify-center text-center p-6 border border-dashed border-[var(--border-strong)] rounded-md bg-[var(--bg)]">
              <FileText size={24} className="text-[var(--text-muted)] mb-2" />
              <p className="text-[14px] font-normal text-[var(--text-secondary)]">No synopsis provided yet.</p>
              <button
                onClick={() => setIsEditing(true)}
                className="mt-2 text-[12px] font-semibold text-[var(--primary)] hover:underline"
              >
                + Add Synopsis
              </button>
            </div>
          )}
        </div>
      </div>

      {/* ── Edit Matter Details Modal ── */}
      {isEditing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs animate-fade-in">
          <div className="bg-[var(--surface)] rounded-lg shadow-xl border border-[var(--border)] w-full max-w-xl overflow-hidden flex flex-col animate-in zoom-in-95 duration-150">
            {/* Modal Header */}
            <div className="flex items-center justify-between p-6 border-b border-[var(--border)]">
              <div>
                <h3 className="text-[18px] font-semibold text-[var(--text-primary)]">Edit Matter Details</h3>
                <p className="text-[14px] font-normal text-[var(--text-secondary)] mt-0.5">
                  Update matter title, financial year, status, and synopsis.
                </p>
              </div>
              <button
                onClick={handleCancel}
                disabled={isPending}
                className="p-2 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-md hover:bg-[var(--surface-hover)] transition-colors"
              >
                <X size={18} />
              </button>
            </div>

            {/* Modal Body / Form */}
            <div className="p-6 flex flex-col gap-4 max-h-[70vh] overflow-y-auto">
              {/* Title Input */}
              <div className="flex flex-col gap-1.5">
                <label className="text-[12px] font-semibold uppercase tracking-wider text-[var(--text-primary)]">
                  Matter Title <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. FY 2023-24 Audit Proceeding"
                  disabled={isPending}
                  className="w-full bg-[var(--surface)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded-md px-3 py-2 text-[14px] text-[var(--text-primary)] transition-all"
                />
              </div>

              {/* Financial Year Select */}
              <div className="flex flex-col gap-1.5">
                <label className="text-[12px] font-semibold uppercase tracking-wider text-[var(--text-primary)]">
                  Financial Year <span className="text-red-500">*</span>
                </label>
                <select
                  value={financialYear}
                  onChange={(e) => setFinancialYear(e.target.value)}
                  disabled={isPending}
                  className="w-full bg-[var(--surface)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded-md px-3 py-2 text-[14px] text-[var(--text-primary)] transition-all"
                >
                  <option value="Unknown FY">Unknown FY</option>
                  {FINANCIAL_YEARS.map((fy) => (
                    <option key={fy} value={fy}>
                      FY {fy}
                    </option>
                  ))}
                </select>
                <p className="text-[12px] text-[var(--text-muted)]">
                  Updating FY will automatically synchronize all linked documents with unassigned FYs.
                </p>
              </div>

              {/* Status Select */}
              <div className="flex flex-col gap-1.5">
                <label className="text-[12px] font-semibold uppercase tracking-wider text-[var(--text-primary)]">
                  Status
                </label>
                <select
                  value={status}
                  onChange={(e) => setStatus(e.target.value as MatterStatus)}
                  disabled={isPending}
                  className="w-full bg-[var(--surface)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded-md px-3 py-2 text-[14px] text-[var(--text-primary)] transition-all"
                >
                  {Object.entries(MATTER_STATUS_LABELS).map(([key, label]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Synopsis / Description */}
              <div className="flex flex-col gap-1.5">
                <label className="text-[12px] font-semibold uppercase tracking-wider text-[var(--text-primary)]">
                  Matter Synopsis / Notes
                </label>
                <textarea
                  rows={4}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Provide background, notice numbers, or key dispute context..."
                  disabled={isPending}
                  className="w-full bg-[var(--surface)] border border-[var(--border-strong)] focus:border-[var(--primary)] focus:ring-2 focus:ring-[var(--primary)]/20 outline-none rounded-md px-3 py-2 text-[14px] text-[var(--text-primary)] transition-all resize-y"
                />
              </div>
            </div>

            {/* Modal Footer */}
            <div className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
              <button
                type="button"
                onClick={handleCancel}
                disabled={isPending}
                className="px-4 py-2 text-[14px] font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-md transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={isPending}
                className="inline-flex items-center justify-center px-5 py-2 text-[14px] font-semibold bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white rounded-md transition-colors shadow-sm"
              >
                {isPending ? (
                  <>
                    <Loader2 size={16} className="animate-spin mr-2" />
                    Saving Changes...
                  </>
                ) : (
                  'Save Changes'
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Delete Matter Confirmation Modal ── */}
      {isDeleteModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-xs animate-fade-in">
          <div className="bg-[var(--surface)] rounded-lg shadow-xl border border-[var(--border)] w-full max-w-md overflow-hidden flex flex-col animate-in zoom-in-95 duration-150">
            <div className="p-6 flex flex-col gap-3">
              <div className="flex items-center gap-3 text-red-600">
                <AlertTriangle size={24} className="shrink-0" />
                <h3 className="text-[18px] font-semibold text-[var(--text-primary)]">Delete Matter?</h3>
              </div>
              <p className="text-[14px] font-normal text-[var(--text-secondary)] leading-relaxed">
                Are you sure you want to delete <strong className="text-[var(--text-primary)]">"{matter.title}"</strong>? All associated documents inside this matter will also be soft-deleted.
              </p>
            </div>
            <div className="flex items-center justify-end gap-3 p-4 px-6 border-t border-[var(--border)] bg-[var(--bg)]">
              <button
                type="button"
                onClick={() => setIsDeleteModalOpen(false)}
                disabled={isDeleting}
                className="px-4 py-2 text-[14px] font-medium text-[var(--text-primary)] hover:bg-[var(--surface-hover)] rounded-md transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDeleteMatter}
                disabled={isDeleting}
                className="inline-flex items-center justify-center px-5 py-2 text-[14px] font-semibold bg-red-600 hover:bg-red-700 text-white rounded-md transition-colors shadow-sm"
              >
                {isDeleting ? (
                  <>
                    <Loader2 size={16} className="animate-spin mr-2" />
                    Deleting...
                  </>
                ) : (
                  'Delete Matter'
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
