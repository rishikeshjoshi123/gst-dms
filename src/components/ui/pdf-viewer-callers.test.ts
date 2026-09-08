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
  const [page, workbench] = await Promise.all([
    readFile(new URL('../../app/(app)/documents/[docId]/page.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../documents/CanonicalDocumentWorkbench.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(page, /signedDocument\.code !== 'ok'[\s\S]*pdfSourceFailureFromAccessCode\(signedDocument\.code\)/)
  assert.match(page, /<CanonicalDocumentWorkbench/)
  assert.match(workbench, /renewCanonicalDocumentVersionSource\(\{/)
  assert.match(workbench, /documentVersionId: source\.versionId/)
  assert.match(workbench, /quoteSource=\{!readOnly && source/)
})

test('quotation drafts are source-keyed, open Notes on selection, and are consumed explicitly', async () => {
  const [workbench, detail] = await Promise.all([
    readFile(new URL('../documents/CanonicalDocumentWorkbench.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../matters/TimelineDocumentDetail.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(workbench, /activeQuotationDraft = quotationDraft\?\.sourceIdentity === sourceIdentity/)
  assert.match(workbench, /setQuotationDraft\(\{ sourceIdentity, selection \}\)[\s\S]*setInspectorTab\('notes'\)/)
  assert.match(workbench, /onQuotationDraftConsumed=\{\(\) => setQuotationDraft\(null\)\}/)
  assert.match(detail, /quotationDraft\.documentVersionId === displayedSource\?\.versionId/)
  assert.match(detail, /onQuotationDraftConsumed\?\.\(\)/)
  assert.doesNotMatch(detail, /setActiveQuote|SET_PDF_QUOTE/)
})

test('the document note composer retains its idempotency key only for an unchanged retry payload', async () => {
  const detail = await readFile(new URL('../matters/TimelineDocumentDetail.tsx', import.meta.url), 'utf8')

  assert.match(detail, /const noteCreateIdempotencyKey = useRef<string \| null>\(null\)/)
  assert.match(detail, /if \(!noteCreateIdempotencyKey\.current\) noteCreateIdempotencyKey\.current = crypto\.randomUUID\(\)/)
  assert.match(detail, /idempotencyKey,\s*\}\)/)
  assert.match(detail, /if \(res\.error\) \{[\s\S]*toast\.error[\s\S]*\} else \{\s*noteCreateIdempotencyKey\.current = null/)
  assert.match(detail, /activeQuote\?\.documentVersionId, activeQuote\?\.pageNumber, activeQuote\?\.text/)
  assert.match(detail, /e\.target\.value !== newNoteContent\) noteCreateIdempotencyKey\.current = null/)
  assert.match(detail, /e\.target\.value !== newNoteType\) noteCreateIdempotencyKey\.current = null/)
})
