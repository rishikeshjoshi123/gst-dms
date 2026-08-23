'use client'

import { useState, useRef, useCallback, useEffect } from 'react'
import { uploadToInbox } from '@/lib/actions/inbox'
import { X, Loader2, FileText, UploadCloud, CheckCircle2, AlertCircle, Sparkles, Plus, FolderOpen, Inbox } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useRouter } from 'next/navigation'

interface UploadModalProps {
  onClose: () => void
  matterId?: string
  matterName?: string
  inline?: boolean
}

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`
}

type FileStatus = 'pending' | 'uploading' | 'done' | 'error'

interface FileEntry {
  file: File
  id: string
  status: FileStatus
  error?: string
}

export function UploadModal({ onClose, matterId, matterName, inline = false }: UploadModalProps) {
  const [isDragging, setIsDragging] = useState(false)
  const [entries, setEntries] = useState<FileEntry[]>([])
  const [isUploading, setIsUploading] = useState(false)
  const [allDone, setAllDone] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const router = useRouter()

  const addFiles = useCallback((newFiles: File[]) => {
    const pdfs = newFiles.filter(f => f.type === 'application/pdf')
    const newEntries: FileEntry[] = pdfs.map(f => ({
      file: f,
      id: `${f.name}-${f.size}-${Date.now()}-${Math.random()}`,
      status: 'pending'
    }))
    setEntries(prev => {
      // Deduplicate by name+size
      const existing = new Set(prev.map(e => `${e.file.name}-${e.file.size}`))
      return [...prev, ...newEntries.filter(e => !existing.has(`${e.file.name}-${e.file.size}`))]
    })
    setAllDone(false)
  }, [])

  function handleDragOver(e: React.DragEvent) {
    e.preventDefault()
    setIsDragging(true)
  }
  function handleDragLeave(e: React.DragEvent) {
    e.preventDefault()
    setIsDragging(false)
  }
  function handleDrop(e: React.DragEvent) {
    e.preventDefault()
    setIsDragging(false)
    addFiles(Array.from(e.dataTransfer.files))
  }
  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files) addFiles(Array.from(e.target.files))
    if (inputRef.current) inputRef.current.value = ''
  }
  function removeEntry(id: string) {
    setEntries(prev => prev.filter(e => e.id !== id))
  }

  function retryFailed() {
    setEntries(prev => prev.map(entry => entry.status === 'error'
      ? { ...entry, status: 'pending', error: undefined }
      : entry,
    ))
    setAllDone(false)
  }

  async function handleUpload() {
    const pending = entries.filter(e => e.status === 'pending')
    if (pending.length === 0) return
    setIsUploading(true)

    let hasError = false
    for (const entry of pending) {
      setEntries(prev => prev.map(e => e.id === entry.id ? { ...e, status: 'uploading' } : e))

      const formData = new FormData()
      formData.append('file', entry.file)
      if (matterId) formData.append('matterId', matterId)

      const res = await uploadToInbox(formData)
      if (res.error) {
        setEntries(prev => prev.map(e => e.id === entry.id ? { ...e, status: 'error', error: res.error } : e))
        hasError = true
      } else {
        setEntries(prev => prev.map(e => e.id === entry.id ? { ...e, status: 'done' } : e))
      }
    }

    setIsUploading(false)
    if (!hasError) {
      setAllDone(true)
      router.refresh()
      // Once staging succeeds, return the user to the live queue immediately.
      // Processing continues in the background and is shown there via realtime.
      onClose()
    }
  }

  const pendingCount = entries.filter(e => e.status === 'pending').length
  const doneCount = entries.filter(e => e.status === 'done').length
  const errorCount = entries.filter(e => e.status === 'error').length
  const hasEntries = entries.length > 0

  // The active intake is the queue itself, so selecting files is enough to
  // begin transfer. There is no second "submit" decision to make.
  useEffect(() => {
    if (!isUploading && entries.some(entry => entry.status === 'pending')) {
      void handleUpload()
    }
    // handleUpload intentionally reads the latest entries snapshot above.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entries, isUploading])

  return (
    <div
      className={cn(
        inline ? 'relative z-20 w-full animate-in fade-in slide-in-from-top-2 duration-200' : 'fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-md animate-in fade-in duration-200',
      )}
      onClick={(e) => { if (!inline && e.target === e.currentTarget && !isUploading) onClose() }}
    >
      <div className={cn(
        'relative flex flex-col overflow-hidden rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)]',
        inline ? 'w-full shadow-sm' : 'w-[92%] max-w-[500px] shadow-2xl animate-in zoom-in-95 duration-200',
      )}>
        {/* Semantic processing accent */}
        <div className="h-1 w-full bg-[var(--primary)] shrink-0" />

        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-5 pb-4">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-[var(--radius-sm)] flex items-center justify-center shrink-0 bg-[var(--accent-muted)]"
            >
              <UploadCloud size={18} className="text-[var(--primary)]" />
            </div>
            <div>
              <h2 className="text-[17px] font-bold text-[var(--text-primary)] leading-none">Add Documents</h2>
              <p className="text-[12px] text-[var(--text-muted)] mt-1">PDF files only · Multiple files supported</p>
            </div>
          </div>
          <button
            onClick={onClose}
            disabled={isUploading}
            className="p-1.5 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface-hover)] transition-colors disabled:opacity-40"
          >
            <X size={16} />
          </button>
        </div>

        {/* Body */}
        <div className="px-6 pb-6 flex flex-col gap-4">
          <div className={cn(
            'flex items-start gap-3 rounded-[var(--radius-md)] border p-3 text-[12px]',
            matterId
              ? 'border-[var(--primary)]/25 bg-[var(--primary)]/5'
              : 'border-[var(--border)] bg-[var(--surface-hover)]',
          )}>
            <div className={cn(
              'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg',
              matterId ? 'bg-[var(--primary)]/15 text-[var(--primary)]' : 'bg-[var(--surface)] text-[var(--text-secondary)]',
            )}>
              {matterId ? <FolderOpen size={14} /> : <Inbox size={14} />}
            </div>
            <div>
              <p className="font-bold text-[var(--text-primary)]">
                {matterId ? `Destination: ${matterName ?? 'Selected matter'}` : 'Destination: Global Inbox'}
              </p>
              <p className="mt-0.5 leading-relaxed text-[var(--text-secondary)]">
                {matterId
                  ? 'These files will be analysed and routed only to this matter. They will not be mixed into global triage.'
                  : 'These files will enter global triage, where a suggested matter is reviewed before filing.'}
              </p>
            </div>
          </div>

          {/* Drop zone */}
          <div
            onClick={() => !isUploading && inputRef.current?.click()}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            className={cn(
              'relative flex flex-col items-center justify-center rounded-[var(--radius-md)] border-2 border-dashed transition-all duration-200 cursor-pointer select-none',
              hasEntries ? 'py-5' : 'py-12',
              isDragging
                ? 'border-[var(--primary)] bg-[var(--primary)]/8 scale-[1.01]'
                : 'border-[var(--border-strong)] hover:border-[var(--primary)]/60 hover:bg-[var(--primary)]/4'
            )}
          >
            <input
              ref={inputRef}
              type="file"
              accept="application/pdf"
              multiple
              className="hidden"
              onChange={handleFileSelect}
              disabled={isUploading}
            />

            {isDragging ? (
              <div className="flex flex-col items-center gap-2 pointer-events-none animate-in zoom-in-95 duration-150">
                <div className="w-12 h-12 rounded-[var(--radius-md)] bg-[var(--primary)]/15 flex items-center justify-center">
                  <UploadCloud size={22} className="text-[var(--primary)]" />
                </div>
                <p className="text-[14px] font-bold text-[var(--primary)]">Drop files here</p>
              </div>
            ) : hasEntries ? (
              <div className="flex items-center gap-2 text-[13px] text-[var(--text-muted)]">
                <Plus size={14} />
                <span>Click or drag to add more PDF files</span>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-3 pointer-events-none">
                <div className="relative">
                  <div
                    className="w-16 h-16 rounded-[var(--radius-md)] bg-[var(--accent-muted)] flex items-center justify-center"
                  >
                    <UploadCloud size={28} className="text-[var(--primary)]" />
                  </div>
                  <Sparkles size={12} className="absolute -top-1 -right-1 text-[var(--primary)] animate-pulse" />
                </div>
                <div className="text-center">
                  <p className="text-[15px] font-bold text-[var(--text-primary)]">Drop PDF files here</p>
                  <p className="text-[13px] text-[var(--text-muted)] mt-1">or click to browse from your computer</p>
                </div>
                <div className="flex items-center gap-1.5 px-4 py-2 rounded-[var(--radius-sm)] bg-[var(--primary)] text-white text-[13px] font-semibold mt-1 shadow-sm">
                  <UploadCloud size={13} />
                  Browse Files
                </div>
              </div>
            )}
          </div>

          {/* File list */}
          {hasEntries && (
            <div className="flex flex-col gap-2 max-h-[220px] overflow-y-auto custom-scrollbar pr-0.5">
              {entries.map((entry) => {
                const isDone = entry.status === 'done'
                const isError = entry.status === 'error'
                const isUpl = entry.status === 'uploading'

                return (
                  <div
                    key={entry.id}
                    className={cn(
                      'flex items-center gap-3 p-3 rounded-[var(--radius-md)] border transition-all duration-300',
                      isDone
                        ? 'border-[color-mix(in_srgb,var(--success)_20%,transparent)] bg-[var(--success-muted)]'
                        : isError
                        ? 'border-[color-mix(in_srgb,var(--danger)_20%,transparent)] bg-[var(--danger-muted)]'
                        : isUpl
                        ? 'border-[color-mix(in_srgb,var(--primary)_40%,var(--border))] bg-[var(--accent-muted)] shadow-[var(--shadow-sm)]'
                        : 'border-[var(--border)] bg-[var(--surface-hover)]'
                    )}
                  >
                    {/* Icon */}
                    <div className={cn(
                      'w-9 h-9 rounded-[var(--radius-sm)] flex items-center justify-center shrink-0 transition-all',
                      isDone ? 'bg-[var(--success-muted)]' : isError ? 'bg-[var(--danger-muted)]' : isUpl ? 'bg-[var(--primary)]/15' : 'bg-[var(--surface)]'
                    )}>
                      {isDone ? (
                        <CheckCircle2 size={16} className="text-[var(--success)]" />
                      ) : isError ? (
                        <AlertCircle size={16} className="text-[var(--danger)]" />
                      ) : isUpl ? (
                        <Loader2 size={16} className="text-[var(--primary)] animate-spin" />
                      ) : (
                        <FileText size={16} className="text-[var(--text-muted)]" />
                      )}
                    </div>

                    {/* Name + size */}
                    <div className="flex-1 min-w-0 flex flex-col">
                      <span className={cn(
                        'text-[13px] font-semibold truncate',
                        isDone ? 'text-[var(--success)]' : isError ? 'text-[var(--danger)]' : 'text-[var(--text-primary)]'
                      )}>
                        {entry.file.name}
                      </span>
                      <span className="text-[11px] text-[var(--text-muted)] mt-0.5">
                        {isError ? (entry.error || 'Upload failed') : isDone ? 'Uploaded successfully' : isUpl ? 'Uploading…' : formatBytes(entry.file.size)}
                      </span>
                    </div>

                    {/* Remove */}
                    {!isUpl && !isDone && (
                      <button
                        onClick={() => removeEntry(entry.id)}
                        disabled={isUploading}
                        className="p-1.5 rounded-lg text-[var(--text-muted)] hover:text-[var(--text-primary)] hover:bg-[var(--surface)] transition-colors shrink-0 disabled:opacity-40"
                      >
                        <X size={13} />
                      </button>
                    )}
                  </div>
                )
              })}
            </div>
          )}

          {/* Uploads start as soon as files are selected. The footer is status
              and recovery only; it never asks the user to submit again. */}
          {hasEntries && (
            <div className="flex items-center gap-3 pt-3 border-t border-[var(--border)]">
              <div className="flex-1 text-[12px] text-[var(--text-muted)]">
                {allDone ? (
                  <span className="text-[var(--success)] font-semibold flex items-center gap-1.5">
                    <CheckCircle2 size={13} /> All files uploaded!
                  </span>
                ) : errorCount > 0 ? (
                  <span className="text-[var(--danger)] font-semibold">{errorCount} failed · {doneCount} done</span>
                ) : (
                  <span>{pendingCount} pending · {doneCount} done</span>
                )}
              </div>
              {errorCount > 0 && !isUploading && (
                <button
                  onClick={retryFailed}
                  className="h-9 px-3 rounded-[var(--radius-sm)] border border-[var(--border)] text-[12px] font-semibold text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)] transition-colors"
                >
                  Retry failed
                </button>
              )}
              {allDone && (
                <button
                  onClick={onClose}
                  className="h-9 px-5 rounded-[var(--radius-sm)] bg-[var(--primary)] text-[13px] font-bold text-white hover:opacity-90 transition-opacity"
                >
                  Done
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
