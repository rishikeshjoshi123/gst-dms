import assert from 'node:assert/strict'
import test from 'node:test'

import {
  clampPdfPage,
  highlightPdfText,
  isPdfPageInRenderWindow,
  isPdfThumbnailInRenderWindow,
  nextPdfSearchBatch,
  normalizePdfSearchQuery,
  pdfThumbnailPages,
  pdfPageHeight,
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
