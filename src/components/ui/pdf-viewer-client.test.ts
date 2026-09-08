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

test('in-document search is cancellable, batched, truthful, and navigates matching pages', async () => {
  const source = await readFile(new URL('./pdf-viewer-client.tsx', import.meta.url), 'utf8')

  assert.match(source, /nextPdfSearchBatch\(searchedPages, numPages\)/)
  assert.match(source, /searchGenerationRef\.current !== generation/)
  assert.match(source, /pdfDocumentRef\.current !== document/)
  assert.match(source, /Searched \{searchedPages\} of \{numPages \?\? 0\} pages/)
  assert.match(source, /requestPage\(mergedResults\[0\]\)/)
  assert.match(source, /customTextRenderer=\{searchResults\.includes\(page\)/)
  assert.match(source, /Cancel search/)
})

test('the responsive thumbnail strip is bounded and synchronized to the current page', async () => {
  const source = await readFile(new URL('./pdf-viewer-client.tsx', import.meta.url), 'utf8')

  assert.match(source, /Show thumbnails/)
  assert.match(source, /aria-label="PDF page thumbnails"/)
  assert.match(source, /pdfThumbnailPages\(pageNumber, numPages\)/)
  assert.match(source, /aria-current=\{selected \? 'page' : undefined\}/)
  assert.match(source, /thumbnailStripRef/)
  assert.match(source, /container\.scrollTo\(\{/)
  assert.match(source, /overflow-x-auto overscroll-x-contain/)
  assert.match(source, /Earlier pages/)
  assert.match(source, /Later pages/)
})
