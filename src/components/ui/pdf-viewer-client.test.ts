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
