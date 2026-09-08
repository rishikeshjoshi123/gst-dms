import assert from 'node:assert/strict'
import test from 'node:test'

import {
  clampPdfPage,
  isPdfPageInRenderWindow,
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

test('preserves placeholder geometry across fit, zoom and rotation', () => {
  const sourceSize = { width: 600, height: 900 }
  assert.equal(pdfPageHeight({ sourceSize, rotation: 0, fitWidth: true, pageWidth: 300, scale: 1 }), 450)
  assert.equal(pdfPageHeight({ sourceSize, rotation: 90, fitWidth: true, pageWidth: 300, scale: 1 }), 200)
  assert.equal(pdfPageHeight({ sourceSize, rotation: 0, fitWidth: false, scale: 1.5 }), 1350)
})
