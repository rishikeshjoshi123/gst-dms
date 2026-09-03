/**
 * Content-safe, local-only gate for the approved Document AI page-acquisition
 * benchmark. The input manifest is deliberately supplied outside the repo.
 */
import { createHash } from 'node:crypto'
import { readFile, stat, writeFile } from 'node:fs/promises'
import { basename, extname, join, resolve } from 'node:path'

export const APPROVED_PROCESSOR_VERSION = 'pretrained-ocr-v2.1.1-2025-01-31'
export const REQUIRED_CATEGORIES = [
  'native_english', 'scanned_english', 'hindi', 'mixed_language', 'handwriting',
  'stamps', 'tables', 'rotation', 'poor_scan',
] as const

type Category = (typeof REQUIRED_CATEGORIES)[number]
type Verdict = 'pass' | 'fail' | 'unknown' | 'not_applicable'
type Action = 'native' | 'ocr'
type Label = { verdict: Verdict; evidence: 'adjudicated' }

export type BenchmarkCase = {
  caseId: string
  sourceSha256: string
  sourcePageNumber: number
  evaluatorDocumentDirectory: string
  categories: Category[]
  routing: { expectedAction: Action; evidence: 'adjudicated' }
  checks: Record<'gstin' | 'reference' | 'date' | 'amount' | 'table' | 'anchor', Label>
  quality: { characterAccuracy: number | null; wordAccuracy: number | null; evidence: 'adjudicated' }
}

export type BenchmarkManifest = {
  schemaVersion: 1
  benchmarkRunId: string
  evaluatorRunId: string
  processorVersion: string
  location: string
  billing: { currency: string; costPerBilledPage: number }
  cases: BenchmarkCase[]
}

type EvaluatorFile = { sourceFileName?: unknown; sourceSha256?: string; sourcePageCount?: unknown; selectedPages?: unknown; outputDirectory?: unknown }
type EvaluatorPage = { sourcePageNumber?: unknown; providerPageNumber?: unknown; observedRoute?: unknown; elapsedMs?: unknown; billedPages?: unknown; rawSha256?: unknown; nativeQuality?: { accepted?: unknown; reasons?: unknown }; textLength?: unknown; tokenCount?: unknown }
type EvaluatorManifest = { schemaVersion?: unknown; runId?: unknown; location?: string; processorVersion?: string; mode?: unknown; files?: EvaluatorFile[] }
type Metric = { correct: number; failed: number; unknown: number; notApplicable: number; denominator: number; accuracy: number | null }

function fail(message: string): never { throw new Error(`OCR acquisition benchmark: ${message}`) }
function isSha256(value: unknown): value is string { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) }
function isSafeSegment(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9._-]+$/.test(value) && !value.startsWith('.')
}
function evaluatorDirectory(file: EvaluatorFile): string | null {
  if (typeof file.sourceFileName !== 'string' || !isSha256(file.sourceSha256)) return null
  const name = basename(file.sourceFileName, extname(file.sourceFileName)).replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'document'
  return `${name}-${file.sourceSha256.slice(0, 12)}`
}
function assertFiniteNonNegative(value: unknown, name: string): asserts value is number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) fail(`${name} must be a finite non-negative number`)
}

export function validateManifest(manifest: BenchmarkManifest): void {
  if (manifest?.schemaVersion !== 1) fail('schemaVersion must be 1')
  if (!isSafeSegment(manifest.benchmarkRunId) || !isSafeSegment(manifest.evaluatorRunId)) fail('run IDs must be safe non-empty identifiers')
  if (manifest.processorVersion !== APPROVED_PROCESSOR_VERSION) fail(`processorVersion must equal approved pin ${APPROVED_PROCESSOR_VERSION}`)
  if (manifest.location !== 'asia-south1') fail('location must be asia-south1')
  if (!manifest.billing || !/^[A-Z]{3}$/.test(manifest.billing.currency)) fail('billing.currency must be an ISO-like uppercase code')
  assertFiniteNonNegative(manifest.billing.costPerBilledPage, 'billing.costPerBilledPage')
  if (manifest.billing.costPerBilledPage === 0) fail('billing.costPerBilledPage must be positive')
  if (!Array.isArray(manifest.cases) || manifest.cases.length < 60 || manifest.cases.length > 100) fail('must contain exactly 60–100 selected pages')

  const caseIds = new Set<string>(); const sourcePages = new Set<string>(); const covered = new Set<Category>(); const directorySources = new Map<string, string>()
  for (const entry of manifest.cases) {
    if (!isSafeSegment(entry.caseId)) fail('caseId must be a safe non-empty identifier')
    if (caseIds.has(entry.caseId)) fail(`duplicate caseId ${entry.caseId}`); caseIds.add(entry.caseId)
    if (!isSha256(entry.sourceSha256)) fail(`case ${entry.caseId} has invalid sourceSha256`)
    if (!Number.isInteger(entry.sourcePageNumber) || entry.sourcePageNumber < 1) fail(`case ${entry.caseId} has invalid sourcePageNumber`)
    const sourcePage = `${entry.sourceSha256}:${entry.sourcePageNumber}`
    if (sourcePages.has(sourcePage)) fail(`duplicate source page selected for case ${entry.caseId}`); sourcePages.add(sourcePage)
    if (!isSafeSegment(entry.evaluatorDocumentDirectory)) fail(`case ${entry.caseId} has unsafe evaluatorDocumentDirectory`)
    const existingDirectorySource = directorySources.get(entry.evaluatorDocumentDirectory)
    if (existingDirectorySource && existingDirectorySource !== entry.sourceSha256) fail(`evaluatorDocumentDirectory ${entry.evaluatorDocumentDirectory} maps to more than one source SHA-256`)
    directorySources.set(entry.evaluatorDocumentDirectory, entry.sourceSha256)
    if (!Array.isArray(entry.categories) || entry.categories.length === 0) fail(`case ${entry.caseId} needs categories`)
    for (const category of entry.categories) {
      if (!REQUIRED_CATEGORIES.includes(category)) fail(`case ${entry.caseId} has unknown category`)
      covered.add(category)
    }
    if (!entry.routing || !['native', 'ocr'].includes(entry.routing.expectedAction) || entry.routing.evidence !== 'adjudicated') fail(`case ${entry.caseId} has incomplete routing label evidence`)
    for (const name of ['gstin', 'reference', 'date', 'amount', 'table', 'anchor'] as const) {
      const check = entry.checks?.[name]
      if (!check || !['pass', 'fail', 'unknown', 'not_applicable'].includes(check.verdict) || check.evidence !== 'adjudicated') fail(`case ${entry.caseId} has incomplete ${name} label evidence`)
    }
    if (!entry.quality || entry.quality.evidence !== 'adjudicated') fail(`case ${entry.caseId} has missing quality label evidence`)
    for (const [name, value] of Object.entries({ characterAccuracy: entry.quality.characterAccuracy, wordAccuracy: entry.quality.wordAccuracy })) {
      if (value !== null && (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1)) fail(`case ${entry.caseId} has invalid ${name}`)
    }
  }
  for (const category of REQUIRED_CATEGORIES) if (!covered.has(category)) fail(`missing required category ${category}`)
}

function metric(labels: Label[]): Metric {
  const correct = labels.filter((entry) => entry.verdict === 'pass').length
  const failed = labels.filter((entry) => entry.verdict === 'fail').length
  const unknown = labels.filter((entry) => entry.verdict === 'unknown').length
  const notApplicable = labels.filter((entry) => entry.verdict === 'not_applicable').length
  const denominator = correct + failed
  return { correct, failed, unknown, notApplicable, denominator, accuracy: denominator === 0 ? null : correct / denominator }
}

async function sha256(filePath: string): Promise<string> { return createHash('sha256').update(await readFile(filePath)).digest('hex') }
async function existsFile(filePath: string): Promise<void> { if (!(await stat(filePath)).isFile()) fail(`missing evaluator output linkage ${basename(filePath)}`) }

export async function verifyEvaluatorLinkage(manifest: BenchmarkManifest, outputDirectory: string): Promise<{ authoritativeEvaluatorRunManifestSha256: string; outputHashes: { count: number; sha256: string }; evidence: Map<string, EvaluatorPage> }> {
  const manifestPath = join(outputDirectory, 'run-manifest.json')
  await existsFile(manifestPath)
  const evaluator = JSON.parse(await readFile(manifestPath, 'utf8')) as EvaluatorManifest
  if (evaluator.schemaVersion !== 2 || evaluator.runId !== manifest.evaluatorRunId) fail('evaluator generated run ID does not match benchmark declaration')
  if (evaluator.mode !== 'page' || evaluator.location !== manifest.location || evaluator.processorVersion !== manifest.processorVersion) fail('evaluator must be matching page-mode processor/location run')
  if (!Array.isArray(evaluator.files)) fail('evaluator run-manifest has no files')
  const evaluatorSelections = new Set<string>()
  for (const file of evaluator.files) {
    if (!isSha256(file.sourceSha256) || !Array.isArray(file.selectedPages)) fail('evaluator has invalid source selection')
    if (file.selectedPages.length === 0) fail('evaluator has an empty source selection')
    for (const page of file.selectedPages) {
      if (!Number.isInteger(page) || page < 1) fail('evaluator has invalid selected page')
      const key = `${file.sourceSha256}:${page}`
      if (evaluatorSelections.has(key)) fail('evaluator has duplicate source page selection')
      evaluatorSelections.add(key)
    }
  }
  const benchmarkSelections = new Set(manifest.cases.map((entry) => `${entry.sourceSha256}:${entry.sourcePageNumber}`))
  if (evaluatorSelections.size !== benchmarkSelections.size || [...evaluatorSelections].some((key) => !benchmarkSelections.has(key))) fail('evaluator selections must exactly match benchmark cases')
  const outputHashes: string[] = []
  const evidence = new Map<string, EvaluatorPage>()
  for (const entry of manifest.cases) {
    const matches = evaluator.files.filter((candidate) => candidate.sourceSha256 === entry.sourceSha256)
    if (matches.length !== 1) fail(`case ${entry.caseId} must match exactly one evaluator source record`)
    const file = matches[0]
    const sourcePageCount = file?.sourcePageCount
    if (!file || typeof sourcePageCount !== 'number' || !Number.isInteger(sourcePageCount) || entry.sourcePageNumber > sourcePageCount || !Array.isArray(file.selectedPages) || !file.selectedPages.includes(entry.sourcePageNumber) || file.outputDirectory !== entry.evaluatorDocumentDirectory || evaluatorDirectory(file) !== entry.evaluatorDocumentDirectory) fail(`case ${entry.caseId} is not linked to selected evaluator source page`)
    const prefix = `page-${String(entry.sourcePageNumber).padStart(4, '0')}`
    const summaryPath = join(outputDirectory, entry.evaluatorDocumentDirectory, 'pages.summary.json')
    await existsFile(summaryPath)
    const pages = JSON.parse(await readFile(summaryPath, 'utf8')) as EvaluatorPage[]
    if (!Array.isArray(pages) || pages.length !== file.selectedPages.length) fail(`case ${entry.caseId} evaluator summary does not exactly cover selected pages`)
    const summarySelections = new Set<number>()
    for (const candidate of pages) {
      const sourcePageNumber = candidate.sourcePageNumber
      if (typeof sourcePageNumber !== 'number' || !Number.isInteger(sourcePageNumber) || !file.selectedPages.includes(sourcePageNumber)) fail(`case ${entry.caseId} evaluator summary contains an unselected page`)
      if (summarySelections.has(sourcePageNumber)) fail(`case ${entry.caseId} evaluator summary contains a duplicate page`)
      summarySelections.add(sourcePageNumber)
    }
    if (summarySelections.size !== file.selectedPages.length) fail(`case ${entry.caseId} evaluator summary does not exactly cover selected pages`)
    const pageMatches = Array.isArray(pages) ? pages.filter((candidate) => candidate.sourcePageNumber === entry.sourcePageNumber) : []
    if (pageMatches.length !== 1) fail(`case ${entry.caseId} must match exactly one evaluator page record`)
    const page = pageMatches[0]
    const nativeQualityValid = typeof page.nativeQuality?.accepted === 'boolean' && Array.isArray(page.nativeQuality.reasons) && page.nativeQuality.reasons.every((reason) => typeof reason === 'string')
    const nativeValid = page.observedRoute === 'native' && page.nativeQuality?.accepted === true && page.providerPageNumber === 0 && page.billedPages === 0 && page.rawSha256 === null
    const ocrValid = page.observedRoute === 'ocr' && page.nativeQuality?.accepted === false && page.providerPageNumber === 1 && page.billedPages === 1 && isSha256(page.rawSha256)
    if (!page || !nativeQualityValid || !Number.isFinite(page.elapsedMs) || Number(page.elapsedMs) < 0 || !Number.isInteger(page.billedPages) || !Number.isInteger(page.textLength) || Number(page.textLength) < 0 || !Number.isInteger(page.tokenCount) || Number(page.tokenCount) < 0 || (!nativeValid && !ocrValid)) fail(`case ${entry.caseId} has invalid evaluator acquisition evidence`)
    if (page.observedRoute === 'ocr') {
      const rawPath = join(outputDirectory, entry.evaluatorDocumentDirectory, `${prefix}.raw.json`)
      await existsFile(rawPath)
      if (await sha256(rawPath) !== page.rawSha256) fail(`case ${entry.caseId} raw output hash mismatch`)
      const raw = JSON.parse(await readFile(rawPath, 'utf8')) as { document?: { text?: unknown; pages?: Array<{ pageNumber?: unknown; tokens?: unknown[] }> } }
      const providerPage = raw.document?.pages?.[0]
      if (!raw.document || typeof raw.document.text !== 'string' || raw.document.text.trim().length === 0 || raw.document.pages?.length !== 1 || providerPage?.pageNumber !== 1 || !Array.isArray(providerPage.tokens) || !providerPage.tokens.some((token) => token && typeof token === 'object' && 'layout' in token)) fail(`case ${entry.caseId} raw provider response is not a selected-page OCR result`)
      outputHashes.push(page.rawSha256)
    }
    outputHashes.push(await sha256(summaryPath))
    evidence.set(entry.caseId, page)
  }
  return { authoritativeEvaluatorRunManifestSha256: await sha256(manifestPath), outputHashes: { count: outputHashes.length, sha256: createHash('sha256').update(outputHashes.sort().join('\n')).digest('hex') }, evidence }
}

export async function buildReport(manifest: BenchmarkManifest, outputDirectory: string, adjudicationManifestSha256: string): Promise<Record<string, unknown>> {
  if (!isSha256(adjudicationManifestSha256)) fail('adjudicationManifestSha256 must be a SHA-256')
  validateManifest(manifest)
  const linkage = await verifyEvaluatorLinkage(manifest, outputDirectory)
  const routing = { truePositive: 0, falsePositive: 0, falseNegative: 0, trueNegative: 0 }
  for (const entry of manifest.cases) {
    const observed = linkage.evidence.get(entry.caseId)?.observedRoute
    if (entry.routing.expectedAction === 'ocr' && observed === 'ocr') routing.truePositive += 1
    else if (entry.routing.expectedAction === 'native' && observed === 'ocr') routing.falsePositive += 1
    else if (entry.routing.expectedAction === 'ocr') routing.falseNegative += 1
    else routing.trueNegative += 1
  }
  const routingPrecisionDenominator = routing.truePositive + routing.falsePositive
  const routingRecallDenominator = routing.truePositive + routing.falseNegative
  const checkMetrics = Object.fromEntries((['gstin', 'reference', 'date', 'amount', 'table', 'anchor'] as const).map((name) => [name, metric(manifest.cases.map((entry) => entry.checks[name]))]))
  const criticalFailuresOrUnknown = Object.entries(checkMetrics).filter(([, value]) => value.failed > 0 || value.unknown > 0).map(([name]) => name)
  const missingCriticalCoverage = Object.entries(checkMetrics).filter(([, value]) => value.denominator < 3).map(([name]) => name)
  const character = manifest.cases.map((entry) => entry.quality.characterAccuracy).filter((value): value is number => value !== null)
  const word = manifest.cases.map((entry) => entry.quality.wordAccuracy).filter((value): value is number => value !== null)
  const totalBilledPages = [...linkage.evidence.values()].reduce((total, entry) => total + Number(entry.billedPages), 0)
  const totalLatencyMs = [...linkage.evidence.values()].reduce((total, entry) => total + Number(entry.elapsedMs), 0)
  const expectedNative = manifest.cases.filter((entry) => entry.routing.expectedAction === 'native').length
  const expectedOcr = manifest.cases.length - expectedNative
  const qualityMissing = manifest.cases.filter((entry) => linkage.evidence.get(entry.caseId)?.observedRoute === 'ocr' && (entry.quality.characterAccuracy === null || entry.quality.wordAccuracy === null))
  return {
    schemaVersion: 1, adjudicationManifestSha256, benchmarkRunId: manifest.benchmarkRunId, evaluatorRun: { generatedId: manifest.evaluatorRunId, provenance: 'matched_to_evaluator_run_manifest' },
    processor: { version: manifest.processorVersion, location: manifest.location },
    evaluatedPages: manifest.cases.length, categories: Object.fromEntries(REQUIRED_CATEGORIES.map((category) => [category, manifest.cases.filter((entry) => entry.categories.includes(category)).length])),
    routing: { ...routing, precision: routingPrecisionDenominator ? routing.truePositive / routingPrecisionDenominator : null, recall: routingRecallDenominator ? routing.truePositive / routingRecallDenominator : null },
    checks: checkMetrics,
    quality: { characterAccuracy: character.length ? character.reduce((sum, value) => sum + value, 0) / character.length : null, characterUnknown: manifest.cases.length - character.length, wordAccuracy: word.length ? word.reduce((sum, value) => sum + value, 0) / word.length : null, wordUnknown: manifest.cases.length - word.length },
    latency: { totalMs: totalLatencyMs, averageMs: totalLatencyMs / manifest.cases.length },
    billing: { currency: manifest.billing.currency, billedPages: totalBilledPages, costPerBilledPage: manifest.billing.costPerBilledPage, totalCost: totalBilledPages * manifest.billing.costPerBilledPage },
    outputLinkage: linkage,
    gate: { status: criticalFailuresOrUnknown.length === 0 && missingCriticalCoverage.length === 0 && qualityMissing.length === 0 && expectedNative > 0 && expectedOcr > 0 && routingPrecisionDenominator > 0 && routingRecallDenominator > 0 ? 'evidence_complete' : 'structurally_incomplete', qualityThresholdStatus: 'not_yet_approved', criticalFailuresOrUnknown, missingCriticalCoverage, qualityMissingCount: qualityMissing.length, missingExpectedRouting: { native: expectedNative === 0, ocr: expectedOcr === 0 } },
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2); const manifestIndex = args.indexOf('--manifest'); const outputIndex = args.indexOf('--evaluator-output'); const reportIndex = args.indexOf('--report')
  if (args.includes('--help')) {
    if (args.length !== 1) fail('--help cannot be combined with other options')
    console.log('Usage: npx tsx scripts/document-ai/ocr-acquisition-benchmark.ts --manifest <local-labelled-manifest.json> --evaluator-output <existing-evaluator-output-dir> --report <content-safe-report.json>')
    return
  }
  const input = args[manifestIndex + 1]; const output = args[outputIndex + 1]; const report = args[reportIndex + 1]
  if (!input || !output || !report || args.length !== 6) fail('supply exactly --manifest, --evaluator-output, and --report')
  const manifestBytes = await readFile(resolve(input))
  const result = await buildReport(JSON.parse(manifestBytes.toString('utf8')) as BenchmarkManifest, resolve(output), createHash('sha256').update(manifestBytes).digest('hex'))
  await writeFile(resolve(report), `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 })
  console.log(`OCR acquisition benchmark ${result.gate instanceof Object ? (result.gate as { status: string }).status : 'completed'}: ${resolve(report)}`)
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)) main().catch((error: unknown) => { console.error(error instanceof Error ? error.message : 'OCR acquisition benchmark failed'); process.exitCode = 1 })
