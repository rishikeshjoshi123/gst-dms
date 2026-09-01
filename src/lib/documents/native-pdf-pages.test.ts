import assert from 'node:assert/strict'
import test from 'node:test'
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'

import {
  assessNativePageQuality,
  extractNativePdfPages,
  nativeTextWordAnchors,
} from './native-pdf-pages'
import { acquireDocumentPageText } from './page-acquisition'

async function textPdf(): Promise<Buffer> {
  const pdf = await PDFDocument.create()
  const page = pdf.addPage([612, 792])
  const font = await pdf.embedFont(StandardFonts.Helvetica)
  page.drawText('Notice issued under section 73 of the CGST Act.', {
    x: 64, y: 700, size: 12, font, color: rgb(0, 0, 0),
  })
  return Buffer.from(await pdf.save())
}

test('native PDF extraction retains page text and normalized word geometry', async () => {
  const pages = await extractNativePdfPages(await textPdf())

  assert.equal(pages.length, 1)
  assert.match(pages[0].text, /Notice issued under section 73/u)
  assert.ok(pages[0].words.length >= 6)
  assert.deepEqual(Object.keys(pages[0].words[0]).sort(), ['height', 'text', 'width', 'x', 'y'])
  assert.ok(pages[0].words.every((word) => word.x >= 0 && word.x <= 1 && word.y >= 0 && word.y <= 1))
})

test('quality gate rejects sparse, broken, and suspicious image-heavy native pages', () => {
  assert.deepEqual(assessNativePageQuality({
    text: 'few', words: [], imageOperationCount: 1, pageArea: 612 * 792,
  }), {
    accepted: false,
    reasons: ['sparse_text', 'implausible_text_density', 'suspicious_image_mixed_page'],
  })
  assert.equal(assessNativePageQuality({
    text: `A complete \ufffd text layer with enough words to avoid a sparse result and no image operations at all.`,
    words: Array.from({ length: 8 }, () => ({ text: 'word', x: 0, y: 0, width: 0.1, height: 0.1 })),
    imageOperationCount: 0,
    pageArea: 612 * 792,
  }).reasons.includes('replacement_character'), true)
})

test('native-first acquisition writes a complete native page without Document AI configuration', async () => {
  const result = await acquireDocumentPageText(await textPdf(), 1)

  assert.equal(result.kind, 'complete')
  if (result.kind !== 'complete') return
  assert.equal(result.pages[0].acquisition_method, 'native_pdf')
  assert.equal(result.pages[0].ocr_processor_identifier, null)
  assert.match(result.pages[0].text, /CGST Act/u)
})

test('rotated native text splits anchors along its transformed baseline', () => {
  const anchors = nativeTextWordAnchors({
    str: 'ALPHA BRAVO',
    transform: [10, 0, 0, 10, 100, 100],
    width: 120,
    height: 10,
    hasEOL: false,
  }, {
    width: 1000,
    height: 1000,
    // A 90-degree viewport rotation maps the source baseline onto the
    // vertical screen axis while preserving top-left normalized coordinates.
    convertToViewportPoint: (x, y) => [y, 1000 - x],
  })

  assert.equal(anchors.length, 2)
  assert.equal(anchors[0].text, 'ALPHA')
  assert.equal(anchors[1].text, 'BRAVO')
  assert.equal(anchors[0].x, anchors[1].x)
  assert.ok(anchors[0].y > anchors[1].y)
  assert.ok(anchors.every((anchor) => anchor.width > 0 && anchor.height > 0))
})
