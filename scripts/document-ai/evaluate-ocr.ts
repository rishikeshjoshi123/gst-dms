/**
 * Local, explicit evaluation harness for Google Document AI Enterprise OCR.
 *
 * It never writes credentials or source PDFs. It writes provider JSON,
 * extracted text, and compact page metrics to the selected local output
 * directory so a human can compare native, scanned, Hindi/mixed, and table
 * documents before the production OCR adapter is promoted.
 */

import { createHash, randomUUID } from 'node:crypto'
import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { basename, extname, join, resolve } from 'node:path'
import { GoogleAuth } from 'google-auth-library'
import { PDFDocument } from 'pdf-lib'
import { assessNativePageQuality, extractNativePdfPages } from '../../src/lib/documents/native-pdf-pages'

type Mode = 'page' | 'whole' | 'both'

type CliOptions = {
  input: string
  output: string
  mode: Mode
  pageSpec?: string
  enableNativePdfParsing: boolean
  includeProcessOptions: boolean
  languageHints: string[]
}

type TextAnchor = {
  textSegments?: Array<{ startIndex?: string | number; endIndex?: string | number }>
}

type Layout = {
  textAnchor?: TextAnchor
  confidence?: number
  boundingPoly?: {
    normalizedVertices?: Array<{ x?: number; y?: number }>
  }
}

type DocumentAiPage = {
  pageNumber?: number
  dimension?: { width?: number; height?: number; unit?: string }
  detectedLanguages?: Array<{ languageCode?: string; confidence?: number }>
  tokens?: Array<{ layout?: Layout }>
  imageQualityScores?: {
    qualityScore?: number
    detectedDefects?: Array<{ type?: string; confidence?: number }>
  }
}

type DocumentAiResponse = {
  document?: {
    text?: string
    pages?: DocumentAiPage[]
  }
}

type PageSummary = {
  sourcePageNumber: number
  providerPageNumber: number
  textLength: number
  tokenCount: number
  averageTokenConfidence: number | null
  dimension: DocumentAiPage['dimension'] | null
  detectedLanguages: NonNullable<DocumentAiPage['detectedLanguages']>
  imageQuality: DocumentAiPage['imageQualityScores'] | null
  observedRoute: 'native' | 'ocr'
  elapsedMs: number
  billedPages: number
  nativeQuality: { accepted: boolean; reasons: string[] }
  rawSha256: string | null
}
type ProviderPageSummary = Omit<PageSummary, 'observedRoute' | 'elapsedMs' | 'billedPages' | 'nativeQuality' | 'rawSha256'>

const HELP = `Usage:
  npx tsx scripts/document-ai/evaluate-ocr.ts --input <pdf-or-directory> [options]

Required environment:
  GOOGLE_APPLICATION_CREDENTIALS_JSON
  GOOGLE_CLOUD_PROJECT (optional when present in the service-account JSON)
  DOCUMENT_AI_LOCATION=asia-south1
  DOCUMENT_AI_OCR_PROCESSOR_ID
  DOCUMENT_AI_OCR_PROCESSOR_VERSION (optional)

Options:
  --mode page|whole|both       Default: page. "both" bills the selected pages twice.
  --pages 1,3-5               Evaluate only selected 1-based source pages.
  --output <directory>        Default: a timestamped directory under the OS temp folder.
  --native-pdf-parsing <bool> Default: true. Disable only for an explicit comparison.
  --process-options <bool>    Default: true. Disable only to isolate provider validation errors.
  --language-hints hi,en      Optional BCP-47 hints; omission is normally preferred.
  --help

Notes:
  - Online whole-document evaluation is deliberately capped at 15 selected pages.
  - Page mode safely handles longer PDFs by sending one copied page per request.
  - No source PDF or credential is copied into the output directory.
`

function parseBoolean(value: string, flag: string): boolean {
  if (value === 'true') return true
  if (value === 'false') return false
  throw new Error(`${flag} must be true or false`)
}

function parseArgs(argv: string[]): CliOptions | null {
  if (argv.includes('--help')) {
    if (argv.length !== 1) throw new Error('--help cannot be combined with other options')
    return null
  }

  let input = ''
  let output = ''
  let mode: Mode = 'page'
  let pageSpec: string | undefined
  let enableNativePdfParsing = true
  let includeProcessOptions = true
  let languageHints: string[] = []
  const seen = new Set<string>()

  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index]
    const value = argv[index + 1]
    if (!flag?.startsWith('--')) throw new Error(`Unexpected argument: ${flag}`)
    if (seen.has(flag)) throw new Error(`Repeated option: ${flag}`)
    seen.add(flag)
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`)

    if (flag === '--input') input = value
    else if (flag === '--output') output = value
    else if (flag === '--mode') {
      if (!['page', 'whole', 'both'].includes(value)) throw new Error('--mode must be page, whole, or both')
      mode = value as Mode
    } else if (flag === '--pages') pageSpec = value
    else if (flag === '--native-pdf-parsing') enableNativePdfParsing = parseBoolean(value, flag)
    else if (flag === '--process-options') includeProcessOptions = parseBoolean(value, flag)
    else if (flag === '--language-hints') {
      languageHints = value.split(',').map((hint) => hint.trim()).filter(Boolean)
    } else throw new Error(`Unknown option: ${flag}`)
    index += 1
  }

  if (!input) throw new Error('--input is required')
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
  return {
    input: resolve(input),
    output: output ? resolve(output) : join(tmpdir(), `casechain-document-ai-ocr-${timestamp}`),
    mode,
    pageSpec,
    enableNativePdfParsing,
    includeProcessOptions,
    languageHints,
  }
}

function parsePageSelection(spec: string | undefined, pageCount: number): number[] {
  if (!spec) return Array.from({ length: pageCount }, (_, index) => index + 1)
  const selected = new Set<number>()
  for (const segment of spec.split(',')) {
    const match = segment.trim().match(/^(\d+)(?:-(\d+))?$/)
    if (!match) throw new Error(`Invalid page selection segment: ${segment}`)
    const start = Number(match[1])
    const end = Number(match[2] ?? match[1])
    if (start < 1 || end < start || end > pageCount) {
      throw new Error(`Page selection ${segment} is outside 1-${pageCount}`)
    }
    for (let page = start; page <= end; page += 1) selected.add(page)
  }
  return [...selected].sort((left, right) => left - right)
}

async function pdfInputs(inputPath: string): Promise<string[]> {
  const inputStat = await stat(inputPath)
  if (inputStat.isFile()) {
    if (extname(inputPath).toLowerCase() !== '.pdf') throw new Error('The input file must be a PDF')
    return [inputPath]
  }
  if (!inputStat.isDirectory()) throw new Error('The input must be a PDF or directory')
  const entries = await readdir(inputPath, { withFileTypes: true })
  const files = entries
    .filter((entry) => entry.isFile() && extname(entry.name).toLowerCase() === '.pdf')
    .map((entry) => join(inputPath, entry.name))
    .sort((left, right) => left.localeCompare(right))
  if (files.length === 0) throw new Error('The input directory contains no PDF files')
  return files
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

function summariseResponse(response: DocumentAiResponse, sourcePages: number[]): {
  text: string
  pages: ProviderPageSummary[]
} {
  const text = response.document?.text ?? ''
  const pages = response.document?.pages ?? []
  return {
    text,
    pages: pages.map((page, index) => {
      const confidences = (page.tokens ?? [])
        .map((token) => token.layout?.confidence)
        .filter((value): value is number => typeof value === 'number' && Number.isFinite(value))
      const pageText = (page.tokens ?? []).map((token) => anchoredText(text, token.layout?.textAnchor)).join(' ')
      return {
        sourcePageNumber: sourcePages[index] ?? index + 1,
        providerPageNumber: page.pageNumber ?? index + 1,
        textLength: pageText.length,
        tokenCount: page.tokens?.length ?? 0,
        averageTokenConfidence: confidences.length > 0
          ? confidences.reduce((total, value) => total + value, 0) / confidences.length
          : null,
        dimension: page.dimension ?? null,
        detectedLanguages: page.detectedLanguages ?? [],
        imageQuality: page.imageQualityScores ?? null,
      }
    }),
  }
}

function validPageResponse(response: DocumentAiResponse): boolean {
  const page = response.document?.pages?.[0]
  const text = response.document?.text
  return Boolean(page && typeof text === 'string' && text.length > 0 && (page.tokens?.length ?? 0) > 0)
}

async function selectedPdf(source: PDFDocument, sourcePages: number[]): Promise<Buffer> {
  const selected = await PDFDocument.create()
  const copied = await selected.copyPages(source, sourcePages.map((page) => page - 1))
  for (const page of copied) selected.addPage(page)
  return Buffer.from(await selected.save())
}

function safeName(filePath: string): string {
  return basename(filePath, extname(filePath)).replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'document'
}

async function writeJson(filePath: string, value: unknown): Promise<void> {
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 })
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2))
  if (!options) {
    console.log(HELP)
    return
  }
  const activeOptions = options

  const credentialsJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
  if (!credentialsJson) throw new Error('GOOGLE_APPLICATION_CREDENTIALS_JSON is required')
  const credentials = JSON.parse(credentialsJson) as { project_id?: string }
  const project = process.env.GOOGLE_CLOUD_PROJECT ?? credentials.project_id
  const location = process.env.DOCUMENT_AI_LOCATION
  const processorId = process.env.DOCUMENT_AI_OCR_PROCESSOR_ID
  const processorVersion = process.env.DOCUMENT_AI_OCR_PROCESSOR_VERSION
  if (!project) throw new Error('GOOGLE_CLOUD_PROJECT is required when the credential has no project_id')
  if (!location) throw new Error('DOCUMENT_AI_LOCATION is required')
  if (location !== 'asia-south1') throw new Error('This approved evaluation harness requires DOCUMENT_AI_LOCATION=asia-south1')
  if (!processorId) throw new Error('DOCUMENT_AI_OCR_PROCESSOR_ID is required')

  const auth = new GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  })
  const authClient = await auth.getClient()
  const resource = processorVersion
    ? `projects/${project}/locations/${location}/processors/${processorId}/processorVersions/${processorVersion}`
    : `projects/${project}/locations/${location}/processors/${processorId}`
  const endpoint = `https://${location}-documentai.googleapis.com/v1/${resource}:process`

  async function processPdf(bytes: Buffer): Promise<{ response: DocumentAiResponse; elapsedMs: number }> {
    const started = performance.now()
    const accessToken = await authClient.getAccessToken()
    if (!accessToken.token) throw new Error('Google authentication returned no access token')
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        rawDocument: {
          content: bytes.toString('base64'),
          mimeType: 'application/pdf',
        },
        ...(activeOptions.includeProcessOptions
          ? {
              processOptions: {
                ocrConfig: {
                  enableNativePdfParsing: activeOptions.enableNativePdfParsing,
                  ...(activeOptions.languageHints.length > 0
                    ? { hints: { languageHints: activeOptions.languageHints } }
                    : {}),
                },
              },
            }
          : {}),
      }),
    })
    const raw = await response.text()
    if (!response.ok) {
      let providerMessage = ''
      try {
        const payload = JSON.parse(raw) as {
          error?: { message?: string; status?: string; details?: unknown[] }
        }
        const details = payload.error?.details?.length
          ? JSON.stringify(payload.error.details).slice(0, 2_000)
          : ''
        providerMessage = [payload.error?.status, payload.error?.message, details]
          .filter(Boolean)
          .join(': ')
      } catch {
        // Do not echo an unexpected provider body because it could contain source content.
      }
      throw new Error(
        `Document AI request failed with HTTP ${response.status}${providerMessage ? ` (${providerMessage})` : ''}`,
      )
    }
    const parsed = JSON.parse(raw) as DocumentAiResponse
    if (!validPageResponse(parsed)) throw new Error('Document AI response did not prove one selected-page OCR result')
    return { response: parsed, elapsedMs: Math.round(performance.now() - started) }
  }

  await mkdir(options.output, { recursive: true, mode: 0o700 })
  const files = await pdfInputs(options.input)
  const manifest: Array<Record<string, unknown>> = []

  for (const filePath of files) {
    const bytes = await readFile(filePath)
    const source = await PDFDocument.load(bytes)
    const sourcePages = parsePageSelection(options.pageSpec, source.getPageCount())
    const sourceSha256 = createHash('sha256').update(bytes).digest('hex')
    const documentOutputName = `${safeName(filePath)}-${sourceSha256.slice(0, 12)}`
    const documentOutput = join(options.output, documentOutputName)
    await mkdir(documentOutput, { recursive: true, mode: 0o700 })
    const record: Record<string, unknown> = {
      sourceFileName: basename(filePath),
      sourceSha256,
      sourcePageCount: source.getPageCount(),
      selectedPages: sourcePages,
      outputDirectory: documentOutputName,
      modes: [],
    }

    if (options.mode === 'whole' || options.mode === 'both') {
      if (sourcePages.length > 15) {
        throw new Error(`Whole-document online evaluation is capped at 15 selected pages; ${basename(filePath)} selected ${sourcePages.length}`)
      }
      const wholeBytes = sourcePages.length === source.getPageCount()
        ? bytes
        : await selectedPdf(source, sourcePages)
      const processed = await processPdf(wholeBytes)
      const summary = summariseResponse(processed.response, sourcePages)
      await writeJson(join(documentOutput, 'whole.raw.json'), processed.response)
      await writeJson(join(documentOutput, 'whole.summary.json'), summary.pages.map((page) => ({ ...page, observedRoute: 'ocr', elapsedMs: processed.elapsedMs, billedPages: sourcePages.length, nativeQuality: { accepted: false, reasons: ['whole_document_comparison'] }, rawSha256: null })))
      await writeFile(join(documentOutput, 'whole.text.txt'), summary.text, { mode: 0o600 })
      ;(record.modes as string[]).push('whole')
    }

    if (options.mode === 'page' || options.mode === 'both') {
      const nativePages = await extractNativePdfPages(bytes)
      const pageSummaries: PageSummary[] = []
      const pageTexts: string[] = []
      for (const sourcePageNumber of sourcePages) {
        const nativePage = nativePages[sourcePageNumber - 1]
        if (!nativePage) throw new Error(`Native page identity missing for selected page ${sourcePageNumber}`)
        const nativeQuality = assessNativePageQuality(nativePage)
        const prefix = `page-${String(sourcePageNumber).padStart(4, '0')}`
        if (nativeQuality.accepted) {
          pageSummaries.push({ sourcePageNumber, providerPageNumber: 0, textLength: nativePage.text.length, tokenCount: nativePage.words.length, averageTokenConfidence: null, dimension: null, detectedLanguages: [], imageQuality: null, observedRoute: 'native', elapsedMs: 0, billedPages: 0, nativeQuality, rawSha256: null })
          pageTexts.push(`===== Source page ${sourcePageNumber} =====\n${nativePage.text}`)
        } else {
          const processed = await processPdf(await selectedPdf(source, [sourcePageNumber]))
          const summary = summariseResponse(processed.response, [sourcePageNumber])
          if (summary.pages.length !== 1 || summary.pages[0]?.providerPageNumber !== 1) throw new Error(`Document AI response page identity mismatch for selected page ${sourcePageNumber}`)
          const rawPath = join(documentOutput, `${prefix}.raw.json`)
          await writeJson(rawPath, processed.response)
          await writeFile(join(documentOutput, `${prefix}.text.txt`), summary.text, { mode: 0o600 })
          pageSummaries.push(...summary.pages.map((page) => ({ ...page, observedRoute: 'ocr' as const, elapsedMs: processed.elapsedMs, billedPages: 1, nativeQuality, rawSha256: createHash('sha256').update(JSON.stringify(processed.response, null, 2) + '\n').digest('hex') })))
          pageTexts.push(`===== Source page ${sourcePageNumber} =====\n${summary.text}`)
        }
      }
      await writeJson(join(documentOutput, 'pages.summary.json'), pageSummaries)
      await writeFile(join(documentOutput, 'pages.text.txt'), `${pageTexts.join('\n\n')}\n`, { mode: 0o600 })
      ;(record.modes as string[]).push('page')
    }

    manifest.push(record)
  }

  await writeJson(join(options.output, 'run-manifest.json'), {
    schemaVersion: 2,
    runId: randomUUID(),
    createdAt: new Date().toISOString(),
    location,
    processorVersion: processorVersion ?? 'processor-default',
    mode: options.mode,
    enableNativePdfParsing: options.enableNativePdfParsing,
    includeProcessOptions: options.includeProcessOptions,
    languageHints: options.languageHints,
    files: manifest,
  })
  console.log(`Document AI evaluation output: ${options.output}`)
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : 'Document AI evaluation failed')
  process.exitCode = 1
})
