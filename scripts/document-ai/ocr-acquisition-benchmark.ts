/**
 * Content-safe, local-only gate for the approved Document AI page-acquisition
 * benchmark. The input manifest is deliberately supplied outside the repo.
 */
import { createHash } from 'node:crypto'
import { chmod, lstat, readFile, stat, writeFile } from 'node:fs/promises'
import { basename, extname, join, resolve } from 'node:path'

export const APPROVED_PROCESSOR_VERSION = 'pretrained-ocr-v2.1.1-2025-01-31'
export const REQUIRED_CATEGORIES = [
  'native_english', 'scanned_english', 'hindi', 'mixed_language', 'handwriting',
  'stamps', 'tables', 'rotation', 'poor_scan',
] as const

type Category = (typeof REQUIRED_CATEGORIES)[number]
type Verdict = 'pass' | 'fail' | 'unknown' | 'not_applicable'
type Action = 'native' | 'ocr'
type Label = { verdict: Verdict; evidence: 'adjudicated'; itemId: string }
type Check = { adjudicatedItemCount: number; items: Label[] }

export type BenchmarkCase = {
  caseId: string
  sourceSha256: string
  sourcePageNumber: number
  evaluatorDocumentDirectory: string
  categories: Category[]
  routing: { expectedAction: Action; evidence: 'adjudicated' }
  checks: Record<'gstin' | 'reference' | 'date' | 'amount' | 'table' | 'anchor', Check>
  quality: { characterAccuracy: number | null; wordAccuracy: number | null; evidence: 'adjudicated' }
  sourceDisposition: 'readable' | 'source_unreadable'
}

export type BenchmarkManifest = {
  schemaVersion: 2
  benchmarkRunId: string
  evaluatorRunId: string
  processorVersion: string
  location: string
  adjudication: { reviewerId: string; method: 'independent_source_comparison'; receiptSha256: string }
  billing: { currency: string; costPerBilledPage: number; usdPerCurrencyUnit: number | null; evidenceSha256: string; billedFeature: 'enterprise_ocr_page' }
  hundredPageAcquisition: { measuredPages: 100; elapsedMs: number; evidenceSha256: string } | null
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
  if (manifest?.schemaVersion !== 2) fail('schemaVersion must be 2; legacy structural reports cannot certify acceptance')
  if (!isSafeSegment(manifest.benchmarkRunId) || !isSafeSegment(manifest.evaluatorRunId)) fail('run IDs must be safe non-empty identifiers')
  if (manifest.processorVersion !== APPROVED_PROCESSOR_VERSION) fail(`processorVersion must equal approved pin ${APPROVED_PROCESSOR_VERSION}`)
  if (manifest.location !== 'asia-south1') fail('location must be asia-south1')
  if (!isSafeSegment(manifest.adjudication?.reviewerId) || manifest.adjudication.method !== 'independent_source_comparison' || manifest.adjudication.reviewerId === manifest.evaluatorRunId) fail('independent adjudicator provenance is required')
  if (!isSha256(manifest.adjudication.receiptSha256)) fail('adjudication receipt hash is required')
  if (!manifest.billing || !/^[A-Z]{3}$/.test(manifest.billing.currency)) fail('billing.currency must be an ISO-like uppercase code')
  assertFiniteNonNegative(manifest.billing.costPerBilledPage, 'billing.costPerBilledPage')
  if (manifest.billing.costPerBilledPage === 0) fail('billing.costPerBilledPage must be positive')
  if (!isSha256(manifest.billing.evidenceSha256) || manifest.billing.billedFeature !== 'enterprise_ocr_page') fail('billing feature and source evidence hash are required')
  if (manifest.billing.usdPerCurrencyUnit !== null) {
    assertFiniteNonNegative(manifest.billing.usdPerCurrencyUnit, 'billing.usdPerCurrencyUnit')
    if (manifest.billing.usdPerCurrencyUnit === 0) fail('billing.usdPerCurrencyUnit must be positive')
  }
  if (manifest.billing.currency === 'USD' && manifest.billing.usdPerCurrencyUnit !== 1) fail('USD billing conversion must equal 1')
  if (manifest.hundredPageAcquisition !== null) {
    if (manifest.hundredPageAcquisition?.measuredPages !== 100 || !isSha256(manifest.hundredPageAcquisition.evidenceSha256)) fail('100-page acquisition needs measured 100 pages and evidence hash')
    assertFiniteNonNegative(manifest.hundredPageAcquisition.elapsedMs, 'hundredPageAcquisition.elapsedMs')
  }
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
    if (!['readable', 'source_unreadable'].includes(entry.sourceDisposition)) fail(`case ${entry.caseId} has missing source disposition`)
    for (const name of ['gstin', 'reference', 'date', 'amount', 'table', 'anchor'] as const) {
      const check = entry.checks?.[name]
      const items = check?.items
      if (!Array.isArray(items) || items.length === 0) fail(`case ${entry.caseId} has incomplete ${name} item labels`)
      if (!Number.isInteger(check.adjudicatedItemCount) || check.adjudicatedItemCount < 0) fail(`case ${entry.caseId} has missing ${name} adjudicated item count`)
      const ids = new Set<string>()
      for (const check of items) {
        if (!check || !isSafeSegment(check.itemId) || ids.has(check.itemId) || !['pass', 'fail', 'unknown', 'not_applicable'].includes(check.verdict) || check.evidence !== 'adjudicated') fail(`case ${entry.caseId} has invalid ${name} item label`)
        ids.add(check.itemId)
      }
      if (items.some((check) => check.verdict === 'not_applicable') && items.length !== 1) fail(`case ${entry.caseId} ${name} non-applicability must be a single adjudicated page label`)
      if (items[0].verdict === 'not_applicable' ? check.adjudicatedItemCount !== 0 : check.adjudicatedItemCount !== items.length) fail(`case ${entry.caseId} ${name} item count does not match independent adjudication`)
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
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`
  if (value && typeof value === 'object') return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => `${JSON.stringify(key)}:${canonical(item)}`).join(',')}}`
  return JSON.stringify(value) ?? 'null'
}
function selectionSha256(manifest: BenchmarkManifest): string {
  return createHash('sha256').update(manifest.cases.map((entry) => `${entry.sourceSha256}:${entry.sourcePageNumber}`).sort().join('\n')).digest('hex')
}
async function readHashedJson(directory: string, file: string, expectedSha256: string): Promise<Record<string, unknown>> {
  if (!isSha256(expectedSha256)) fail(`${file} hash is missing`)
  const path = join(directory, 'acceptance-evidence', file)
  const details = await lstat(path)
  if (!details.isFile() || details.isSymbolicLink() || (details.mode & 0o077) !== 0) fail(`${file} must be a private regular local evidence file`)
  if (await sha256(path) !== expectedSha256) fail(`${file} evidence hash mismatch`)
  const parsed = JSON.parse(await readFile(path, 'utf8')) as unknown
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) fail(`${file} must be a JSON object`)
  return parsed as Record<string, unknown>
}

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

async function verifyAcceptanceEvidence(manifest: BenchmarkManifest, outputDirectory: string, linkage: Awaited<ReturnType<typeof verifyEvaluatorLinkage>>): Promise<{ adjudicationReceiptSha256: string; comparisonSha256: string; billingReceiptSha256: string; pricingSha256: string; hundredRunManifestSha256: string | null; hundredEventsSha256: string | null }> {
  const selection = selectionSha256(manifest)
  const adjudication = await readHashedJson(outputDirectory, 'adjudication-receipt.json', manifest.adjudication.receiptSha256)
  if (adjudication.kind !== 'independent_adjudication_receipt' || adjudication.reviewerId !== manifest.adjudication.reviewerId || adjudication.method !== manifest.adjudication.method || adjudication.evaluatorRunId !== manifest.evaluatorRunId || adjudication.evaluatorRunManifestSha256 !== linkage.authoritativeEvaluatorRunManifestSha256 || adjudication.selectionSha256 !== selection || !isSha256(adjudication.comparisonSha256)) fail('adjudication receipt does not bind evaluator run and selection')
  const comparison = await readHashedJson(outputDirectory, 'source-comparison.json', adjudication.comparisonSha256)
  const expectedCases = manifest.cases.map((entry) => ({ caseId: entry.caseId, sourceSha256: entry.sourceSha256, sourcePageNumber: entry.sourcePageNumber, categories: entry.categories, routing: entry.routing, checks: entry.checks, quality: entry.quality, sourceDisposition: entry.sourceDisposition }))
  if (comparison.kind !== 'source_comparison_labels' || comparison.reviewerId !== manifest.adjudication.reviewerId || canonical(comparison.cases) !== canonical(expectedCases)) fail('independent source-comparison artifact does not match every selected label')
  const billedPages = [...linkage.evidence.values()].reduce((sum, page) => sum + Number(page.billedPages), 0)
  const billing = await readHashedJson(outputDirectory, 'billing-receipt.json', manifest.billing.evidenceSha256)
  if (billing.kind !== 'ocr_billing_receipt' || billing.evaluatorRunManifestSha256 !== linkage.authoritativeEvaluatorRunManifestSha256 || billing.selectionSha256 !== selection || billing.billedPages !== billedPages || billing.currency !== manifest.billing.currency || billing.costPerBilledPage !== manifest.billing.costPerBilledPage || billing.usdPerCurrencyUnit !== manifest.billing.usdPerCurrencyUnit || billing.billedFeature !== manifest.billing.billedFeature || !isSha256(billing.pricingSha256)) fail('billing receipt does not match actual linked pages and declared pricing')
  const pricing = await readHashedJson(outputDirectory, 'pricing-source.json', billing.pricingSha256)
  if (pricing.kind !== 'pricing_source_capture' || pricing.processorVersion !== manifest.processorVersion || pricing.location !== manifest.location || pricing.currency !== manifest.billing.currency || pricing.costPerBilledPage !== manifest.billing.costPerBilledPage || pricing.usdPerCurrencyUnit !== manifest.billing.usdPerCurrencyUnit || pricing.billedFeature !== manifest.billing.billedFeature) fail('opened pricing source does not match billing declaration')
  let hundredEventsSha256: string | null = null
  if (manifest.hundredPageAcquisition !== null) {
    const run = await readHashedJson(outputDirectory, 'hundred-run-manifest.json', manifest.hundredPageAcquisition.evidenceSha256)
    if (run.kind !== 'bounded_hundred_page_run' || run.evaluatorRunManifestSha256 !== linkage.authoritativeEvaluatorRunManifestSha256 || run.selectionSha256 !== selection || run.processorVersion !== manifest.processorVersion || run.location !== manifest.location || !isSafeSegment(run.runId) || run.measuredPages !== 100 || !isSha256(run.sourceSha256) || !isSha256(run.eventsSha256)) fail('100-page run manifest does not bind evaluator, pin and source')
    const events = await readHashedJson(outputDirectory, 'hundred-page-events.json', run.eventsSha256)
    if (events.kind !== 'bounded_page_events' || events.runId !== run.runId || events.sourceSha256 !== run.sourceSha256 || !Array.isArray(events.pages) || events.pages.length !== 100) fail('100-page events do not match run')
    const pageNumbers = new Set<number>(); let first = Number.POSITIVE_INFINITY; let last = 0
    for (const event of events.pages as Array<Record<string, unknown>>) {
      if (!event || !Number.isInteger(event.sourcePageNumber) || Number(event.sourcePageNumber) < 1 || Number(event.sourcePageNumber) > 100 || pageNumbers.has(Number(event.sourcePageNumber)) || typeof event.startedAtMs !== 'number' || !Number.isFinite(event.startedAtMs) || event.startedAtMs < 0 || typeof event.endedAtMs !== 'number' || !Number.isFinite(event.endedAtMs) || event.endedAtMs < event.startedAtMs) fail('100-page events have missing, duplicate or malformed measurements')
      pageNumbers.add(Number(event.sourcePageNumber)); first = Math.min(first, event.startedAtMs); last = Math.max(last, event.endedAtMs)
    }
    if (last - first !== manifest.hundredPageAcquisition.elapsedMs) fail('100-page elapsed time does not match measured event span')
    hundredEventsSha256 = run.eventsSha256
  }
  return { adjudicationReceiptSha256: manifest.adjudication.receiptSha256, comparisonSha256: adjudication.comparisonSha256 as string, billingReceiptSha256: manifest.billing.evidenceSha256, pricingSha256: billing.pricingSha256 as string, hundredRunManifestSha256: manifest.hundredPageAcquisition?.evidenceSha256 ?? null, hundredEventsSha256 }
}

export async function buildReport(manifest: BenchmarkManifest, outputDirectory: string, adjudicationManifestSha256: string): Promise<Record<string, unknown>> {
  if (!isSha256(adjudicationManifestSha256)) fail('adjudicationManifestSha256 must be a SHA-256')
  validateManifest(manifest)
  const linkage = await verifyEvaluatorLinkage(manifest, outputDirectory)
  const acceptanceEvidence = await verifyAcceptanceEvidence(manifest, outputDirectory, linkage)
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
  const checkMetrics = Object.fromEntries((['gstin', 'reference', 'date', 'amount', 'table', 'anchor'] as const).map((name) => [name, metric(manifest.cases.flatMap((entry) => entry.checks[name].items))]))
  const criticalFailuresOrUnknown = Object.entries(checkMetrics).filter(([, value]) => value.failed > 0 || value.unknown > 0).map(([name]) => name)
  const missingCriticalCoverage = Object.entries(checkMetrics).filter(([, value]) => value.denominator === 0).map(([name]) => name)
  const totalBilledPages = [...linkage.evidence.values()].reduce((total, entry) => total + Number(entry.billedPages), 0)
  const totalLatencyMs = [...linkage.evidence.values()].reduce((total, entry) => total + Number(entry.elapsedMs), 0)
  const expectedNative = manifest.cases.filter((entry) => entry.routing.expectedAction === 'native').length
  const expectedOcr = manifest.cases.length - expectedNative
  const ocrCases = manifest.cases.filter((entry) => linkage.evidence.get(entry.caseId)?.observedRoute === 'ocr')
  const qualityMissing = ocrCases.filter((entry) => entry.quality.characterAccuracy === null || entry.quality.wordAccuracy === null)
  const ocrCharacter = ocrCases.map((entry) => entry.quality.characterAccuracy).filter((value): value is number => value !== null)
  const ocrWord = ocrCases.map((entry) => entry.quality.wordAccuracy).filter((value): value is number => value !== null)
  const meanCharacter = ocrCharacter.length ? ocrCharacter.reduce((sum, value) => sum + value, 0) / ocrCharacter.length : null
  const meanWord = ocrWord.length ? ocrWord.reduce((sum, value) => sum + value, 0) / ocrWord.length : null
  const usdRate = manifest.billing.usdPerCurrencyUnit
  const usdPerBilledPage = usdRate === null ? null : manifest.billing.costPerBilledPage * usdRate
  const hundredPageMs = manifest.hundredPageAcquisition?.elapsedMs ?? null
  const pages = manifest.cases.map((entry) => {
    const observed = linkage.evidence.get(entry.caseId)?.observedRoute
    const critical = Object.values(entry.checks).some((check) => check.items.some((item) => item.verdict === 'fail' || item.verdict === 'unknown'))
    const poorOcr = observed === 'ocr' && (entry.quality.characterAccuracy === null || entry.quality.wordAccuracy === null || entry.quality.characterAccuracy < 0.98 || entry.quality.wordAccuracy < 0.95)
    const disposition = entry.sourceDisposition === 'source_unreadable' ? 'source_unreadable' : observed !== entry.routing.expectedAction || poorOcr ? 'reacquire' : critical ? 'metadata_only' : 'body_eligible_after_search_gates'
    const fieldReviewClasses = (['gstin', 'reference', 'date', 'amount'] as const).filter((name) => entry.checks[name].items.some((item) => item.verdict === 'fail' || item.verdict === 'unknown'))
    return { caseId: entry.caseId, sourcePageKeySha256: createHash('sha256').update(`${entry.sourceSha256}:${entry.sourcePageNumber}`).digest('hex'), disposition, fieldReviewClasses }
  })
  const categoryBreakdown = Object.fromEntries(REQUIRED_CATEGORIES.map((category) => {
    const entries = ocrCases.filter((entry) => entry.categories.includes(category))
    const chars = entries.map((entry) => entry.quality.characterAccuracy).filter((value): value is number => value !== null)
    const words = entries.map((entry) => entry.quality.wordAccuracy).filter((value): value is number => value !== null)
    return [category, { pages: entries.length, characterMean: chars.length ? chars.reduce((a, b) => a + b, 0) / chars.length : null, wordMean: words.length ? words.reduce((a, b) => a + b, 0) / words.length : null, missingCharacterLabels: entries.length - chars.length, missingWordLabels: entries.length - words.length, missingLabels: entries.filter((entry) => entry.quality.characterAccuracy === null || entry.quality.wordAccuracy === null).length }]
  }))
  const missingOcrCategories = REQUIRED_CATEGORIES.filter((category) => category !== 'native_english' && ocrCases.every((entry) => !entry.categories.includes(category)))
  const failedThresholds = [
    ...(criticalFailuresOrUnknown.length || missingCriticalCoverage.length ? ['critical_exactness'] : []),
    ...(expectedNative === 0 || expectedOcr === 0 || routingRecallDenominator === 0 || routingPrecisionDenominator === 0 || routing.falseNegative > 0 || routing.truePositive / routingPrecisionDenominator < 0.9 ? ['routing'] : []),
    ...(qualityMissing.length || missingOcrCategories.length || meanCharacter === null || meanCharacter + 1e-12 < 0.98 || meanWord === null || meanWord + 1e-12 < 0.95 ? ['ocr_quality_or_category_coverage'] : []),
    ...(totalLatencyMs / manifest.cases.length > 10000 || hundredPageMs === null || hundredPageMs > 1200000 ? ['latency'] : []),
    ...(usdPerBilledPage === null || usdPerBilledPage > 0.01 || usdPerBilledPage * 100 > 1 ? ['ocr_cost_usd'] : []),
  ]
  return {
    schemaVersion: 2, adjudicationManifestSha256, benchmarkRunId: manifest.benchmarkRunId, adjudication: { reviewerId: manifest.adjudication.reviewerId, method: manifest.adjudication.method }, evaluatorRun: { generatedId: manifest.evaluatorRunId, provenance: 'matched_to_evaluator_run_manifest' },
    processor: { version: manifest.processorVersion, location: manifest.location },
    evaluatedPages: manifest.cases.length, categories: Object.fromEntries(REQUIRED_CATEGORIES.map((category) => [category, manifest.cases.filter((entry) => entry.categories.includes(category)).length])),
    routing: { ...routing, precisionDenominator: routingPrecisionDenominator, recallDenominator: routingRecallDenominator, precision: routingPrecisionDenominator ? routing.truePositive / routingPrecisionDenominator : null, recall: routingRecallDenominator ? routing.truePositive / routingRecallDenominator : null },
    checks: checkMetrics,
    quality: { characterAccuracy: meanCharacter, characterUnknown: qualityMissing.length, wordAccuracy: meanWord, wordUnknown: qualityMissing.length, categoryBreakdown },
    latency: { totalMs: totalLatencyMs, averageMs: totalLatencyMs / manifest.cases.length, hundredPageMs, hundredPageEvidenceSha256: manifest.hundredPageAcquisition?.evidenceSha256 ?? null },
    billing: { currency: manifest.billing.currency, billedPages: totalBilledPages, costPerBilledPage: manifest.billing.costPerBilledPage, usdPerCurrencyUnit: usdRate, usdPerBilledPage, fullyOcrHundredPageUsd: usdPerBilledPage === null ? null : usdPerBilledPage * 100, evidenceSha256: manifest.billing.evidenceSha256 },
    pages: pages.map((page) => ({ ...page, indexingBlockedByBenchmarkGate: failedThresholds.length > 0, bodyIndexingEligibility: failedThresholds.length > 0 ? 'not_indexable_pending_global_gate' : page.disposition === 'body_eligible_after_search_gates' ? 'not_indexable_pending_external_acceptance_and_search_gates' : 'not_indexable_page_disposition' })),
    outputLinkage: { authoritativeEvaluatorRunManifestSha256: linkage.authoritativeEvaluatorRunManifestSha256, outputHashes: linkage.outputHashes },
    acceptanceEvidence,
    gate: { status: failedThresholds.length ? 'failed' : 'local_evidence_linked_not_provider_approved', providerApproval: 'not_evaluated', externalEvidenceAuthenticity: 'not_verified', failedThresholds, criticalFailuresOrUnknown, missingCriticalCoverage, qualityMissingCount: qualityMissing.length, missingOcrCategories },
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2); const manifestIndex = args.indexOf('--manifest'); const outputIndex = args.indexOf('--evaluator-output'); const reportIndex = args.indexOf('--report')
  if (args.includes('--help')) {
    if (args.length !== 1) fail('--help cannot be combined with other options')
    console.log('Usage: npx tsx scripts/document-ai/ocr-acquisition-benchmark.ts --manifest <local-labelled-manifest.json> --evaluator-output <existing-evaluator-output-dir> --report <content-safe-report.json>')
    console.log('Requires private regular acceptance-evidence/{adjudication-receipt,source-comparison,billing-receipt,pricing-source,hundred-run-manifest,hundred-page-events}.json files under evaluator output; local linkage is not provider approval.')
    return
  }
  const input = args[manifestIndex + 1]; const output = args[outputIndex + 1]; const report = args[reportIndex + 1]
  if (!input || !output || !report || args.length !== 6) fail('supply exactly --manifest, --evaluator-output, and --report')
  const manifestBytes = await readFile(resolve(input))
  const result = await buildReport(JSON.parse(manifestBytes.toString('utf8')) as BenchmarkManifest, resolve(output), createHash('sha256').update(manifestBytes).digest('hex'))
  const reportPath = resolve(report)
  try { await chmod(reportPath, 0o600) } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error
  }
  await writeFile(reportPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 })
  console.log(`OCR acquisition benchmark ${result.gate instanceof Object ? (result.gate as { status: string }).status : 'completed'}: ${resolve(report)}`)
  if ((result.gate as { status: string }).status === 'failed') process.exitCode = 2
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)) main().catch((error: unknown) => { console.error(error instanceof Error ? error.message : 'OCR acquisition benchmark failed'); process.exitCode = 1 })
