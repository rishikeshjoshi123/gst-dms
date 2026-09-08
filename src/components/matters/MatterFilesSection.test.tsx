import assert from 'node:assert/strict'
import test from 'node:test'
import { renderToStaticMarkup } from 'react-dom/server'

import type { MatterSupportingFileSummary, MatterSupportingFilesPage } from '@/lib/matters/workspace-read'
import { MatterFilesSection } from './MatterFilesSection'

const selectedId = '00000000-0000-4000-8000-000000000099'

function file(id: string): MatterSupportingFileSummary {
  return {
    id,
    matter_id: 'matter-a',
    document_class: 'supporting',
    display_title: `File ${id}`,
    effective_filename: `${id}.pdf`,
    document_category: 'evidence',
    reference_number: null,
    content_availability: 'source_attached',
    created_at: '2026-09-08T00:00:00Z',
    effective_size_bytes: 1024,
    revision: 7,
  }
}

function page(overrides: Partial<MatterSupportingFilesPage> = {}): MatterSupportingFilesPage {
  return {
    items: [file('file-1')],
    total: 1,
    offset: 0,
    limit: 50,
    fetchedAt: '2026-09-08T00:00:00Z',
    sourceRevision: null,
    ...overrides,
  }
}

function render(options: {
  page?: MatterSupportingFilesPage
  selectedDocument?: MatterSupportingFileSummary | null
  selectedDocumentId?: string | null
  selectionUnavailable?: boolean
} = {}) {
  return renderToStaticMarkup(
    <MatterFilesSection
      matterId="matter-a"
      page={options.page ?? page()}
      selectedDocument={options.selectedDocument ?? null}
      selectedDocumentId={options.selectedDocumentId ?? null}
      selectionUnavailable={options.selectionUnavailable ?? false}
      inspector="overview"
      queryEntries={[
        ['section', 'files'],
        ['filter', 'evidence'],
        ['filter', 'correspondence'],
        ['document', selectedId],
        ['inspector', 'overview'],
      ]}
    />,
  )
}

test('renders truthful empty and one-file range states with disabled page controls', () => {
  const empty = render({ page: page({ items: [], total: 0 }) })
  assert.match(empty, />0 files</)
  assert.match(empty, />No supporting files</)

  const one = render()
  assert.match(one, />Showing 1–1 of 1 file</)
  assert.equal((one.match(/aria-disabled="true"/g) ?? []).length, 2)
  assert.match(one, />Previous</)
  assert.match(one, />Next</)
})

test('renders previous and next links with exact range and preserved deep-link query state', () => {
  const items = Array.from({ length: 50 }, (_, index) => file(`file-${index + 51}`))
  const html = render({ page: page({ items, total: 250, offset: 50, limit: 50 }) })

  assert.match(html, />Showing 51–100 of 250 files</)
  assert.match(html, /href="\/matters\/matter-a\?section=files&amp;filter=evidence&amp;filter=correspondence&amp;document=00000000-0000-4000-8000-000000000099&amp;inspector=overview"/)
  assert.match(html, /href="\/matters\/matter-a\?section=files&amp;filter=evidence&amp;filter=correspondence&amp;document=00000000-0000-4000-8000-000000000099&amp;inspector=overview&amp;filesOffset=100"/)
  assert.match(html, /min-h-11/)
})

test('keeps a valid off-page selection inspectable without expanding the current page', () => {
  const selected = file(selectedId)
  const html = render({
    page: page({ items: [file('file-on-page')], total: 100, offset: 50 }),
    selectedDocument: selected,
    selectedDocumentId: selectedId,
  })

  assert.match(html, />Selected supporting file</)
  assert.match(html, new RegExp(`>File ${selectedId}<`))
  assert.doesNotMatch(html, /id="file-on-page"/)
  assert.match(html, new RegExp(`href="/documents/${selectedId}\\?matterId=matter-a&amp;returnTo=`))
  assert.match(html, /returnTo=%2Fmatters%2Fmatter-a%3Fsection%3Dfiles/)
})

test('renders one non-disclosing unavailable state for an inaccessible selection', () => {
  const html = render({ selectedDocumentId: null, selectionUnavailable: true })
  assert.match(html, /The selected document is unavailable\. Choose a file from this matter\./)
  assert.doesNotMatch(html, />Selected supporting file</)
})
