import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./ReassignDocumentDialog.tsx', import.meta.url), 'utf8')

test('controlled unmount restores explicit launcher focus through Radix for Escape, Cancel and Copy success', () => {
  const caller = readFileSync(new URL('./TimelineDocumentDetail.tsx', import.meta.url), 'utf8')
  assert.match(caller, /<Button ref=\{repairLauncher\}/)
  assert.match(caller, /returnFocusRef=\{repairLauncher\}/)
  assert.match(caller, /const closeRepairDialog = \(\) => \{[^]*?setIsReassignOpen\(false\)[^]*?requestAnimationFrame\(\(\) => repairLauncher.current\?\.focus\(\{ preventScroll: true \}\)\)/)
  assert.match(caller, /onClose=\{closeRepairDialog\}/)
  assert.match(source, /onCloseAutoFocus=\{\(event\) => \{[^]*?event.preventDefault\(\)[^]*?returnFocusRef.current\?\.focus\(\{ preventScroll: true \}\)/)
  assert.match(source, /if \(!open && !pending\) onClose\(\)/)
  assert.match(source, /onEscapeKeyDown=\{\(event\) => \{ if \(pending\) event.preventDefault\(\)/)
  assert.match(source, /toast.success\([^]*?onClose\(\)/)
  assert.match(source, /else onClose\(\)/)
  assert.match(source, /return props.isOpen \? <BoundaryRepairDialog/)
})

test('Move preserves its source locator and framework navigation instead of closing the obsolete source dialog', () => {
  assert.match(source, /sourceVersionId: impact.versionId, sourcePage/)
  assert.match(source, /catch \(error\) \{\s*unstable_rethrow\(error\)/)
  assert.match(source, /toast.success\('Document copied'\)\s*onClose\(\)/)
  assert.doesNotMatch(source, /toast.success\(mode === 'move'/)
  const workbench = readFileSync(new URL('../documents/CanonicalDocumentWorkbench.tsx', import.meta.url), 'utf8')
  assert.match(workbench, /id="document-workbench" role="region" aria-label="Document workbench" tabIndex=\{-1\}/)
  assert.match(workbench, /window.location.hash !== '#document-workbench'/)
  assert.match(workbench, /requestAnimationFrame\(\(\) => workbench.current\?\.focus/)
  assert.match(workbench, /\[doc.id, doc.matter_id\]/)
  assert.match(workbench, /<TimelineDocumentDetail\s+key=\{`\$\{doc.id\}:\$\{doc.matter_id\}`\}/)
})

test('caller-owned close restores focus after the dialog subtree is removed', () => {
  const caller = readFileSync(new URL('./TimelineDocumentDetail.tsx', import.meta.url), 'utf8')
  const closeBody = caller.match(/const closeRepairDialog = \(\) => \{([^]*?)\n  \}/)?.[1]
  assert.ok(closeBody)
  const events: string[] = []
  const frames: Array<() => void> = []
  const close = new Function('setIsReassignOpen', 'requestAnimationFrame', 'repairLauncher', closeBody)
  close((open: boolean) => { assert.equal(open, false); events.push('dialog removed') },
    (frame: () => void) => frames.push(frame),
    { current: { focus: (options: { preventScroll: boolean }) => { assert.equal(options.preventScroll, true); events.push('launcher focused') } } })
  assert.deepEqual(events, ['dialog removed'])
  assert.equal(frames.length, 1)
  frames[0]()
  assert.deepEqual(events, ['dialog removed', 'launcher focused'])
})

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
