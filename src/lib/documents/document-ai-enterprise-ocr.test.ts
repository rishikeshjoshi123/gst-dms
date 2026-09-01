import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import {
  DOCUMENT_AI_REQUIRED_LOCATION,
  resolveDocumentAiOcrConfiguration,
} from './document-ai-enterprise-ocr'

const credentials = JSON.stringify({ project_id: 'casechain-test' })

test('Document AI fails closed unless an explicit Mumbai Enterprise OCR configuration is complete', () => {
  assert.equal(resolveDocumentAiOcrConfiguration({
    GOOGLE_APPLICATION_CREDENTIALS_JSON: credentials,
    GOOGLE_CLOUD_PROJECT: 'casechain-test',
    DOCUMENT_AI_LOCATION: 'us-central1',
    DOCUMENT_AI_OCR_PROCESSOR_ID: '123456',
  }), null)
  assert.equal(resolveDocumentAiOcrConfiguration({
    GOOGLE_APPLICATION_CREDENTIALS_JSON: credentials,
    GOOGLE_CLOUD_PROJECT: 'casechain-test',
    DOCUMENT_AI_LOCATION: DOCUMENT_AI_REQUIRED_LOCATION,
  }), null)
  assert.deepEqual(resolveDocumentAiOcrConfiguration({
    GOOGLE_APPLICATION_CREDENTIALS_JSON: credentials,
    GOOGLE_CLOUD_PROJECT: 'casechain-test',
    DOCUMENT_AI_LOCATION: DOCUMENT_AI_REQUIRED_LOCATION,
    DOCUMENT_AI_OCR_PROCESSOR_ID: '123456',
    DOCUMENT_AI_OCR_PROCESSOR_VERSION: 'pretrained-ocr-v2.1',
  }), {
    project: 'casechain-test',
    location: 'asia-south1',
    processorId: '123456',
    processorVersion: 'pretrained-ocr-v2.1',
    credentials: { project_id: 'casechain-test' },
  })
})

test('Document AI adapter sends only selected source pages and disables native parsing for OCR fallback', () => {
  const source = readFileSync(new URL('./document-ai-enterprise-ocr.ts', import.meta.url), 'utf8')

  assert.match(source, /for \(const pageNumber of pageNumbers\)/)
  assert.match(source, /selectedPdf\(pdfBytes, pageNumber\)/)
  assert.match(source, /enableNativePdfParsing: false/)
  assert.match(source, /https:\/\/\$\{configuration\.location\}-documentai\.googleapis\.com/)
  assert.doesNotMatch(source, /us-central1|locations\/global/)
})
