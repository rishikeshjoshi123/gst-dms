import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { GoogleAuth } from 'google-auth-library'
import { PDFDocument } from 'pdf-lib'

import {
  DOCUMENT_AI_REQUIRED_LOCATION,
  ocrDocumentAiEnterprisePages,
  resolveDocumentAiOcrConfiguration,
  tableCellsFromResponse,
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

test('Document AI OCR fallback omits rejected image-quality scoring from its actual provider request', async (t) => {
  const pdf = await PDFDocument.create()
  pdf.addPage([72, 72])
  const requests: RequestInit[] = []
  t.mock.method(GoogleAuth.prototype, 'getClient', async () => ({
    getAccessToken: async () => ({ token: 'test-token' }),
  }))
  t.mock.method(globalThis, 'fetch', async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    requests.push(init ?? {})
    return new Response(JSON.stringify({ document: { text: 'OCR text', pages: [{}] } }), { status: 200 })
  })

  const result = await ocrDocumentAiEnterprisePages(
    Buffer.from(await pdf.save()),
    [1],
    { project: 'casechain-test', location: DOCUMENT_AI_REQUIRED_LOCATION, processorId: '123456', processorVersion: null, credentials: { project_id: 'casechain-test' } },
  )

  assert.equal(result?.get(1)?.text, 'OCR text')
  assert.equal(requests.length, 1)
  const request = JSON.parse(String(requests[0].body)) as { processOptions: { ocrConfig: Record<string, unknown> } }
  assert.deepEqual(request.processOptions.ocrConfig, { enableNativePdfParsing: false })
  assert.equal('enableImageQualityScores' in request.processOptions.ocrConfig, false)
})

test('Document AI table cells retain bounded structural coordinates and canonical geometry', () => {
  const cells = tableCellsFromResponse('Total 1,000', {
    tables: [{
      headerRows: [],
      bodyRows: [{ cells: [{
        rowSpan: 1, colSpan: 2,
        layout: {
          textAnchor: { textSegments: [{ startIndex: 0, endIndex: 11 }] },
          boundingPoly: { normalizedVertices: [{ x: 0.2, y: 0.3 }, { x: 0.6, y: 0.3 }, { x: 0.6, y: 0.4 }, { x: 0.2, y: 0.4 }] },
        },
      }] }],
    }],
  })

  assert.deepEqual(cells, [{
    table_index: 0, row_index: 0, column_index: 0, row_span: 1, column_span: 2, reading_order: 0,
    text: 'Total 1,000', x: 0.2, y: 0.3, width: 0.4, height: 0.1,
  }])
})
