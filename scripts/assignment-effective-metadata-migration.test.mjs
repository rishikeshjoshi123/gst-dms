import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const migration = new URL('../supabase/migrations/00074_current_document_assignment_projection.sql', import.meta.url)

async function sql() {
  return readFile(migration, 'utf8')
}

test('assignment projection is service-only, tenant-scoped, and current-valid-version fenced', async () => {
  const source = await sql()
  assert.match(source, /CREATE FUNCTION public\.read_current_document_assignment_projection/)
  assert.match(source, /document\.org_id = p_org_id/)
  assert.match(source, /version\.state = 'current'/)
  assert.match(source, /version\.validation_state = 'valid'/)
  assert.match(source, /GRANT EXECUTE ON FUNCTION public\.read_current_document_assignment_projection[\s\S]*TO service_role/)
  assert.doesNotMatch(source, /raw_metadata\s*->/)
})

test('assignment projection preserves corrected values and suppresses cleared or rejected values without fallback', async () => {
  const source = await sql()
  assert.match(source, /read_current_document_effective_metadata/)
  assert.match(source, /metadata\.normalized_value IS NOT NULL/)
  assert.match(source, /metadata\.field_path = 'document\.financial_year'/)
  assert.match(source, /metadata\.field_path = 'document\.referenced_document_number'/)
})
