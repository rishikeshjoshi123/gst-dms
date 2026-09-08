import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const activeSectionSource = readFileSync(new URL('./MatterActiveSection.tsx', import.meta.url), 'utf8')
const boundarySource = readFileSync(new URL('./MatterSectionBoundary.tsx', import.meta.url), 'utf8')
const pageSource = readFileSync(new URL('../../app/(app)/matters/[id]/page.tsx', import.meta.url), 'utf8')
const readerSource = readFileSync(new URL('../../lib/matters/workspace-read.ts', import.meta.url), 'utf8')
const timelineSource = readFileSync(new URL('./MatterTimelineTab.tsx', import.meta.url), 'utf8')
const exactResourceSource = readFileSync(new URL('../../lib/trash/exact-resource.ts', import.meta.url), 'utf8')

test('the route fetches the exact shell first and keeps section work under Suspense and a local boundary', () => {
  assert.match(pageSource, /await getExactMatter\(params\.id\)/)
  assert.match(pageSource, /<MatterWorkspaceShell[\s\S]*<MatterSectionBoundary[\s\S]*<Suspense[\s\S]*<MatterActiveSection/)
  assert.match(boundarySource, /Retry \{label\}/)
  assert.match(boundarySource, /unstable_catchError/)
  assert.match(boundarySource, /unstable_retry\(\)/)
  assert.doesNotMatch(boundarySource, /router\.refresh\(\)/)
})

test('active unavailable sections do not import or call canonical domain readers', () => {
  assert.doesNotMatch(activeSectionSource, /getDeadlineAttention|activity_logs|financial[_A-Za-z]*\(/)
  assert.match(activeSectionSource, /Deadlines are not available in this release/)
  assert.match(activeSectionSource, /Financials are not available in this release/)
  assert.match(activeSectionSource, /Activity is not available in this release/)
})

test('inspector metadata is read only after exact section membership acceptance', () => {
  for (const sectionFunction of ['TimelineSection', 'FilesSection']) {
    const start = activeSectionSource.indexOf(`function ${sectionFunction}`)
    const next = activeSectionSource.indexOf('\nasync function ', start + 1)
    const body = activeSectionSource.slice(start, next === -1 ? undefined : next)
    assert.ok(body.indexOf('acceptedSectionSelection') < body.indexOf('getDocumentInspectorMetadata([accepted.id])'))
    assert.match(body, /selectionUnavailable = route\.selectionRequested && !accepted/)
  }
})

test('Timeline selected-document notes use the narrow reader without the Notes member directory', () => {
  const start = activeSectionSource.indexOf('function TimelineSection')
  const end = activeSectionSource.indexOf('async function FilesSection', start)
  const timelineBody = activeSectionSource.slice(start, end)
  assert.match(timelineBody, /readSelectedDocumentNotes\(matterId, accepted\.id\)/)
  assert.doesNotMatch(timelineBody, /getNotes\(/)
  assert.doesNotMatch(readerSource, /getSafeMemberDirectory|getOperationalMemberOptions/)
  assert.match(readerSource, /\.eq\('matter_id', matterId\)[\s\S]*\.eq\('document_id', documentId\)/)
})

test('URL inspector state is consumed and active mutation UI is capability and closed-state gated', () => {
  assert.match(activeSectionSource, /inspector=\{route\.inspector\}/)
  assert.match(timelineSource, /activeTab=\{inspector\}/)
  assert.match(timelineSource, /buildMatterInspectorHref/)
  assert.match(activeSectionSource, /record\.status === 'closed' \|\| !canContribute/)
  assert.match(readerSource, /capabilities\.includes\('document\.intake\.create'\)/)
})

test('temporary active Matter lookup failures do not fall through to a false not-found result', () => {
  const start = exactResourceSource.indexOf('export async function getExactMatter')
  const body = exactResourceSource.slice(start, exactResourceSource.indexOf('/**', start))
  assert.match(body, /const \{ data, error \}/)
  assert.ok(body.indexOf("if (error) throw new Error") < body.indexOf("getTrashProjection<TrashMatterRecord>"))
})

test('Trash sections use exact snapshots and never active readers', () => {
  assert.match(activeSectionSource, /isTrash\s*\? exactMatter\.data\.documents/)
  assert.match(activeSectionSource, /isTrash\s*\? exactMatter\.data\.links/)
  assert.match(activeSectionSource, /isTrash \? exactMatter\.data\.wikiSections : await getWikiSections/)
  assert.match(activeSectionSource, /initialNotes=\{exactMatter\.data\.notes\}/)
  assert.match(pageSource, /<TrashReadOnlyStrip context=\{exactMatter\.context\}/)
})

test('narrow readers exclude supporting documents from Timeline and never follow cross-matter links', () => {
  assert.match(readerSource, /readActiveProceedings[\s\S]*'proceeding'/)
  assert.match(readerSource, /document_class\.eq\.proceeding,document_class\.is\.null/)
  assert.match(readerSource, /readActiveSupportingFiles[\s\S]*'supporting'/)
  assert.doesNotMatch(readerSource, /crossMatter|linkedDocIds/)
  assert.match(readerSource, /allowedIds\.has\(link\.from_doc_id\)[\s\S]*allowedIds\.has\(link\.to_doc_id\)/)
})
