import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

test('signed PDF source failures keep provider detail server-side', async () => {
  const source = await readFile(new URL('./document.ts', import.meta.url), 'utf8')

  assert.match(source, /PDF source access is temporarily unavailable\./)
  assert.equal(source.match(/pdfSourceLookupFailureCode\(\{/g)?.length, 4)
  assert.equal(source.match(/if \(grantError\) console\.error/g)?.length, 3)
  assert.match(source, /if \(error\) console\.error\('Failed to resolve canonical document version:', error\)/)
  assert.match(source, /This document version is not available\.', code: 'source_unavailable' as const/)
  assert.match(source, /This intake PDF is not available for preview\.', code: 'source_unavailable' as const/)
  assert.doesNotMatch(source, /return \{ error: error\?\.message \?\? 'Failed to generate view link\.' \}/)
  assert.match(source, /console\.error\('Failed to create versioned document URL:', error\)/)
  assert.match(source, /console\.error\('Failed to create trashed document URL:', error\)/)
  assert.match(source, /console\.error\('Failed to create intake document URL:', error\)/)
})
