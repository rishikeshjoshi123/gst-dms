'use client'

import { useState, useRef, useTransition } from 'react'
import { uploadToInbox } from '@/lib/actions/inbox'
import { UploadCloud, File as FileIcon, X, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { useRouter } from 'next/navigation'

interface UploadModalProps {
  onClose: () => void
  matterId?: string
}

export function UploadModal({ onClose, matterId }: UploadModalProps) {
  const [isDragging, setIsDragging] = useState(false)
  const [files, setFiles] = useState<File[]>([])
  const [uploadState, setUploadState] = useState<'idle' | 'uploading' | 'error'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const inputRef = useRef<HTMLInputElement>(null)
  const router = useRouter()

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
    const droppedFiles = Array.from(e.dataTransfer.files).filter(f => f.type === 'application/pdf')
    setFiles(prev => [...prev, ...droppedFiles])
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files) {
      const selectedFiles = Array.from(e.target.files).filter(f => f.type === 'application/pdf')
      setFiles(prev => [...prev, ...selectedFiles])
    }
    if (inputRef.current) inputRef.current.value = ''
  }

  function removeFile(index: number) {
    setFiles(prev => prev.filter((_, i) => i !== index))
  }

  async function handleUpload() {
    if (files.length === 0) return
    setUploadState('uploading')
    setErrorMessage(null)

    let hasError = false
    startTransition(async () => {
      for (const file of files) {
        const formData = new FormData()
        formData.append('file', file)
        if (matterId) {
          formData.append('matterId', matterId)
        }
        
        const res = await uploadToInbox(formData)
        if (res.error) {
          console.error(res.error)
          setErrorMessage(res.error)
          hasError = true
          break
        }
      }

      if (!hasError) {
        setFiles([])
        router.refresh() // Tell layout/page to re-fetch
        onClose() // Close modal immediately to see live pulse
      } else {
        setUploadState('error')
      }
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm animate-in fade-in duration-200">
      <div className="bg-surface rounded-lg shadow-xl border border-border w-[90%] max-w-lg overflow-hidden flex flex-col animate-in zoom-in-95 duration-200">
        <div className="flex items-center justify-between p-4 border-b border-border bg-bg">
          <div>
            <h2 className="text-[18px] font-semibold text-[var(--text-primary)] leading-none">Add Document</h2>
            <p className="text-[14px] text-[var(--text-muted)] mt-1">Upload PDF documents to the Document Hub.</p>
          </div>
          <button 
            onClick={onClose}
            className="p-1 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--border-subtle)] transition-colors"
          >
            <X size={20} />
          </button>
        </div>
        
        <div className="p-6 flex flex-col gap-4">
          <div
            className={cn(
              "relative flex flex-col items-center justify-center p-8 border-2 border-dashed rounded-lg transition-colors duration-200",
              isDragging 
                ? "border-primary bg-primary/5" 
                : "border-border-strong bg-surface hover:border-primary/50 hover:bg-bg"
            )}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
          >
            <input 
              ref={inputRef}
              type="file" 
              accept="application/pdf" 
              multiple 
              className="hidden" 
              onChange={handleFileSelect} 
            />
            
            <div className="flex h-14 w-14 items-center justify-center rounded-full bg-bg border border-[var(--border-subtle)] mb-4">
              <UploadCloud size={24} className="text-[var(--text-muted)]" />
            </div>
            
            <p className="text-[14px] font-medium text-[var(--text-primary)]">
              Drag & drop PDF files here
            </p>
            <p className="text-[12px] text-[var(--text-muted)] mt-1 mb-5">
              Or click the button below to browse
            </p>
            
            <Button 
              type="button" 
              variant="secondary" 
              size="sm"
              onClick={() => inputRef.current?.click()}
              disabled={uploadState === 'uploading'}
            >
              Select Files
            </Button>
          </div>

          {files.length > 0 && (
            <div className="flex flex-col gap-3 mt-2">
              <div className="grid gap-2 max-h-[160px] overflow-y-auto pr-1">
                {files.map((f, i) => (
                  <div key={i} className="flex items-center justify-between p-3 rounded-md border border-[var(--border-subtle)] bg-surface shadow-sm">
                    <div className="flex items-center gap-3">
                      <div className="p-2 rounded bg-slate-50 border border-slate-100 text-slate-600 shrink-0">
                        <FileIcon size={16} />
                      </div>
                      <div className="flex flex-col min-w-0">
                        <span className="text-[14px] font-medium text-[var(--text-primary)] truncate max-w-[200px] sm:max-w-[300px]">
                          {f.name}
                        </span>
                        <span className="text-[12px] text-[var(--text-muted)] mt-0.5">
                          {(f.size / 1024 / 1024).toFixed(2)} MB
                        </span>
                      </div>
                    </div>
                    <button 
                      onClick={() => removeFile(i)}
                      className="p-1.5 text-[var(--text-muted)] hover:text-[var(--text-primary)] rounded-full hover:bg-[var(--border-subtle)] transition-colors"
                      disabled={uploadState === 'uploading'}
                    >
                      <X size={14} />
                    </button>
                  </div>
                ))}
              </div>

              {uploadState === 'error' && errorMessage && (
                <div className="p-3 bg-red-50 border border-red-200 rounded-md">
                  <p className="text-[12px] text-[var(--danger)]">{errorMessage}</p>
                </div>
              )}

              <div className="flex items-center justify-between mt-2 pt-4 border-t border-[var(--border-subtle)]">
                <span className="text-[12px] font-medium text-[var(--text-muted)]">
                  {files.length} file(s) selected
                </span>
                <Button 
                  onClick={handleUpload} 
                  disabled={uploadState === 'uploading' || isPending}
                  variant="default"
                  className="gap-2"
                >
                  {(uploadState === 'uploading' || isPending) && <Loader2 size={16} className="animate-spin" />}
                  {uploadState === 'uploading' || isPending ? 'Uploading...' : 'Upload Files'}
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
