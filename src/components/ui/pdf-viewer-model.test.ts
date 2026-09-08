import assert from 'node:assert/strict'
import test from 'node:test'

import {
  clampPdfPage,
  classifyPdfSourceFailure,
  highlightPdfText,
  isPdfPageInRenderWindow,
  isPdfThumbnailInRenderWindow,
  nextPdfSearchBatch,
  normalizePdfSearchQuery,
  pdfThumbnailPages,
  pdfSourceFailureFromAccessCode,
  pdfSourceFailureCopy,
  pdfPageHeight,
  pdfFitPageScale,
  retryPdfSourceAccess,
} from './pdf-viewer-model'

test('clamps direct and event-driven pages to safe document bounds', () => {
  assert.equal(clampPdfPage(Number.NaN, 12), 1)
  assert.equal(clampPdfPage(-4, 12), 1)
  assert.equal(clampPdfPage(3.9, 12), 3)
  assert.equal(clampPdfPage(99, 12), 12)
})

test('keeps at most five adjacent PDF canvases in the render window', () => {
  const rendered = Array.from({ length: 20 }, (_, index) => index + 1)
    .filter((page) => isPdfPageInRenderWindow(page, 10))
  assert.deepEqual(rendered, [8, 9, 10, 11, 12])
  assert.deepEqual([1, 2, 3].filter((page) => isPdfPageInRenderWindow(page, 1)), [1, 2, 3])
})

test('keeps at most five adjacent thumbnail canvases in the thumbnail strip', () => {
  const rendered = Array.from({ length: 20 }, (_, index) => index + 1)
    .filter((page) => isPdfThumbnailInRenderWindow(page, 10))
  assert.deepEqual(rendered, [8, 9, 10, 11, 12])
  assert.deepEqual([1, 2, 3].filter((page) => isPdfThumbnailInRenderWindow(page, 1)), [1, 2, 3])
  assert.deepEqual(pdfThumbnailPages(10, 20), [8, 9, 10, 11, 12])
  assert.deepEqual(pdfThumbnailPages(1, 20), [1, 2, 3])
  assert.deepEqual(pdfThumbnailPages(20, 20), [18, 19, 20])
})

test('preserves placeholder geometry across fit, zoom and rotation', () => {
  const sourceSize = { width: 600, height: 900 }
  assert.equal(pdfPageHeight({ sourceSize, rotation: 0, fitWidth: true, pageWidth: 300, scale: 1 }), 450)
  assert.equal(pdfPageHeight({ sourceSize, rotation: 90, fitWidth: true, pageWidth: 300, scale: 1 }), 200)
  assert.equal(pdfPageHeight({ sourceSize, rotation: 0, fitWidth: false, scale: 1.5 }), 1350)
})

test('fits each page inside both viewport dimensions after rotation', () => {
  const sourceSize = { width: 600, height: 900 }
  assert.equal(pdfFitPageScale({ sourceSize, rotation: 0, viewportWidth: 300, viewportHeight: 300 }), 1 / 3)
  assert.equal(pdfFitPageScale({ sourceSize, rotation: 90, viewportWidth: 300, viewportHeight: 300 }), 1 / 3)
  assert.equal(pdfFitPageScale({ sourceSize, rotation: 0, viewportWidth: 1200, viewportHeight: 900 }), 1)
})

test('bounds each search pass and reports when coverage is complete', () => {
  assert.deepEqual(nextPdfSearchBatch(0, 60), { start: 1, end: 25, complete: false })
  assert.deepEqual(nextPdfSearchBatch(25, 60), { start: 26, end: 50, complete: false })
  assert.deepEqual(nextPdfSearchBatch(50, 60), { start: 51, end: 60, complete: false })
  assert.deepEqual(nextPdfSearchBatch(60, 60), { start: 61, end: 60, complete: true })
})

test('normalizes bounded queries and safely highlights untrusted PDF text', () => {
  assert.equal(normalizePdfSearchQuery(`  input   tax ${'x'.repeat(120)}`).length, 100)
  assert.equal(
    highlightPdfText('<script>GST & GST</script>', 'GST'),
    '&lt;script&gt;<mark style="background:var(--warning-muted);color:inherit">GST</mark> &amp; <mark style="background:var(--warning-muted);color:inherit">GST</mark>&lt;/script&gt;',
  )
})

test('classifies stable PDF.js failures without exposing private error messages', () => {
  assert.equal(classifyPdfSourceFailure({ name: 'PasswordException', message: 'secret detail' }), 'encrypted')
  assert.equal(classifyPdfSourceFailure({ name: 'InvalidPDFException' }), 'malformed')
  assert.equal(classifyPdfSourceFailure({ name: 'FormatError' }), 'malformed')
  assert.equal(classifyPdfSourceFailure({ name: 'ResponseException', status: 403 }), 'unavailable')
  assert.equal(classifyPdfSourceFailure({ name: 'AbortException' }), null)
  assert.equal(classifyPdfSourceFailure(new TypeError('Failed to fetch a private URL')), 'render_failed')
  assert.equal(classifyPdfSourceFailure(new Error('private detail')), 'render_failed')
  assert.equal(pdfSourceFailureFromAccessCode('source_unavailable'), 'missing')
  assert.equal(pdfSourceFailureFromAccessCode('access_temporary'), 'unavailable')
  assert.equal(pdfSourceFailureFromAccessCode('not_authenticated'), 'unavailable')
  assert.deepEqual(pdfSourceFailureCopy('missing'), {
    title: 'PDF file unavailable',
    detail: 'This stored PDF is not available. Return to the document record or contact an administrator if the source should be restored.',
    retryable: false,
    retryLabel: null,
  })
  assert.deepEqual(pdfSourceFailureCopy('unavailable'), {
    title: 'PDF access needs refreshing',
    detail: 'The secure view link may have expired, or the source could not be retrieved. Refresh access and try again.',
    retryable: true,
    retryLabel: 'Refresh PDF access',
  })
  assert.deepEqual(pdfSourceFailureCopy('render_failed'), {
    title: 'PDF could not be opened',
    detail: 'The viewer could not open this PDF. Try loading it again.',
    retryable: true,
    retryLabel: 'Retry PDF',
  })
})

test('renews caller-owned signed access and keeps route-owned retry behavior distinct', async () => {
  let routeRefreshes = 0
  const refreshed = await retryPdfSourceAccess({
    currentUrl: 'https://storage.test/expired',
    requestFreshUrl: async () => 'https://storage.test/fresh',
    refreshRoute: () => { routeRefreshes += 1 },
  })
  assert.equal(refreshed, 'https://storage.test/fresh')
  assert.equal(routeRefreshes, 0)

  const retained = await retryPdfSourceAccess({
    currentUrl: 'https://storage.test/server-owned',
    refreshRoute: () => { routeRefreshes += 1 },
  })
  assert.equal(retained, 'https://storage.test/server-owned')
  assert.equal(routeRefreshes, 1)

  const failedRenewal = await retryPdfSourceAccess({
    currentUrl: 'https://storage.test/expired',
    requestFreshUrl: async () => null,
    refreshRoute: () => { routeRefreshes += 1 },
  })
  assert.equal(failedRenewal, null)
})
