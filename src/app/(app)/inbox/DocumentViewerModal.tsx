'use client'

import { X } from 'lucide-react'
import { PdfViewer } from '@/components/ui/pdf-viewer'

interface DocumentViewerModalProps {
  url: string
  title?: string
  onClose: () => void
}

export function DocumentViewerModal({ url, title = 'Document Viewer', onClose }: DocumentViewerModalProps) {
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm animate-in fade-in duration-200 p-4 sm:p-8">
      <div className="bg-[var(--bg-surface)] rounded-xl shadow-2xl border border-[var(--border)] w-full max-w-6xl h-full max-h-[90vh] overflow-hidden flex flex-col animate-in zoom-in-95 duration-200">
        
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-[var(--border)] bg-[var(--bg)] shrink-0">
          <div className="min-w-0 pr-4">
            <h2 className="text-[16px] font-semibold text-[var(--text-primary)] leading-none truncate">
              {title}
            </h2>
          </div>
          <button 
            onClick={onClose}
            className="p-1.5 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--border-subtle)] transition-colors shrink-0"
          >
            <X size={20} />
          </button>
        </div>
        
        {/* Viewer Content */}
        <div className="flex-1 overflow-hidden bg-[var(--border)] relative">
          <PdfViewer url={url} />
        </div>
        
      </div>
    </div>
  )
}
