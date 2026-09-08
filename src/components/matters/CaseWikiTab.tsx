'use client'

import { useState } from 'react'
import { toast } from 'sonner'
import { Sparkles, Edit2, Check, X } from 'lucide-react'
import { updateWikiSection } from '@/lib/actions/wiki'
import { CaseWikiMarkdown } from './CaseWikiMarkdown'
import type { Database, Json } from '@/lib/supabase/database.types'

type WikiSection = Database['public']['Tables']['wiki_sections']['Row']

function wikiText(content: Json) {
  if (typeof content !== 'string') return ''
  try {
    const parsed: unknown = JSON.parse(content)
    if (typeof parsed === 'object' && parsed !== null && 'text' in parsed && typeof parsed.text === 'string') {
      return parsed.text
    }
  } catch {}
  return ''
}

export function CaseWikiTab({ matterId, initialSections, readOnly = false }: { matterId: string; initialSections: WikiSection[]; readOnly?: boolean }) {
  const [localEdits, setLocalEdits] = useState<Record<string, string>>({})
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editContent, setEditContent] = useState<string>('')

  const sections = initialSections.map((section) => localEdits[section.id] === undefined
    ? section
    : { ...section, content: JSON.stringify({ text: localEdits[section.id] }), is_user_edited: true })

  const startEditing = (section: WikiSection) => {
    if (readOnly) return
    setEditingId(section.id)
    setEditContent(wikiText(section.content))
  }

  const saveEdit = async (section: WikiSection) => {
    if (readOnly) return
    const toastId = toast.loading('Saving section edits...')
    const res = await updateWikiSection(section.id, editContent, matterId)
    if (res.error) {
      toast.error(res.error, { id: toastId })
    } else {
      toast.success('Section updated successfully!', { id: toastId })
      setLocalEdits((previous) => ({ ...previous, [section.id]: editContent }))
      setEditingId(null)
    }
  }

  if (sections.length === 0) {
    return (
      <div className="py-16 flex flex-col items-center justify-center text-[var(--text-muted)] border border-dashed border-[var(--border-strong)] rounded-lg bg-[var(--surface)]">
        <Sparkles size={40} className="mb-4 text-[var(--primary)] opacity-80" />
        <h3 className="text-xl font-medium text-[var(--text-primary)] mb-2">Case Brief</h3>
        <p className="text-sm max-w-md text-center leading-relaxed">
          Case Brief generation is not available in this release. Existing compatibility content remains readable when present.
        </p>
      </div>
    )
  }

  const orderedKeys = ['executive_summary', 'key_arguments', 'outstanding_tasks']
  const orderedSections = orderedKeys
    .map(key => sections.find(s => s.section_key === key))
    .filter((section): section is WikiSection => Boolean(section))

  return (
    <div className="flex flex-col gap-6 py-2">
      {orderedSections.map((section) => {
        const textContent = wikiText(section.content)

        const isEditing = editingId === section.id

        return (
          <div key={section.id} className="flex flex-col bg-[var(--surface)] rounded-[var(--radius-md)] border border-[var(--border)] overflow-hidden shadow-sm">
            <div className="flex items-center justify-between bg-[var(--surface-hover)] border-b border-[var(--border)] px-5 py-3">
              <div className="flex items-center gap-3">
                <h3 className="text-[16px] font-semibold text-[var(--text-primary)]">{section.title}</h3>
                {section.is_user_edited && (
                  <span className="text-[10px] font-medium uppercase tracking-wider text-[var(--warning)] bg-[var(--warning-muted)] px-2 py-0.5 rounded-[var(--radius-sm)] border border-[color-mix(in_srgb,var(--warning)_30%,transparent)]">
                    Manually Edited
                  </span>
                )}
              </div>
              
              {!readOnly && (!isEditing ? (
                <button onClick={() => startEditing(section)} className="text-[var(--text-muted)] hover:text-[var(--primary)] transition-colors p-1 rounded-[var(--radius-sm)] hover:bg-[var(--primary)]/10">
                  <Edit2 size={16} />
                </button>
              ) : (
                <div className="flex items-center gap-2">
                  <button onClick={() => saveEdit(section)} className="text-[var(--success)] hover:text-[color-mix(in_srgb,var(--success)_70%,black)] transition-colors p-1 rounded-[var(--radius-sm)] hover:bg-[var(--success-muted)]">
                    <Check size={18} />
                  </button>
                  <button onClick={() => setEditingId(null)} className="text-[var(--text-muted)] hover:text-[var(--danger)] transition-colors p-1 rounded-[var(--radius-sm)] hover:bg-[var(--danger-muted)]">
                    <X size={18} />
                  </button>
                </div>
              ))}
            </div>

            <div className="p-5">
              {isEditing ? (
                <textarea
                  value={editContent}
                  onChange={(e) => setEditContent(e.target.value)}
                  className="w-full min-h-[250px] p-4 text-[14px] text-[var(--text-primary)] bg-[var(--surface)] border border-[var(--border-strong)] rounded-[var(--radius-sm)] focus:outline-none focus:ring-2 focus:ring-[var(--primary)]/20 focus:border-[var(--primary)] resize-y"
                  placeholder="Enter markdown content..."
                />
              ) : (
                <div className="prose prose-sm max-w-none prose-headings:font-semibold prose-a:text-[var(--primary)]">
                  <CaseWikiMarkdown matterId={matterId} readOnly={readOnly}>{textContent}</CaseWikiMarkdown>
                </div>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}
