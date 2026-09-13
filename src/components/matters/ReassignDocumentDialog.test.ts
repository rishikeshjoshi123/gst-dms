import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./ReassignDocumentDialog.tsx', import.meta.url), 'utf8')

test('repair presents authoritative consequences before a reason-required confirmation', () => {
  assert.match(source, /await previewDocumentBoundaryRepair\(documentId, target, mode\)/)
  assert.match(source, /fingerprint: impact.fingerprint, reason, idempotencyKey/)
  assert.match(source, /impact.categories.map/)
  assert.match(source, /impact.blockers.length > 0/)
  assert.match(source, /disabled=\{pending \|\| !reason.trim\(\) \|\| impact.blockers.length > 0\}/)
  assert.match(source, /Create the target Matter separately/)
  assert.match(source, /Original notes, citations, deadlines and tasks remain with the original/)
  assert.match(source, /Human field decisions are preserved with their source provenance/)
  assert.match(source, /setSearch\(event.target.value\); setTarget\(''\)/)
})

test('repair rejects stale UI responses and retains a retry identity for uncertain confirmations', () => {
  assert.match(source, /request !== generation.current/)
  assert.match(source, /const idempotencyKey = confirmationKey.current/)
  assert.match(source, /result.code === 'stale_preview'/)
  assert.match(source, /Retry to check the same change/)
  assert.match(source, /key=\{`\$\{props.documentId\}:\$\{props.currentMatterId\}`\}/)
})

test('repair uses shared controls, one body scroller, anchored actions and labelled focus', () => {
  assert.match(source, /from '@\/components\/ui\/dialog'/)
  assert.match(source, /max-h-\[85dvh\] flex-col overflow-hidden/)
  assert.equal((source.match(/overflow-y-auto/g) ?? []).length, 1)
  assert.match(source, /DialogFooter className="shrink-0"/)
  assert.match(source, /impactHeading.current\?\.focus\(\)/)
  assert.match(source, /aria-describedby="repair-reason-help"/)
  assert.match(source, /role="alert"/)
  assert.doesNotMatch(source, /text-white|shadow-xl|bg-(blue|slate|gray)-|<button/)
})
