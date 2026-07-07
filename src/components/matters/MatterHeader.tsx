'use client'

import { useState, useTransition, useRef, useEffect } from 'react'
import { toast } from 'sonner'
import { Badge } from '@/components/ui/badge'
import { Plus, Edit2, Check, X, Loader2, Info } from 'lucide-react'
import Link from 'next/link'
import { MATTER_STATUS_LABELS } from '@/lib/constants'
import { updateMatterTitle } from '@/lib/actions/matter'

export function MatterHeader({ matter, isClosed }: { matter: any, isClosed: boolean }) {
  const [isEditing, setIsEditing] = useState(false)
  const [titleValue, setTitleValue] = useState(matter.title)
  const [isPending, startTransition] = useTransition()
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus()
    }
  }, [isEditing])

  const handleSave = () => {
    if (titleValue.trim() === '' || titleValue === matter.title) {
      setIsEditing(false)
      setTitleValue(matter.title)
      return
    }

    startTransition(async () => {
      const res = await updateMatterTitle(matter.id, titleValue.trim())
      if (res.error) {
        toast.error(res.error)
        setTitleValue(matter.title)
      } else {
        toast.success('Title updated')
      }
      setIsEditing(false)
    })
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleSave()
    if (e.key === 'Escape') {
      setIsEditing(false)
      setTitleValue(matter.title)
    }
  }

  return (
    <div className="flex flex-col p-2.5 rounded-md bg-white border border-[--border-subtle] shadow-sm relative overflow-visible">
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0 flex-1">
          {/* Status Badge */}
          <Badge variant={matter.status === 'active' ? 'default' : 'muted'} className="shrink-0 h-5 py-0 px-1.5 text-[10px] tracking-wider uppercase">
            {MATTER_STATUS_LABELS[matter.status as keyof typeof MATTER_STATUS_LABELS] || matter.status}
          </Badge>
          
          {/* Editable Title */}
          {isEditing ? (
            <div className="flex items-center gap-1.5 min-w-0 flex-1 max-w-xl">
              <input
                ref={inputRef}
                value={titleValue}
                onChange={(e) => setTitleValue(e.target.value)}
                onKeyDown={handleKeyDown}
                className="w-full text-[15px] font-semibold text-[--text-primary] bg-slate-50 border border-blue-400 focus:ring-2 focus:ring-blue-200 outline-none rounded px-2 py-0.5"
                disabled={isPending}
              />
              <button 
                onClick={handleSave} 
                disabled={isPending}
                className="p-1 text-green-600 hover:bg-green-50 rounded transition-colors"
              >
                {isPending ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} />}
              </button>
              <button 
                onClick={() => { setIsEditing(false); setTitleValue(matter.title); }} 
                disabled={isPending}
                className="p-1 text-red-600 hover:bg-red-50 rounded transition-colors"
              >
                <X size={14} />
              </button>
            </div>
          ) : (
            <div className="flex items-center gap-2 min-w-0">
              <h1 
                onClick={() => setIsEditing(true)}
                className="text-[15px] font-semibold text-[--text-primary] truncate cursor-pointer hover:text-blue-600 transition-colors group flex items-center gap-1.5"
                title="Click to edit title"
              >
                {matter.title}
                <Edit2 size={12} className="opacity-0 group-hover:opacity-100 text-blue-400" />
              </h1>
            </div>
          )}

          <div className="flex items-center gap-2 text-[11px] text-[--text-muted] font-medium shrink-0 ml-2">
            {matter.matter_code && (
              <span className="font-mono bg-slate-50 px-1.5 py-0.5 rounded border border-slate-200">
                {matter.matter_code}
              </span>
            )}
            <span className="px-1.5 border-l border-slate-200">FY {matter.financial_year}</span>
          </div>

          {/* Hidden Synopsis Tooltip Trigger */}
          {matter.description && (
            <div className="group relative ml-2 shrink-0">
              <button className="text-[--text-muted] hover:text-[--primary] transition-colors p-1 rounded hover:bg-slate-50">
                <Info size={14} />
              </button>
              <div className="absolute left-0 top-full mt-1 w-80 p-3 bg-white border border-[--border-strong] shadow-xl rounded-md z-50 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all pointer-events-none">
                <span className="block text-[10px] font-bold uppercase text-[--text-muted] mb-1">Matter Synopsis</span>
                <p className="text-xs text-[--text-secondary] leading-relaxed whitespace-pre-wrap">
                  {matter.description}
                </p>
              </div>
            </div>
          )}
        </div>

        {/* Add Documents Button */}
        {!isClosed && (
          <div className="shrink-0">
            <Link 
              href={`/inbox?matterId=${matter.id}`}
              className="inline-flex items-center justify-center whitespace-nowrap rounded-md text-[11px] font-semibold h-7 px-2.5 bg-[--primary] hover:bg-[--primary-hover] text-white shadow-sm transition-colors"
            >
              <Plus size={12} className="mr-1" />
              Add Docs
            </Link>
          </div>
        )}
      </div>
    </div>
  )
}
