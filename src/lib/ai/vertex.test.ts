import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('Vertex structured-output boundary strictly parses complete JSON and logs only fixed diagnostics', () => {
  const source = readFileSync(new URL('./vertex.ts', import.meta.url), 'utf8')

  assert.match(source, /return JSON\.parse\(rawText\)/)
  assert.doesNotMatch(source, /indexOf\('\{'\)|lastIndexOf\('\}'\)|\.slice\(firstBrace/)
  assert.doesNotMatch(source, /console\.(?:error|warn)\([^\n]*,\s*(?:err|error|e|validation)/)
  assert.match(source, /logVertexDiagnostic\('document_response_unreadable'\)/)
  assert.match(source, /logVertexDiagnostic\('wiki_response_invalid'\)/)
})
