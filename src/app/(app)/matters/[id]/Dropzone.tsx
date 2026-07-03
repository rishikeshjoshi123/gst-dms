'use client'

import { useState, useRef, useTransition } from 'react'
import { uploadToMatter } from '@/lib/actions/document'
import { UploadCloud, File as FileIcon, X, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { useRouter } from 'next/navigation'

export function Dropzone({ matterId }: { matterId: string }) {
  const [isDragging, setIsDragging] = useState(false)
  const [files, setFiles] = useState<File[]>([])
  const [uploadState, setUploadState] = useState<'idle' | 'uploading' | 'success' | 'error'>('idle')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [isPending, startTransition] = useTransition()
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
    const droppedFiles = Array.from(e.dataTransfer.files).filter(f => f.type === 'application/pdf')
    setFiles(prev => [...prev, ...droppedFiles])
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files) {
      const selectedFiles = Array.from(e.target.files).filter(f => f.type === 'application/pdf')
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

      for (const file of files) {
        const formData = new FormData()
        formData.append('file', file)
        const result = await uploadToMatter(matterId, formData)
        if (result.error) {
          errorCount++
        } else {
          successCount++
        }
      }

      if (errorCount > 0) {
        setUploadState('error')
        setErrorMessage(`Failed to upload ${errorCount} files.`)
      } else {
        setUploadState('success')
        setFiles([])
        router.refresh()
        // Simple success timeout
        setTimeout(() => setUploadState('idle'), 3000)
      }
    })
  }

  return (
    <div className="flex flex-col gap-4">
      <div
        className={cn(
          "flex flex-col items-center justify-center p-8 border-2 border-dashed rounded-xl transition-colors",
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

      {files.length > 0 && (
        <div className="flex flex-col gap-2">
          {files.map((file, i) => (
            <div key={i} className="flex items-center justify-between p-3 rounded-md border border-[--border-subtle] bg-[--bg-surface]">
              <div className="flex items-center gap-3">
                <FileIcon size={16} className="text-[--text-muted]" />
                <span className="text-sm text-[--text-primary] truncate max-w-[200px] sm:max-w-xs">{file.name}</span>
                <span className="text-xs text-[--text-muted]">{(file.size / 1024 / 1024).toFixed(2)} MB</span>
              </div>
              <button onClick={() => removeFile(i)} className="text-[--text-muted] hover:text-[--danger] transition-colors" disabled={uploadState === 'uploading'}>
                <X size={16} />
              </button>
            </div>
          ))}

          <div className="flex items-center justify-between mt-2">
            <div>
              {uploadState === 'error' && <p className="text-sm text-[--danger]">{errorMessage}</p>}
              {uploadState === 'success' && <p className="text-sm text-[--success]">Upload successful. AI processing started.</p>}
            </div>
            <Button onClick={handleUpload} loading={uploadState === 'uploading'}>
              {uploadState === 'uploading' ? 'Uploading...' : `Upload ${files.length} file${files.length !== 1 ? 's' : ''}`}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
