import assert from 'node:assert/strict'
import test from 'node:test'
import { renderToStaticMarkup } from 'react-dom/server'

import { CaseWikiMarkdown } from './CaseWikiMarkdown'

const version = '00000000-0000-4000-8000-000000000007'

function render(markdown: string, readOnly = false) {
  return renderToStaticMarkup(
    <CaseWikiMarkdown matterId="matter-a" readOnly={readOnly}>{markdown}</CaseWikiMarkdown>,
  )
}

test('renders an exact source as a labelled, focus-visible, effective-touch-target link', () => {
  const html = render(`[Author label](/documents/document-a?version=${version}&page=8)`, true)

  assert.match(html, new RegExp(`href="/documents/document-a\\?matterId=matter-a&amp;version=${version}&amp;page=8"`))
  assert.match(html, />Author label</)
  assert.match(html, />Open exact source</)
  assert.match(html, /min-h-11/)
  assert.match(html, /focus-visible:ring-2/)
})

test('preserves an ambiguous source label as a visible non-link status', () => {
  const html = render('[Preserved author label](/documents/document-a#page=8)')

  assert.doesNotMatch(html, /<a/)
  assert.match(html, />Preserved author label</)
  assert.match(html, />Source location unverified</)
  assert.match(html, /role="note"/)
})

test('preserves normal Markdown links and its default unsafe URL blocking', () => {
  const html = render([
    '[External](https://example.test/reference)',
    '[Email](mailto:reviewer@example.test)',
    '[Matter notes](/matters/matter-a/notes)',
    '[Script](javascript:alert(1))',
    '[Data](data:text/html,unsafe)',
  ].join('\n\n'))

  assert.match(html, /href="https:\/\/example.test\/reference"/)
  assert.match(html, /href="mailto:reviewer@example.test"/)
  assert.match(html, /href="\/matters\/matter-a\/notes"/)
  assert.doesNotMatch(html, /href="javascript:/)
  assert.doesNotMatch(html, /href="data:/)
  assert.doesNotMatch(html, /Open exact source|Source location unverified/)
})
