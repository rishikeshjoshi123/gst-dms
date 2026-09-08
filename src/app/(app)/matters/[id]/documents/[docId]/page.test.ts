import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
test('legacy matter document route preserves source query state for canonical validation', () => {
  const source = readFileSync(new URL('./page.tsx', import.meta.url), 'utf8')

  assert.match(source, /Promise\.all\(\[props\.params, props\.searchParams\]\)/)
  assert.match(source, /permanentRedirect\(legacyCanonicalDocumentRedirectPath\(docId, id, query\)\)/)
  assert.doesNotMatch(source, /redirect_uri|callback/)
})
