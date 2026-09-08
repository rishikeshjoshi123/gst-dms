import assert from 'node:assert/strict'
import test from 'node:test'

import { caseWikiSourceLinkPresentation } from './case-wiki-source-link'

const version = '00000000-0000-4000-8000-000000000007'

test('canonicalizes exact canonical and legacy document locators to immutable Workbench routes', () => {
  assert.deepEqual(
    caseWikiSourceLinkPresentation(`/documents/document-a?version=${version}&page=8`),
    { kind: 'exact', href: `/documents/document-a?version=${version}&page=8` },
  )
  assert.deepEqual(
    caseWikiSourceLinkPresentation(`/matters/legacy-matter/documents/document-a?page=8&version=${version}`),
    { kind: 'exact', href: `/documents/document-a?version=${version}&page=8` },
  )
})

test('adds the supplied matter lineage only for an exact read-only source', () => {
  assert.deepEqual(
    caseWikiSourceLinkPresentation(
      `/matters/stored-matter/documents/document-a?version=${version}&page=8`,
      { matterId: 'authorised-trash-matter', readOnly: true },
    ),
    {
      kind: 'exact',
      href: `/documents/document-a?matterId=authorised-trash-matter&version=${version}&page=8`,
    },
  )
  assert.deepEqual(
    caseWikiSourceLinkPresentation(
      `/documents/document-a?version=${version}&page=8`,
      { matterId: 'active-matter', readOnly: false },
    ),
    { kind: 'exact', href: `/documents/document-a?version=${version}&page=8` },
  )
})

test('fails absent, incomplete, malformed, repeated, and hash-only document locators closed', () => {
  const unverified = [
    '/documents/document-a',
    '/documents/document-a#page=8',
    `/documents/document-a?version=${version}`,
    '/documents/document-a?page=8',
    '/documents/document-a?version=not-a-version&page=8',
    `/documents/document-a?version=${version}&page=0`,
    `/documents/document-a?version=${version}&page=1.5`,
    `/documents/document-a?version=${version}&page=8&page=9`,
    `/documents/document-a?version=${version}&version=${version}&page=8`,
  ]

  for (const href of unverified) {
    assert.deepEqual(caseWikiSourceLinkPresentation(href), { kind: 'unverified', href: null }, href)
  }
})

test('fails document-looking traversal, encoded separator, backslash, and extra-path variants closed', () => {
  const unsafeDocumentSources = [
    `/%64ocuments/document-a?version=${version}&page=8`,
    `/documents/../documents/document-a?version=${version}&page=8`,
    `/documents/document%2Fa?version=${version}&page=8`,
    `/documents/document%252Fa?version=${version}&page=8`,
    `/documents/%252e%252e?version=${version}&page=8`,
    `/documents\\document-a?version=${version}&page=8`,
    `/documents/document-a/extra?version=${version}&page=8`,
  ]

  for (const href of unsafeDocumentSources) {
    assert.deepEqual(caseWikiSourceLinkPresentation(href), { kind: 'unverified', href: null }, href)
  }
})

test('leaves external, protocol-relative, mail, unsafe-scheme, and non-document links to Markdown policy', () => {
  const ordinaryLinks = [
    `https://example.test/documents/document-a?version=${version}&page=8`,
    `//example.test/documents/document-a?version=${version}&page=8`,
    'mailto:reviewer@example.test',
    'javascript:alert(1)',
    'data:text/html,unsafe',
    '/matters/matter-a/notes',
    './supporting-material',
  ]

  for (const href of ordinaryLinks) {
    assert.deepEqual(caseWikiSourceLinkPresentation(href), { kind: 'other', href }, href)
  }
})
