import assert from 'node:assert/strict'
import test from 'node:test'
import { readFileSync } from 'node:fs'

const source = readFileSync(new URL('./TeamWorkspace.tsx', import.meta.url), 'utf8')

test('Team workspace has an accessible list/detail selection and ownership contract', () => {
  assert.match(source, /Back to members/)
  assert.match(source, /Close details/)
  assert.match(source, /OwnerBadge/)
  assert.match(source, /lg:flex-row/)
  assert.match(source, /next\.delete\('member'\)/)
  assert.match(source, /data-member-id/)
  assert.match(source, /h-12 max-w-full/)
  assert.match(source, /requestAnimationFrame/)
  assert.doesNotMatch(source, /setTimeout\(\(\) => document\.querySelector/)
  assert.match(source, /capabilityLabel/)
  assert.match(source, /sm:grid-cols-\[minmax\(0,1fr\)_minmax\(0,10rem\)_minmax\(0,10rem\)\]/)
  assert.match(source, /w-full min-w-0/)
  assert.match(source, /onClick=\{\(\) => select\(member\)\}/)
  assert.match(source, /Person<\/TableHead><TableHead>Role<\/TableHead><TableHead>Status<\/TableHead><TableHead>Joined/)
  assert.doesNotMatch(source, /Invite member/)
})
