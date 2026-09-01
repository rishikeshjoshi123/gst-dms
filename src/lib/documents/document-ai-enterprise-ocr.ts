import { GoogleAuth } from 'google-auth-library'
import { PDFDocument } from 'pdf-lib'

import type { PageWordAnchor } from './native-pdf-pages'

export const DOCUMENT_AI_REQUIRED_LOCATION = 'asia-south1'
type Environment = Record<string, string | undefined>

export type DocumentAiOcrConfiguration = {
  project: string
  location: typeof DOCUMENT_AI_REQUIRED_LOCATION
  processorId: string
  processorVersion: string | null
  credentials: Record<string, unknown>
}

export type DocumentAiOcrPage = {
  text: string
  words: PageWordAnchor[]
  detectedLanguages: string[]
  processorId: string
  processorVersion: string | null
}

type TextAnchor = { textSegments?: Array<{ startIndex?: string | number; endIndex?: string | number }> }
type Layout = {
  textAnchor?: TextAnchor
  boundingPoly?: { normalizedVertices?: Array<{ x?: number; y?: number }> }
}
type DocumentAiResponse = {
  document?: {
    text?: string
    pages?: Array<{
      detectedLanguages?: Array<{ languageCode?: string }>
      tokens?: Array<{ layout?: Layout }>
    }>
  }
}
type DocumentAiProviderPage = NonNullable<NonNullable<DocumentAiResponse['document']>['pages']>[number]

function configuredText(value: string | undefined): string | null {
  const normalized = value?.trim()
  return normalized ? normalized : null
}

export function resolveDocumentAiOcrConfiguration(environment: Environment = process.env): DocumentAiOcrConfiguration | null {
  const credentialsJson = configuredText(environment.GOOGLE_APPLICATION_CREDENTIALS_JSON)
  const location = configuredText(environment.DOCUMENT_AI_LOCATION)
  const processorId = configuredText(environment.DOCUMENT_AI_OCR_PROCESSOR_ID)
  if (!credentialsJson || location !== DOCUMENT_AI_REQUIRED_LOCATION || !processorId) return null

  try {
    const credentials = JSON.parse(credentialsJson) as Record<string, unknown>
    const project = configuredText(environment.GOOGLE_CLOUD_PROJECT) ?? (typeof credentials.project_id === 'string' ? credentials.project_id : null)
    if (!project) return null
    return {
      project,
      location: DOCUMENT_AI_REQUIRED_LOCATION,
      processorId,
      processorVersion: configuredText(environment.DOCUMENT_AI_OCR_PROCESSOR_VERSION),
      credentials,
    }
  } catch {
    return null
  }
}

function integerIndex(value: string | number | undefined, fallback: number): number {
  if (value === undefined) return fallback
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

function anchoredText(text: string, anchor: TextAnchor | undefined): string {
  return (anchor?.textSegments ?? []).map((segment) => {
    const start = integerIndex(segment.startIndex, 0)
    const end = integerIndex(segment.endIndex, start)
    return text.slice(start, end)
  }).join('')
}

function bounded(value: number): number {
  return Math.max(0, Math.min(1, Number(value.toFixed(6))))
}

function wordsFromResponse(text: string, page: DocumentAiProviderPage): PageWordAnchor[] {
  return (page.tokens ?? []).flatMap((token) => {
    const word = anchoredText(text, token.layout?.textAnchor).trim()
    const vertices = token.layout?.boundingPoly?.normalizedVertices ?? []
    if (!word || vertices.length === 0 || word.length > 256) return []
    const xValues = vertices.map((vertex) => vertex.x).filter((value): value is number => typeof value === 'number' && Number.isFinite(value))
    const yValues = vertices.map((vertex) => vertex.y).filter((value): value is number => typeof value === 'number' && Number.isFinite(value))
    if (xValues.length === 0 || yValues.length === 0) return []
    const minX = bounded(Math.min(...xValues)); const maxX = bounded(Math.max(...xValues))
    const minY = bounded(Math.min(...yValues)); const maxY = bounded(Math.max(...yValues))
    if (maxX <= minX || maxY <= minY) return []
    return [{ text: word, x: minX, y: minY, width: maxX - minX, height: maxY - minY }]
  })
}

async function selectedPdf(pdfBytes: Buffer, pageNumber: number): Promise<Buffer> {
  const source = await PDFDocument.load(pdfBytes, { ignoreEncryption: false, updateMetadata: false })
  const selected = await PDFDocument.create()
  const [page] = await selected.copyPages(source, [pageNumber - 1])
  selected.addPage(page)
  return Buffer.from(await selected.save())
}

export async function ocrDocumentAiEnterprisePages(
  pdfBytes: Buffer,
  pageNumbers: number[],
  configuration: DocumentAiOcrConfiguration,
): Promise<Map<number, DocumentAiOcrPage> | null> {
  if (configuration.location !== DOCUMENT_AI_REQUIRED_LOCATION || pageNumbers.length === 0) return null
  try {
    const auth = new GoogleAuth({
      credentials: configuration.credentials,
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    })
    const client = await auth.getClient()
    const resource = configuration.processorVersion
      ? `projects/${configuration.project}/locations/${configuration.location}/processors/${configuration.processorId}/processorVersions/${configuration.processorVersion}`
      : `projects/${configuration.project}/locations/${configuration.location}/processors/${configuration.processorId}`
    const endpoint = `https://${configuration.location}-documentai.googleapis.com/v1/${resource}:process`
    const result = new Map<number, DocumentAiOcrPage>()

    for (const pageNumber of pageNumbers) {
      const accessToken = await client.getAccessToken()
      if (!accessToken.token) return null
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          rawDocument: { content: (await selectedPdf(pdfBytes, pageNumber)).toString('base64'), mimeType: 'application/pdf' },
          processOptions: { ocrConfig: { enableNativePdfParsing: false, enableImageQualityScores: true } },
        }),
      })
      if (!response.ok) return null
      const providerResponse = await response.json() as DocumentAiResponse
      const page = providerResponse.document?.pages?.[0]
      const providerText = providerResponse.document?.text ?? ''
      // The pre-existing artifact contract excludes control characters. Keep
      // the OCR words and their anchors exact, while representing provider
      // line layout as ordinary spaces in its one-line search text field.
      const text = providerText.replace(/[\t\n\r\f\v]+/gu, ' ').trim()
      if (!page || !text || /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(text) || text.length > 8000) return null
      const words = wordsFromResponse(providerText, page)
      result.set(pageNumber, {
        text,
        words: words.length > 2000 ? [] : words,
        detectedLanguages: [...new Set((page.detectedLanguages ?? [])
          .map((language) => language.languageCode?.trim())
          .filter((language): language is string => Boolean(language)))],
        processorId: configuration.processorId,
        processorVersion: configuration.processorVersion,
      })
    }
    return result
  } catch {
    return null
  }
}
