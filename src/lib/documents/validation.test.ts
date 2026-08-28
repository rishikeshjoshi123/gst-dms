import assert from 'node:assert/strict'
import test from 'node:test'
import { EncryptedPDFError, PDFDocument } from 'pdf-lib'
import { safeValidationOutcome, validatePdfBytes } from './validation'

test('validates a generated one-page PDF', async () => {
  const pdf = await PDFDocument.create(); pdf.addPage()
  const bytes = await pdf.save()
  assert.deepEqual(await validatePdfBytes(bytes, bytes.byteLength), { outcome: 'ready', pageCount: 1 })
})
test('rejects malformed PDF bytes', async () => {
  assert.deepEqual(await validatePdfBytes(new Uint8Array([1, 2, 3]), 3), { outcome: 'invalid_pdf', pageCount: null })
})
test('classifies encrypted parser errors safely', () => {
  assert.equal(safeValidationOutcome(new EncryptedPDFError()), 'encrypted_pdf')
})
