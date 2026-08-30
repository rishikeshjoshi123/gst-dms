'use client'

import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { Sparkles, Edit2, Check, X, RefreshCw } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import { Button } from '@/components/ui/button'
import { updateWikiSection, triggerWikiGeneration } from '@/lib/actions/wiki'

export function CaseWikiTab({ matterId, initialSections, readOnly = false }: { matterId: string; initialSections: any[]; readOnly?: boolean }) {
  const [sections, setSections] = useState(initialSections)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editContent, setEditContent] = useState<string>('')
  const [isGenerating, setIsGenerating] = useState(false)

  useEffect(() => {
    setSections(initialSections)
  }, [initialSections])

  const handleGenerate = async () => {
    if (readOnly) return
    setIsGenerating(true)
    const toastId = toast.loading('Triggering Case Synthesis...')
    const res = await triggerWikiGeneration(matterId)
    if (res.error) {
      toast.error(res.error, { id: toastId })
      setIsGenerating(false)
    } else {
      toast.success('Synthesis started! Synthesizing the case wiki in the background (takes 1-2 mins).', {
        id: toastId,
        duration: 5000
      })
      // Keep isGenerating true to avoid multi-clicks, it will reset on page reload
    }
  }

  const startEditing = (section: any) => {
    if (readOnly) return
    setEditingId(section.id)
    try {
      const parsed = JSON.parse(section.content || '{}')
      setEditContent(parsed.text || '')
    } catch {
      setEditContent('')
    }
  }

  const saveEdit = async (section: any) => {
    if (readOnly) return
    const toastId = toast.loading('Saving section edits...')
    const res = await updateWikiSection(section.id, editContent, matterId)
    if (res.error) {
      toast.error(res.error, { id: toastId })
    } else {
      toast.success('Section updated successfully!', { id: toastId })
      // Update local state to reflect changes immediately
      setSections(prev => prev.map(s => {
        if (s.id === section.id) {
          return { ...s, content: JSON.stringify({ text: editContent }), is_user_edited: true }
        }
        return s
      }))
      setEditingId(null)
    }
  }

  if (sections.length === 0) {
    return (
      <div className="py-16 flex flex-col items-center justify-center text-[var(--text-muted)] border border-dashed border-[var(--border-strong)] rounded-lg bg-[var(--surface)]">
        <Sparkles size={40} className="mb-4 text-[var(--primary)] opacity-80" />
        <h3 className="text-xl font-medium text-[var(--text-primary)] mb-2">CaseWiki</h3>
        <p className="text-sm max-w-md text-center mb-6 leading-relaxed">
          The CaseWiki provides an automated synthesized summary of the entire matter history, key arguments, and outstanding tasks based on uploaded documents.
        </p>
        {!readOnly && <Button onClick={handleGenerate} disabled={isGenerating} className="bg-[var(--primary)] hover:opacity-90 text-white">
          {isGenerating ? (
            <>
              <RefreshCw size={16} className="mr-2 animate-spin" />
              Synthesizing Wiki...
            </>
          ) : (
            <>
              <Sparkles size={16} className="mr-2" />
              Generate Case Wiki
            </>
          )}
        </Button>}
      </div>
    )
  }

  const orderedKeys = ['executive_summary', 'key_arguments', 'outstanding_tasks']
  const orderedSections = orderedKeys
    .map(key => sections.find(s => s.section_key === key))
    .filter(Boolean)

  return (
    <div className="flex flex-col gap-6 py-2">
      {!readOnly && <div className="flex justify-end mb-2">
        <Button onClick={handleGenerate} disabled={isGenerating} variant="outline" size="sm">
          {isGenerating ? (
            <RefreshCw size={14} className="mr-2 animate-spin" />
          ) : (
            <RefreshCw size={14} className="mr-2" />
          )}
          {isGenerating ? 'Regenerating...' : 'Regenerate Wiki'}
        </Button>
      </div>}
      
      {orderedSections.map((section: any) => {
        let textContent = ''
        try {
          const parsed = JSON.parse(section.content || '{}')
          textContent = parsed.text || ''
        } catch {}

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
                  <ReactMarkdown>{textContent}</ReactMarkdown>
                </div>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}
