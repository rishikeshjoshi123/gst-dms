import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('client-owned PDF sources renew through their signing caller', async () => {
  const [hub, modal, inbox] = await Promise.all([
    readFile(new URL('../../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../../app/(app)/inbox/DocumentViewerModal.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../../app/(app)/inbox/InboxClientView.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(hub, /async function openSource\(\): Promise<string \| null>/)
  assert.match(hub, /setSourceUrl\(result\.url\)\s+return result\.url/)
  assert.match(hub, /<PdfViewer url=\{sourceUrl\} onRequestSourceRefresh=\{openSource\}/)
  assert.match(modal, /onRequestSourceRefresh\?: \(\) => Promise<string \| null>/)
  assert.match(modal, /<PdfViewer url=\{url\} onRequestSourceRefresh=\{onRequestSourceRefresh\}/)
  assert.match(inbox, /async function handleViewDocument\(\): Promise<string \| null>/)
  assert.match(inbox, /setViewDocumentUrl\(res\.url\)\s+return res\.url/)
  assert.match(inbox, /onRequestSourceRefresh=\{handleViewDocument\}/)
})

test('the server-owned document route can recover an initial signing failure', async () => {
  const page = await readFile(new URL('../../app/(app)/documents/[docId]/page.tsx', import.meta.url), 'utf8')

  assert.match(page, /signedDocument\.code !== 'ok'[\s\S]*pdfSourceFailureFromAccessCode\(signedDocument\.code\)/)
  assert.match(page, /signedDocumentError \? \(\s*<PdfViewer url=\{null\}[^>]*initialFailure=\{signedDocumentFailure\}/)
  assert.match(page, /<PdfViewer url=\{signedDocumentUrl\} initialPage=/)
})
