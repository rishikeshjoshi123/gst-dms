import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { documentHubPath } from './document-hub-route'

test('builds the canonical Document Hub route from allowlisted state only', () => {
  assert.equal(documentHubPath(), '/documents')
  assert.equal(documentHubPath({ matterId: 'matter one' }), '/documents?matterId=matter+one')
  assert.equal(documentHubPath({ intakeId: 'intake/one' }), '/documents?intakeId=intake%2Fone')
  assert.equal(
    documentHubPath({ matterId: 'matter', intakeId: 'intake' }),
    '/documents?matterId=matter&intakeId=intake',
  )
  assert.equal(documentHubPath({ matterId: ['matter-a', 'matter-b'], intakeId: '' }), '/documents')
})

test('makes documents the queue owner and inbox a redirect-only compatibility route', () => {
  const documentsPage = readFileSync(new URL('../app/(app)/documents/page.tsx', import.meta.url), 'utf8')
  const inboxPage = readFileSync(new URL('../app/(app)/inbox/page.tsx', import.meta.url), 'utf8')

  assert.match(documentsPage, /getStagedDocuments\(\)/)
  assert.match(documentsPage, /<InboxClientView/)
  assert.match(inboxPage, /permanentRedirect\(documentHubPath\(await searchParams\)\)/)
  assert.doesNotMatch(inboxPage, /getStagedDocuments|InboxClientView/)
})

test('keeps production navigation and mutation refreshes on the canonical route', () => {
  const sources = [
    '../components/nav/SidebarNav.tsx',
    '../components/nav/BreadcrumbNav.tsx',
    '../components/matters/MatterDetailsTab.tsx',
    '../app/(app)/inbox/InboxClientView.tsx',
    './actions/document.ts',
    './actions/inbox.ts',
  ].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))

  for (const source of sources) {
    assert.doesNotMatch(source, /['"`]\/inbox(?:\?|['"`])/)
  }

  assert.match(sources[0], /href: '\/documents'/)
  assert.match(sources[2], /href=\{`\/documents\?matterId=\$\{matter\.id\}`\}/)
  assert.match(sources[3], /\/documents\?intakeId=/)
  assert.match(sources[4], /revalidatePath\('\/documents'\)/)
  assert.match(sources[5], /revalidatePath\('\/documents'\)/)
})
