import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('the shared PDF viewer owns one responsive scroller and fit-width toolbar', async () => {
  const source = await readFile(new URL('./pdf-viewer-client.tsx', import.meta.url), 'utf8')

  assert.match(source, /new ResizeObserver\(updateWidth\)/)
  assert.match(source, /Fit width/)
  assert.match(source, /flex-wrap/)
  assert.match(source, /min-h-0 w-full flex-1 justify-center overflow-auto/)
  assert.match(source, /min-h-11 min-w-11/)
  assert.doesNotMatch(source, /min-h-\[600px\]|bg-white/)
})

test('the shared viewer rotates and scopes keyboard page navigation to its focusable region', async () => {
  const source = await readFile(new URL('./pdf-viewer-client.tsx', import.meta.url), 'utf8')

  assert.match(source, /function rotateClockwise\(\)/)
  assert.match(source, /setRotation\(current => \(current \+ 90\) % 360\)/)
  assert.match(source, /rotate=\{rotation\}/)
  assert.match(source, /aria-keyshortcuts="ArrowLeft ArrowRight PageUp PageDown Home End"/)
  assert.match(source, /target\.closest\('button, input, select, textarea, a, \[contenteditable="true"\]'\)/)
  assert.match(source, /setRotation\(0\)/)
  assert.match(source, /const nextPage = clampPdfPage\(e\.detail\.pageNumber, numPages\)/)
})

test('continuous scrolling renders a bounded page window and synchronizes the dominant page', async () => {
  const source = await readFile(new URL('./pdf-viewer-client.tsx', import.meta.url), 'utf8')

  assert.match(source, /isPdfPageInRenderWindow\(page, pageNumber\)/)
  assert.match(source, /new IntersectionObserver/)
  assert.match(source, /data-pdf-page=\{page\}/)
  assert.match(source, /container\.scrollTo\(\{ top:/)
  assert.doesNotMatch(source, /scrollIntoView/)
  assert.match(source, /pageNumber: selection\.pageNumber/)
})
