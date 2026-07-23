'use client'

import { useState } from 'react'
import { toast } from 'sonner'
import { Sparkles, Edit2, Check, X, RefreshCw } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import { Button } from '@/components/ui/button'
import { updateWikiSection, triggerWikiGeneration } from '@/lib/actions/wiki'

export function CaseWikiTab({ matterId, initialSections }: { matterId: string; initialSections: any[] }) {
  const [sections, setSections] = useState(initialSections)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editContent, setEditContent] = useState<string>('')
  const [isGenerating, setIsGenerating] = useState(false)

  const handleGenerate = async () => {
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
    setEditingId(section.id)
    try {
      const parsed = JSON.parse(section.content || '{}')
      setEditContent(parsed.text || '')
    } catch {
      setEditContent('')
    }
  }

  const saveEdit = async (section: any) => {
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
        <Sparkles size={40} className="mb-4 text-blue-500 opacity-80" />
        <h3 className="text-xl font-medium text-[var(--text-primary)] mb-2">CaseWiki</h3>
        <p className="text-sm max-w-md text-center mb-6 leading-relaxed">
          The CaseWiki provides an automated synthesized summary of the entire matter history, key arguments, and outstanding tasks based on uploaded documents.
        </p>
        <Button onClick={handleGenerate} disabled={isGenerating} className="bg-blue-600 hover:bg-blue-700 text-white">
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
        </Button>
      </div>
    )
  }

  const orderedKeys = ['executive_summary', 'key_arguments', 'outstanding_tasks']
  const orderedSections = orderedKeys
    .map(key => sections.find(s => s.section_key === key))
    .filter(Boolean)

  return (
    <div className="flex flex-col gap-6 py-2">
      <div className="flex justify-end mb-2">
        <Button onClick={handleGenerate} disabled={isGenerating} variant="outline" size="sm">
          {isGenerating ? (
            <RefreshCw size={14} className="mr-2 animate-spin" />
          ) : (
            <RefreshCw size={14} className="mr-2" />
          )}
          {isGenerating ? 'Regenerating...' : 'Regenerate Wiki'}
        </Button>
      </div>
      
      {orderedSections.map((section: any) => {
        let textContent = ''
        try {
          const parsed = JSON.parse(section.content || '{}')
          textContent = parsed.text || ''
        } catch {}

        const isEditing = editingId === section.id

        return (
          <div key={section.id} className="flex flex-col bg-[var(--surface)] rounded-xl border border-[var(--border)] overflow-hidden shadow-sm">
            <div className="flex items-center justify-between bg-slate-50 border-b border-[var(--border)] px-5 py-3">
              <div className="flex items-center gap-3">
                <h3 className="text-[16px] font-semibold text-[var(--text-primary)]">{section.title}</h3>
                {section.is_user_edited && (
                  <span className="text-[10px] font-medium uppercase tracking-wider text-amber-600 bg-amber-50 px-2 py-0.5 rounded border border-amber-200">
                    Manually Edited
                  </span>
                )}
              </div>
              
              {!isEditing ? (
                <button onClick={() => startEditing(section)} className="text-[var(--text-muted)] hover:text-blue-600 transition-colors p-1 rounded-md hover:bg-blue-50">
                  <Edit2 size={16} />
                </button>
              ) : (
                <div className="flex items-center gap-2">
                  <button onClick={() => saveEdit(section)} className="text-emerald-600 hover:text-emerald-700 transition-colors p-1 rounded-md hover:bg-emerald-50">
                    <Check size={18} />
                  </button>
                  <button onClick={() => setEditingId(null)} className="text-[var(--text-muted)] hover:text-red-600 transition-colors p-1 rounded-md hover:bg-red-50">
                    <X size={18} />
                  </button>
                </div>
              )}
            </div>

            <div className="p-5">
              {isEditing ? (
                <textarea
                  value={editContent}
                  onChange={(e) => setEditContent(e.target.value)}
                  className="w-full min-h-[250px] p-4 text-[14px] text-[var(--text-primary)] bg-white border border-[var(--border-strong)] rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-y"
                  placeholder="Enter markdown content..."
                />
              ) : (
                <div className="prose prose-sm prose-slate max-w-none prose-headings:font-semibold prose-a:text-blue-600">
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
