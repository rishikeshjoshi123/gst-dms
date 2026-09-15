import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import { documentHubPath } from './document-hub-route'

test('builds the canonical Document Inbox route from allowlisted state only', () => {
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

  assert.match(documentsPage, /getStagedDocuments\(\{ includeId: intakeId, ownershipScope: 'mine' \}\)/)
  assert.match(documentsPage, /capabilities\.includes\('document\.intake\.assign'\)/)
  assert.match(documentsPage, /canManageIntake=\{canManageIntake\}/)
  assert.match(documentsPage, /<DocumentHubClientView/)
  assert.doesNotMatch(documentsPage, /InboxClientView/)
  assert.match(inboxPage, /permanentRedirect\(documentHubPath\(await searchParams\)\)/)
  assert.doesNotMatch(inboxPage, /getStagedDocuments|InboxClientView/)
})

test('mounts the Upload Queue, details, and source closure without changing the legacy inbox client', () => {
  const documentHub = readFileSync(new URL('../app/(app)/documents/DocumentHubClientView.tsx', import.meta.url), 'utf8')

  assert.match(documentHub, /canonicalIntakeActions/)
  assert.match(documentHub, /getIntakeItemSignedUrl/)
  assert.match(documentHub, /getCanonicalDuplicateResolution/)
  assert.match(documentHub, /canonicalDocumentPath/)
  assert.match(documentHub, /lg:w-3\/5 lg:flex-none/)
  assert.match(documentHub, /lg:w-2\/5 lg:flex-none/)
  assert.match(documentHub, /Back to Upload Queue/)
  assert.match(documentHub, /Back to details/)
})

test('uses Document Inbox for the workspace and Upload Queue for processing without conflating Review', () => {
  const [documentsPage, documentHub, sidebar, breadcrumbs] = [
    '../app/(app)/documents/page.tsx',
    '../app/(app)/documents/DocumentHubClientView.tsx',
    '../components/nav/SidebarNav.tsx',
    '../components/nav/BreadcrumbNav.tsx',
  ].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))

  assert.match(documentsPage, /title: 'Document Inbox — GST Litigation DMS'/)
  assert.match(sidebar, /href: '\/documents',[\s\S]*label: 'Document Inbox'/)
  assert.match(breadcrumbs, /'\/documents': 'Document Inbox'/)
  assert.match(breadcrumbs, /'\/review': 'Pending Review'/)
  assert.match(documentHub, /id="upload-queue-heading"[\s\S]*>Upload Queue</)
  assert.match(documentHub, /aria-label=.*Upload Queue/)
  assert.match(documentHub, /Search Upload Queue/)
  assert.match(documentHub, /Upload PDFs/)
  assert.match(documentHub, /From Matter/)
  assert.match(documentHub, /Return to Matter/)
  assert.doesNotMatch(documentHub, /Review queue/)
})

test('hands committed placement to the server-returned exact Workbench version', () => {
  const [documentHub, inboxAction] = [
    '../app/(app)/documents/DocumentHubClientView.tsx',
    './actions/inbox.ts',
  ].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))

  assert.match(inboxAction, /documentVersionId: result\.document_version_id/)
  assert.match(documentHub, /canonicalDocumentPath\(result\.documentId, \{[\s\S]*?matterId: selectedMatterId,[\s\S]*?version: result\.documentVersionId,[\s\S]*?page: '1'/)
  assert.doesNotMatch(documentHub, /Assignment completed\. The remaining queue could not be refreshed/)
})

test('keeps production navigation and mutation refreshes on the canonical route', () => {
  const sources = [
    '../components/nav/SidebarNav.tsx',
    '../components/nav/BreadcrumbNav.tsx',
    '../components/matters/MatterDetailsTab.tsx',
    '../app/(app)/documents/DocumentHubClientView.tsx',
    './actions/document.ts',
    './actions/inbox.ts',
  ].map(path => readFileSync(new URL(path, import.meta.url), 'utf8'))

  for (const source of sources) {
    assert.doesNotMatch(source, /['"`]\/inbox(?:\?|['"`])/)
  }

  assert.match(sources[0], /href: '\/documents'/)
  assert.match(sources[2], /href=\{`\/documents\?matterId=\$\{matter\.id\}`\}/)
  assert.match(sources[3], /documentHubPath\(\{ matterId: preselectedMatterId, intakeId \}\)/)
  assert.match(sources[4], /revalidatePath\('\/documents'\)/)
  assert.match(sources[5], /revalidatePath\('\/documents'\)/)
})
