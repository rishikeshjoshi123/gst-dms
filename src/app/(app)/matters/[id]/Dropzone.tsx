'use client'

import { useState, useRef, useTransition } from 'react'
import { uploadToMatter } from '@/lib/actions/document'
import { UploadCloud, File as FileIcon, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { useRouter } from 'next/navigation'

type QueuedUpload = { file: File; idempotencyKey: string; error?: string; retryable?: boolean }

export function Dropzone({ matterId }: { matterId: string }) {
  const [isDragging, setIsDragging] = useState(false)
  const [files, setFiles] = useState<QueuedUpload[]>([])
  const [uploadState, setUploadState] = useState<'idle' | 'uploading' | 'success' | 'error'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [, startTransition] = useTransition()
  const router = useRouter()
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
    const droppedFiles = queueFiles(e.dataTransfer.files)
    setFiles(prev => [...prev, ...droppedFiles])
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files) {
      const selectedFiles = queueFiles(e.target.files)
      setFiles(prev => [...prev, ...selectedFiles])
    }
  }

  function removeFile(index: number) {
    setFiles(prev => prev.filter((_, i) => i !== index))
  }

  async function handleUpload() {
    if (files.length === 0) return

    setUploadState('uploading')
    setErrorMessage(null)

    startTransition(async () => {
      let successCount = 0
      let errorCount = 0

      const retryableKeys = new Set<string>()
      const terminalMessages: string[] = []
      for (const queuedFile of files) {
        const formData = new FormData()
        formData.append('file', queuedFile.file)
        formData.append('upload_idempotency_key', queuedFile.idempotencyKey)
        const result = await uploadToMatter(matterId, formData)
        if ('error' in result) {
          errorCount++
          if (result.retryable) {
            retryableKeys.add(queuedFile.idempotencyKey)
          } else {
            terminalMessages.push(`${queuedFile.file.name}: ${result.error}`)
          }
        } else {
          successCount++
        }
      }

      if (errorCount > 0) {
        setUploadState(retryableKeys.size > 0 ? 'error' : 'idle')
        setErrorMessage([
          retryableKeys.size > 0 ? `${retryableKeys.size} file${retryableKeys.size === 1 ? '' : 's'} can be retried.` : null,
          ...terminalMessages,
        ].filter(Boolean).join(' '))
        // Only transient storage/transport failures remain in the tray. Their
        // original idempotency keys resume the same reserved asset/session.
        setFiles(current => current
          .filter(({ idempotencyKey }) => retryableKeys.has(idempotencyKey))
          .map(upload => ({ ...upload, error: 'Upload interrupted. Retry this file.', retryable: true })))
      } else {
        if (successCount > 0) {
          setUploadState('success')
          setFiles([])
          router.refresh()
          setTimeout(() => setUploadState('idle'), 3000)
        } else {
          setUploadState('idle')
          setFiles([])
        }
      }
    })
  }

  return (
    <div className="flex flex-col gap-4">
      <div
        className={cn(
          "flex flex-col items-center justify-center p-8 border-2 border-dashed rounded-[var(--radius-md)] transition-colors",
          isDragging ? "border-[--accent] bg-[--accent-muted]" : "border-[--border-subtle] bg-[--bg-surface] hover:border-[--border-default]"
        )}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        onClick={() => inputRef.current?.click()}
      >
        <UploadCloud size={32} className="text-[--text-muted] mb-3" />
        <p className="text-sm font-medium text-[--text-primary]">
          Drag and drop PDF files here
        </p>
        <p className="text-xs text-[--text-muted] mt-1">
          or click to browse
        </p>
        <input
          type="file"
          ref={inputRef}
          onChange={handleFileSelect}
          accept="application/pdf"
          multiple
          className="hidden"
        />
      </div>

      {(errorMessage || uploadState === 'success') && (
        <div aria-live="polite">
          {errorMessage && <p className="text-sm text-[--danger]">{errorMessage}</p>}
          {uploadState === 'success' && <p className="text-sm text-[--success]">Upload successful. System processing started.</p>}
        </div>
      )}

      {files.length > 0 && (
        <div className="flex flex-col gap-2">
          {files.map(({ file, idempotencyKey, error }, i) => (
            <div key={idempotencyKey} className="flex items-center justify-between p-3 rounded-md border border-[--border-subtle] bg-[--bg-surface]">
              <div className="flex min-w-0 items-center gap-3">
                <FileIcon size={16} className="text-[--text-muted]" />
                <div className="min-w-0">
                  <span className="block text-sm text-[--text-primary] truncate max-w-[200px] sm:max-w-xs">{file.name}</span>
                  {error && <span className="block text-xs text-[--danger]">{error}</span>}
                </div>
                <span className="shrink-0 text-xs text-[--text-muted]">{(file.size / 1024 / 1024).toFixed(2)} MB</span>
              </div>
              <button aria-label={`Remove ${file.name}`} onClick={() => removeFile(i)} className="min-h-11 min-w-11 text-[--text-muted] hover:text-[--danger] transition-colors" disabled={uploadState === 'uploading'}>
                <X size={16} />
              </button>
            </div>
          ))}

          <div className="flex items-center justify-between mt-2">
            <div />
            <Button onClick={handleUpload} loading={uploadState === 'uploading'}>
              {uploadState === 'uploading' ? 'Uploading...' : `Upload ${files.length} file${files.length !== 1 ? 's' : ''}`}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

function queueFiles(fileList: FileList) {
  return Array.from(fileList)
    // Desktop browsers frequently omit MIME for dragged files. Filename is
    // only an admission hint; the server validates the stored PDF signature.
    .filter(file => file.type === 'application/pdf' || file.type === '' || /\.pdf$/i.test(file.name))
    .map(file => ({ file, idempotencyKey: crypto.randomUUID() }))
}
