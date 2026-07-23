'use client'

import { useTransition } from 'react'
import { dismissReviewFlag } from '@/lib/actions/document'
import { AlertTriangle, X, ArrowRight, FolderOpen, Building2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

export function NeedsAttentionPanel({ documents }: { documents: any[] }) {
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  function handleDismiss(id: string) {
    startTransition(async () => {
      await dismissReviewFlag(id)
      router.refresh()
    })
  }

  if (documents.length === 0) return null

  return (
    <div className="rounded-lg bg-white dark:bg-[#161E2E] border border-[#E5E2DC] dark:border-[#1F293D] overflow-hidden animate-fade-in mb-8 shadow-xs border-l-4 border-l-amber-500">
      <div className="flex items-center gap-2 px-6 py-4 border-b border-[#E5E2DC] dark:border-[#1F293D] bg-amber-50/80 dark:bg-amber-950/40">
        <AlertTriangle size={18} className="text-amber-600 dark:text-amber-400" />
        <h2 className="text-[14px] font-semibold text-[#1C1917] dark:text-[#F8FAFC]">Needs Attention ({documents.length})</h2>
      </div>

      <div className="divide-y divide-[#E5E2DC] dark:divide-[#1F293D]">
        {documents.map(doc => {
          const fileName = doc.storage_path.split('/').pop()
          return (
            <div key={doc.id} className="flex flex-col sm:flex-row sm:items-start justify-between gap-4 p-6 hover:bg-slate-50/50 dark:hover:bg-slate-900/30 transition-colors">
              
              <div className="flex flex-col gap-1.5 min-w-0 flex-1">
                <div className="flex items-center gap-3">
                  <h3 className="font-medium text-[14px] text-[#1C1917] dark:text-[#F8FAFC] truncate">{fileName}</h3>
                  <span className="text-[10px] font-bold tracking-wider uppercase text-amber-700 dark:text-amber-300 bg-amber-100 dark:bg-amber-900/60 px-2 py-0.5 rounded-sm">
                    Flagged for review
                  </span>
                </div>
                
                <p className="text-[14px] text-[#78716C] dark:text-[#94A3B8] mt-1">{doc.review_reason}</p>

                <div className="flex items-center gap-4 mt-2">
                  <div className="flex items-center gap-1.5 text-[12px] text-[#A8A29E] dark:text-[#64748B]">
                    <Building2 size={12} />
                    <span className="truncate max-w-[150px]">{doc.matters?.clients?.name}</span>
                  </div>
                  <div className="flex items-center gap-1.5 text-[12px] text-[#A8A29E] dark:text-[#64748B]">
                    <FolderOpen size={12} />
                    <span>{doc.matters?.title} ({doc.matters?.matter_code})</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-2 shrink-0 pt-1">
                <Button 
                  variant="ghost" 
                  size="sm"
                  onClick={() => handleDismiss(doc.id)}
                  disabled={isPending}
                  className="text-[#78716C] dark:text-[#94A3B8]"
                >
                  <X size={14} className="mr-1.5" />
                  Dismiss
                </Button>
                <Button 
                  size="sm"
                  onClick={() => router.push(`/matters/${doc.matter_id}`)}
                  className="bg-[#1D4ED8] hover:bg-[#1E40AF] dark:bg-[#3B82F6] dark:hover:bg-[#2563EB] text-white"
                >
                  View Matter
                  <ArrowRight size={14} className="ml-1.5" />
                </Button>
              </div>

            </div>
          )
        })}
      </div>
    </div>
  )
}
