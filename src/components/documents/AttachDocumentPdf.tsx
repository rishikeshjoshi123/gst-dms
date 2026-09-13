'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { getDocumentAttachmentState } from '@/lib/actions/document'
import { documentUploadIdempotencyKey, uploadDocumentFile, type DocumentUploadControl } from '@/lib/uploads/resumable-document-upload'

const outcomes: Record<string, string> = {
  source_already_attached: 'Another PDF was attached first. Your upload did not replace it.',
  duplicate_reference: 'This exact PDF is already attached to a document. No file was attached here.',
  duplicate: 'This exact PDF already exists. No file was attached here.',
  stale_target: 'The document changed while uploading. No file was attached.',
  target_unavailable: 'The document is no longer available for attachment.',
  upload_unavailable: 'The PDF could not be validated. Choose a valid PDF and try again.',
  not_allowed: 'Your permission to attach this PDF is no longer available.',
  expired: 'This unfinished upload expired. Choose the PDF again.',
  cancelled: 'Upload cancelled. No file was attached.',
}

export function AttachDocumentPdf({ documentId }: { documentId: string }) {
  const router = useRouter()
  const [file, setFile] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<number | null>(null)
  const [message, setMessage] = useState('Your document details, notes, and relationships will be kept.')
  const [intakeId, setIntakeId] = useState<string | null>(null)
  const [canCancel, setCanCancel] = useState(false)
  const control = useRef<DocumentUploadControl | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const restoreFileFocus = useRef(false)
  useEffect(() => {
    if (!busy && restoreFileFocus.current) {
      restoreFileFocus.current = false
      fileInput.current?.focus()
    }
  }, [busy])

  async function checkStatus(id: string) {
    const state = await getDocumentAttachmentState(documentId, id)
    if (state?.state === 'attached') {
      setMessage('PDF attached. Opening the current version…')
      router.refresh()
    } else if (state?.state === 'validating') {
      setMessage('Upload received. The PDF is being validated before attachment.')
    } else {
      setIntakeId(null)
      setMessage(outcomes[state?.state ?? 'target_unavailable'] ?? 'Attachment could not be completed. No existing file was replaced.')
    }
  }

  async function submit() {
    if (!file || busy) return
    setBusy(true)
    setMessage('Preparing private PDF upload…')
    try {
      const key = documentUploadIdempotencyKey(file, null, documentId)
      const result = await uploadDocumentFile(file, null, key, setProgress, next => {
        control.current = next
        setCanCancel(next !== null)
      }, documentId)
      if ('error' in result) setMessage(result.error)
      else if (result.intakeId) {
        setIntakeId(result.intakeId)
        await checkStatus(result.intakeId)
      } else setMessage('Upload cancelled. No file was attached.')
    } catch {
      setMessage('The upload could not finish. Retry with this file to resume safely.')
    } finally {
      setBusy(false)
      setProgress(null)
      setCanCancel(false)
      control.current = null
    }
  }

  return (
    <form className="w-full min-w-0 max-w-md space-y-3 text-left" onSubmit={event => { event.preventDefault(); void submit() }} aria-label="Attach first PDF">
      <Label htmlFor={`attachment-${documentId}`}>PDF file</Label>
      <Input ref={fileInput} id={`attachment-${documentId}`} type="file" accept="application/pdf,.pdf" disabled={busy || !!intakeId} className="min-h-11 w-full min-w-0" aria-describedby={`attachment-status-${documentId}`} onChange={event => { setFile(event.target.files?.[0] ?? null); setMessage('Your document details, notes, and relationships will be kept.') }} />
      {file && <p className="break-all text-xs text-[var(--text-secondary)]">{file.name}</p>}
      <p id={`attachment-status-${documentId}`} role="status" className="break-words text-sm text-[var(--text-secondary)]">{progress === null ? message : `Uploading PDF · ${progress}%`}</p>
      <div className="flex flex-wrap gap-2">
        {!intakeId && <Button type="submit" disabled={!file || busy} className="min-h-11">{busy ? 'Attaching PDF…' : 'Attach PDF'}</Button>}
        {intakeId && <Button type="button" disabled={busy} className="min-h-11" onClick={async () => {
          setBusy(true)
          try { await checkStatus(intakeId) } catch { setMessage('Could not check attachment status. Try again.') } finally { setBusy(false) }
        }}>{busy ? 'Checking attachment…' : 'Check attachment status'}</Button>}
        {canCancel && <Button type="button" variant="outline" className="min-h-11" onClick={async () => {
          restoreFileFocus.current = true
          setCanCancel(false)
          try { await control.current?.cancel() } catch { setMessage('Cancellation could not be confirmed. Check attachment status before retrying.') }
        }}>Cancel upload</Button>}
      </div>
    </form>
  )
}
