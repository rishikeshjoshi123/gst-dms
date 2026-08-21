'use client'

import { useState, useRef, useTransition } from 'react'
import { uploadToInbox } from '@/lib/actions/inbox'
import { checkExactDuplicate } from '@/lib/actions/document'
import { calculateFileHash } from '@/lib/utils/hash'
import { toast } from 'sonner'
import { UploadCloud, File as FileIcon, X, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'

export function GlobalDropzone() {
  const [isDragging, setIsDragging] = useState(false)
  const [files, setFiles] = useState<File[]>([])
  const [uploadState, setUploadState] = useState<'idle' | 'uploading' | 'success' | 'error'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
  const inputRef = useRef<HTMLInputElement>(null)

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
      let uploadedCount = 0
      
      for (const file of files) {
        // Client-side SHA-256 check
        const sha256 = await calculateFileHash(file)
        const dupCheck = await checkExactDuplicate(sha256)
        
        if (dupCheck.isDuplicate && dupCheck.duplicateOf) {
          toast.error(`Upload cancelled: "${file.name}" is an exact duplicate of document ${dupCheck.duplicateOf.reference} in "${dupCheck.duplicateOf.matterTitle}".`)
          // We remove this file from the state but continue with others
          setFiles(prev => prev.filter(f => f.name !== file.name))
          continue
        }

        const formData = new FormData()
        formData.append('file', file)
        
        const res = await uploadToInbox(formData)
        if (res.error) {
          console.error(res.error)
          setErrorMessage(res.error)
          hasError = true
          break
        }
        uploadedCount++
      }

      if (!hasError) {
        if (uploadedCount > 0) {
          setUploadState('success')
          setFiles([])
          setTimeout(() => setUploadState('idle'), 3000)
        } else {
          // All files were duplicates and filtered out
          setUploadState('idle')
          setFiles([])
        }
      } else {
        setUploadState('error')
      }
    })
  }

  return (
    <div className="flex flex-col gap-4 mb-8">
      <div className="flex items-center justify-between">
        <h2 className="text-[16px] font-semibold text-[--text-primary]">Quick Upload</h2>
        <span className="text-xs text-[--text-muted]">Upload documents to your Inbox</span>
      </div>
      
      <div
        className={cn(
          "relative flex flex-col items-center justify-center p-6 border-2 border-dashed rounded-lg transition-colors duration-200",
          isDragging 
            ? "border-[--primary] bg-[--primary]/5" 
            : "border-[--border-strong] bg-[--bg-surface] hover:border-[--primary]/50 hover:bg-[--bg-overlay]"
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
        
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-[--bg-muted] mb-3">
          <UploadCloud size={24} className="text-[--text-muted]" />
        </div>
        
        <p className="text-sm font-medium text-[--text-primary]">
          Drag & drop PDF files here
        </p>
        <p className="text-xs text-[--text-muted] mt-1 mb-4">
          Or click the button below to browse
        </p>
        
        <Button 
          type="button" 
          variant="outline" 
          size="sm"
          onClick={() => inputRef.current?.click()}
          disabled={uploadState === 'uploading'}
        >
          Select Files
        </Button>
      </div>

      {files.length > 0 && (
        <div className="flex flex-col gap-3">
          <div className="grid gap-2">
            {files.map((f, i) => (
              <div key={i} className="flex items-center justify-between p-3 rounded border border-[--border-subtle] bg-white">
                <div className="flex items-center gap-3">
                  <div className="p-2 rounded-[var(--radius-sm)] bg-[var(--surface-hover)] text-[var(--text-secondary)] shrink-0">
                    <FileIcon size={16} />
                  </div>
                  <div className="flex flex-col min-w-0">
                    <span className="text-sm font-medium text-[--text-primary] truncate max-w-[200px] sm:max-w-[300px]">
                      {f.name}
                    </span>
                    <span className="text-xs text-[--text-muted]">
                      {(f.size / 1024 / 1024).toFixed(2)} MB
                    </span>
                  </div>
                </div>
                <button 
                  onClick={() => removeFile(i)}
                  className="p-1.5 text-[--text-muted] hover:text-[--text-primary] rounded-full hover:bg-[--bg-overlay] transition-colors"
                  disabled={uploadState === 'uploading'}
                >
                  <X size={14} />
                </button>
              </div>
            ))}
          </div>

          <div className="flex items-center justify-between mt-2">
            <span className="text-xs text-[--text-muted]">
              {files.length} file(s) selected
            </span>
            <Button 
              onClick={handleUpload} 
              disabled={uploadState === 'uploading' || isPending}
              className="gap-2"
            >
              {(uploadState === 'uploading' || isPending) && <Loader2 size={16} className="animate-spin" />}
              {uploadState === 'uploading' || isPending ? 'Uploading...' : 'Upload to Inbox'}
            </Button>
          </div>
          
          {uploadState === 'error' && errorMessage && (
            <p className="text-sm text-[--danger] mt-1">{errorMessage}</p>
          )}
          {uploadState === 'success' && (
            <p className="text-sm text-[--success] mt-1">Upload complete! System processing started.</p>
          )}
        </div>
      )}
    </div>
  )
}
