import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
test('legacy matter document route redirects with only its known exact matter lineage', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')

  assert.match(source, /permanentRedirect\(canonicalDocumentPath\(docId, \{ matterId: id \}\)\)/)
  assert.doesNotMatch(source, /searchParams|return|redirect_uri|callback/)
})
