import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const source = readFileSync(new URL('./MatterTimelineChronology.tsx', import.meta.url), 'utf8')
const active = readFileSync(new URL('./MatterActiveSection.tsx', import.meta.url), 'utf8')
const filters = readFileSync(new URL('./MatterTimelineFilters.tsx', import.meta.url), 'utf8')
const focus = readFileSync(new URL('./MatterTimelineFocusBridge.tsx', import.meta.url), 'utf8')
const loading = readFileSync(new URL('./MatterSectionLoading.tsx', import.meta.url), 'utf8')
const page = readFileSync(new URL('../../app/(app)/matters/[id]/page.tsx', import.meta.url), 'utf8')
test('live Timeline is bounded chronology, not the legacy graph or links', () => {
  assert.match(active, /readMatterTimelineChronology/)
  assert.doesNotMatch(active, /readActiveProceedings|readTransitionalTimelineLinks|MatterTimelineTab/)
  assert.match(source, /\['Date', 'Document', 'Direction', 'Procedural effect', 'Key fact', 'Attention'\]/)
  assert.match(source, /canonicalDocumentPath\(item\.id, \{ matterId, returnTo \}\)/)
  assert.match(source, /buildMatterReturnPath/)
  assert.match(source, /lg:flex/)
  assert.doesNotMatch(source, /fixed inset-y-0/)
  assert.match(source, /Effective relationships/)
  assert.match(source, /No active Timeline relationships involve this proceeding/)
  assert.match(source, /Timeline progression/)
  assert.match(source, /describeMatterTimelineRelationship/)
  assert.doesNotMatch(source, /Legacy document links/)
  assert.match(source, /MatterTimelineFilters/)
})

test('filters, inspector subviews, and filtered empty copy are explicit', () => {
  assert.match(active, /filters=\{route\.timelinePage\.filters\}/)
  assert.match(source, /No proceedings match these filters/)
  assert.match(source, /inspector === 'overview'/)
  assert.match(source, /inspector === 'relationships'/)
  assert.match(source, /inspector === 'notes'/)
  assert.match(source, /aria-current=\{inspector === view \? 'page'/)
  assert.match(filters, /maxLength=\{78\}/)
  assert.match(filters, /maxLength=\{75\}/)
  assert.match(filters, /router\.push\([\s\S]*\{ scroll: false \}/)
  assert.match(filters, /From on or before To/)
  assert.match(filters, /key=\{props\.filters\.join/)
  assert.match(filters, /if \(nextOpen\) resetDraft\(filters\)/)
  assert.match(filters, /const trimmedQuery = query\.trim\(\)/)
  assert.match(filters, /const trimmedDocumentType = documentType\.trim\(\)/)
})

test('selection-only navigation retains a persistent, streamed focus bridge', () => {
  assert.match(page, /<MatterTimelineFocusProvider>[\s\S]*<Suspense/)
  assert.match(source, /MatterTimelineRowLink/)
  assert.match(source, /MatterTimelineCloseLink/)
  assert.match(focus, /onNavigate=\{\(\) => bridge\.remember\(documentId\)\}/)
  assert.match(focus, /matter-timeline-row-\$\{documentId\}/)
  assert.match(focus, /focus\(\{ preventScroll: true \}\)/)
  assert.match(focus, /requestAnimationFrame/)
})

test('rows expose typed terminal states and compact mobile interpretation without graph reads', () => {
  for (const copy of ['PDF not attached', 'Source unreadable', 'Processing failed', 'Needs review', 'Processing', 'Effect:', 'Key fact:']) assert.match(source, new RegExp(copy))
  assert.match(source, /data-content-state=\{item\.contentAvailability \?\? 'unavailable'\}/)
  assert.match(source, /data-attention-state=\{item\.attentionState\}/)
  assert.match(source, /content\(item\.contentAvailability\)[\s\S]*attention\(item\.attentionState\)/)
  assert.match(source, /canonicalDocumentPath\(item\.id/)
  assert.doesNotMatch(source, /document_links|raw_metadata/)
})

test('Timeline loading mirrors the chronology workbar and responsive row geometry', () => {
  assert.match(loading, /section === 'timeline'/)
  assert.match(loading, /min-w-\[900px\]/)
  assert.match(loading, /grid-cols-\[10rem_minmax\(16rem,1fr\)_9rem_11rem_11rem_10rem\]/)
  assert.match(loading, /overflow-y-auto/)
})
