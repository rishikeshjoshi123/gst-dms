import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises'
import test from 'node:test'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { APPROVED_PROCESSOR_VERSION, buildReport as buildReportUnchecked, type BenchmarkManifest, validateManifest } from './ocr-acquisition-benchmark'

const adjudicationHash = createHash('sha256').update('test-adjudication').digest('hex')
const digest = (value: string) => createHash('sha256').update(value).digest('hex')
async function writeAcceptanceEvidence(manifest: BenchmarkManifest, output: string): Promise<void> {
  const directory = join(output, 'acceptance-evidence'); await mkdir(directory, { recursive: true })
  const write = async (name: string, value: unknown) => { const bytes = JSON.stringify(value); await writeFile(join(directory, name), bytes, { mode: 0o600 }); return digest(bytes) }
  const runManifestSha256 = digest(await readFile(join(output, 'run-manifest.json'), 'utf8'))
  const selectionSha256 = digest(manifest.cases.map((entry) => `${entry.sourceSha256}:${entry.sourcePageNumber}`).sort().join('\n'))
  const cases = manifest.cases.map((entry) => ({ caseId: entry.caseId, sourceSha256: entry.sourceSha256, sourcePageNumber: entry.sourcePageNumber, categories: entry.categories, routing: entry.routing, checks: entry.checks, quality: entry.quality, sourceDisposition: entry.sourceDisposition }))
  const comparisonSha256 = await write('source-comparison.json', { kind: 'source_comparison_labels', reviewerId: manifest.adjudication.reviewerId, cases })
  manifest.adjudication.receiptSha256 = await write('adjudication-receipt.json', { kind: 'independent_adjudication_receipt', reviewerId: manifest.adjudication.reviewerId, method: manifest.adjudication.method, evaluatorRunId: manifest.evaluatorRunId, evaluatorRunManifestSha256: runManifestSha256, selectionSha256, comparisonSha256 })
  const billedPages = (await Promise.all(manifest.cases.map(async (entry) => JSON.parse(await readFile(join(output, entry.evaluatorDocumentDirectory, 'pages.summary.json'), 'utf8'))[0].billedPages as number))).reduce((a, b) => a + b, 0)
  const pricingSha256 = await write('pricing-source.json', { kind: 'pricing_source_capture', processorVersion: manifest.processorVersion, location: manifest.location, currency: manifest.billing.currency, costPerBilledPage: manifest.billing.costPerBilledPage, usdPerCurrencyUnit: manifest.billing.usdPerCurrencyUnit, billedFeature: manifest.billing.billedFeature })
  manifest.billing.evidenceSha256 = await write('billing-receipt.json', { kind: 'ocr_billing_receipt', evaluatorRunManifestSha256: runManifestSha256, selectionSha256, billedPages, currency: manifest.billing.currency, costPerBilledPage: manifest.billing.costPerBilledPage, usdPerCurrencyUnit: manifest.billing.usdPerCurrencyUnit, billedFeature: manifest.billing.billedFeature, pricingSha256 })
  if (manifest.hundredPageAcquisition !== null) {
    const elapsed = manifest.hundredPageAcquisition.elapsedMs
    const sourceSha256 = digest('hundred-page-synthetic-source')
    const eventsSha256 = await write('hundred-page-events.json', { kind: 'bounded_page_events', runId: 'hundred-run-1', sourceSha256, pages: Array.from({ length: 100 }, (_, index) => ({ sourcePageNumber: index + 1, startedAtMs: Math.floor(index * elapsed / 100), endedAtMs: Math.floor((index + 1) * elapsed / 100) })) })
    manifest.hundredPageAcquisition.evidenceSha256 = await write('hundred-run-manifest.json', { kind: 'bounded_hundred_page_run', runId: 'hundred-run-1', evaluatorRunManifestSha256: runManifestSha256, selectionSha256, processorVersion: manifest.processorVersion, location: manifest.location, measuredPages: 100, sourceSha256, eventsSha256 })
  }
}
const buildReport = async (manifest: BenchmarkManifest, output: string) => { await writeAcceptanceEvidence(manifest, output); return buildReportUnchecked(manifest, output, adjudicationHash) }

function fixture(): BenchmarkManifest {
  const categories = ['native_english', 'scanned_english', 'hindi', 'mixed_language', 'handwriting', 'stamps', 'tables', 'rotation', 'poor_scan'] as const
  const evidenceSha256 = createHash('sha256').update('synthetic-evidence').digest('hex')
  return { schemaVersion: 2, benchmarkRunId: 'benchmark-1', evaluatorRunId: 'evaluator-1', processorVersion: APPROVED_PROCESSOR_VERSION, location: 'asia-south1', adjudication: { reviewerId: 'independent-reviewer', method: 'independent_source_comparison', receiptSha256: evidenceSha256 }, billing: { currency: 'USD', costPerBilledPage: 0.005, usdPerCurrencyUnit: 1, evidenceSha256, billedFeature: 'enterprise_ocr_page' }, hundredPageAcquisition: { measuredPages: 100, elapsedMs: 1000000, evidenceSha256 }, cases: Array.from({ length: 60 }, (_, index) => { const sourceSha256 = createHash('sha256').update(`fixture-source-${index + 1}`).digest('hex'); const label = () => ({ adjudicatedItemCount: 1, items: [{ itemId: 'item-1', verdict: 'pass' as const, evidence: 'adjudicated' as const }] }); return { caseId: `case-${index + 1}`, sourceSha256, sourcePageNumber: 1, evaluatorDocumentDirectory: `doc-${index + 1}-${sourceSha256.slice(0, 12)}`, categories: [categories[index % categories.length]], routing: { expectedAction: index % categories.length === 0 ? 'native' : 'ocr', evidence: 'adjudicated' }, checks: { gstin: label(), reference: label(), date: label(), amount: label(), table: label(), anchor: label() }, quality: { characterAccuracy: 1, wordAccuracy: 1, evidence: 'adjudicated' }, sourceDisposition: 'readable' } }) }
}

async function evaluatorOutput(manifest: BenchmarkManifest): Promise<string> {
  const output = await mkdtemp(join(tmpdir(), 'ocr-benchmark-'))
  await writeFile(join(output, 'run-manifest.json'), JSON.stringify({ schemaVersion: 2, runId: manifest.evaluatorRunId, mode: 'page', location: manifest.location, processorVersion: manifest.processorVersion, files: manifest.cases.map((entry) => ({ sourceFileName: `doc-${entry.caseId.slice(5)}.pdf`, sourceSha256: entry.sourceSha256, sourcePageCount: 1, selectedPages: [1], outputDirectory: entry.evaluatorDocumentDirectory })) }))
  for (const entry of manifest.cases) { const directory = join(output, entry.evaluatorDocumentDirectory); await mkdir(directory); const raw = JSON.stringify({ document: { text: 'x', pages: [{ pageNumber: 1, tokens: [{ layout: {} }] }] } }); const normalizedRaw = `${JSON.stringify(JSON.parse(raw), null, 2)}\n`; const hash = createHash('sha256').update(normalizedRaw).digest('hex'); if (entry.routing.expectedAction === 'ocr') await writeFile(join(directory, 'page-0001.raw.json'), normalizedRaw); await writeFile(join(directory, 'pages.summary.json'), JSON.stringify([{ sourcePageNumber: 1, providerPageNumber: entry.routing.expectedAction === 'ocr' ? 1 : 0, observedRoute: entry.routing.expectedAction, elapsedMs: 10, billedPages: entry.routing.expectedAction === 'ocr' ? 1 : 0, rawSha256: entry.routing.expectedAction === 'ocr' ? hash : null, nativeQuality: { accepted: entry.routing.expectedAction === 'native', reasons: [] }, textLength: 1, tokenCount: 1 }])) }
  return output
}

test('rejects a duplicate selected source page, including copied PDFs', () => { const value = fixture(); value.cases[1].sourceSha256 = value.cases[0].sourceSha256; assert.throws(() => validateManifest(value), /duplicate source page/) })
test('rejects missing category and mutable processor alias', () => { const value = fixture(); value.cases.forEach((entry) => { entry.categories = ['native_english'] }); assert.throws(() => validateManifest(value), /missing required category/); value.processorVersion = 'stable'; assert.throws(() => validateManifest(value), /approved pin/) })
test('reports unknown labels separately and fails closed', async () => { const value = fixture(); value.cases[0].checks.date.items[0].verdict = 'unknown'; const report = await buildReport(value, await evaluatorOutput(value)); const checks = report.checks as Record<string, { unknown: number }>; assert.equal(checks.date.unknown, 1); assert.equal((report.gate as { status: string }).status, 'failed') })
test('not applicable is separate from an unknown and does not fail an otherwise covered check', async () => { const value = fixture(); value.cases[0].checks.table.items[0].verdict = 'not_applicable'; value.cases[0].checks.table.adjudicatedItemCount = 0; const report = await buildReport(value, await evaluatorOutput(value)); const table = (report.checks as Record<string, { denominator: number; notApplicable: number; unknown: number }>).table; assert.deepEqual(table, { correct: 59, failed: 0, unknown: 0, notApplicable: 1, denominator: 59, accuracy: 1 }); assert.equal((report.gate as { status: string }).status, 'local_evidence_linked_not_provider_approved') })
test('missing applicable critical-fact coverage fails closed', async () => { const value = fixture(); value.cases.forEach((entry) => { entry.checks.amount.items[0].verdict = 'not_applicable'; entry.checks.amount.adjudicatedItemCount = 0 }); const report = await buildReport(value, await evaluatorOutput(value)); assert.deepEqual((report.gate as { missingCriticalCoverage: string[] }).missingCriticalCoverage, ['amount']); assert.equal((report.gate as { status: string }).status, 'failed') })
test('critical handwritten date failure cannot be hidden by aggregates', async () => { const value = fixture(); value.cases[4].checks.date.items[0].verdict = 'fail'; const report = await buildReport(value, await evaluatorOutput(value)); assert.equal((report.checks as Record<string, { failed: number }>).date.failed, 1); assert.equal((report.gate as { status: string }).status, 'failed') })
test('allows one output directory for multiple pages of one source but rejects source collisions', () => { const valid = fixture(); valid.cases[1].sourceSha256 = valid.cases[0].sourceSha256; valid.cases[1].sourcePageNumber = 2; valid.cases[1].evaluatorDocumentDirectory = valid.cases[0].evaluatorDocumentDirectory; assert.doesNotThrow(() => validateManifest(valid)); const collision = fixture(); collision.cases[1].evaluatorDocumentDirectory = collision.cases[0].evaluatorDocumentDirectory; assert.throws(() => validateManifest(collision), /more than one source SHA-256/) })
test('safe report excludes labels, output paths, and provider content', async () => { const value = fixture(); const result = await buildReport(value, await evaluatorOutput(value)); const report = JSON.stringify(result); assert.doesNotMatch(report, /evaluatorDocumentDirectory|sourceSha256|raw\.json|\/tmp\//); assert.match(report, /authoritativeEvaluatorRunManifestSha256/); assert.deepEqual(result.evaluatorRun, { generatedId: 'evaluator-1', provenance: 'matched_to_evaluator_run_manifest' }); assert.equal((result.pages as Array<{ bodyIndexingEligibility: string }>)[0].bodyIndexingEligibility, 'not_indexable_pending_external_acceptance_and_search_gates') })
test('fails when evaluator linkage is forged or missing', async () => { const value = fixture(); const output = await evaluatorOutput(value); value.cases[0].sourcePageNumber = 2; await assert.rejects(() => buildReport(value, output), /exactly match/) })
test('rejects evaluator run and mode linkage mismatches', async () => { const value = fixture(); const output = await evaluatorOutput(value); const runPath = join(output, 'run-manifest.json'); const run = JSON.parse(await (await import('node:fs/promises')).readFile(runPath, 'utf8')); run.runId = 'other-run'; await writeFile(runPath, JSON.stringify(run)); await assert.rejects(() => buildReport(value, output), /run ID/); run.runId = value.evaluatorRunId; run.mode = 'whole'; await writeFile(runPath, JSON.stringify(run)); await assert.rejects(() => buildReport(value, output), /page-mode/) })
test('rejects empty extra evaluator records and unselected summary pages', async () => {
  const value = fixture(); const output = await evaluatorOutput(value); const runPath = join(output, 'run-manifest.json'); const run = JSON.parse(await (await import('node:fs/promises')).readFile(runPath, 'utf8'))
  run.files.push({ sourceSha256: createHash('sha256').update('extra').digest('hex'), sourcePageCount: 1, selectedPages: [], outputDirectory: 'extra-000000000000' })
  await writeFile(runPath, JSON.stringify(run)); await assert.rejects(() => buildReport(value, output), /empty source selection/)
  run.files.pop(); await writeFile(runPath, JSON.stringify(run))
  const summaryPath = join(output, value.cases[0].evaluatorDocumentDirectory, 'pages.summary.json'); const summary = JSON.parse(await (await import('node:fs/promises')).readFile(summaryPath, 'utf8')); summary.push({ ...summary[0], sourcePageNumber: 2, billedPages: 999, elapsedMs: 999999 })
  await writeFile(summaryPath, JSON.stringify(summary)); await assert.rejects(() => buildReport(value, output), /summary does not exactly cover selected pages/)
})
test('rejects empty or wrong-page provider raw output and raw-hash tampering', async () => {
  const value = fixture(); const output = await evaluatorOutput(value); const rawPath = join(output, value.cases[1].evaluatorDocumentDirectory, 'page-0001.raw.json')
  await writeFile(rawPath, '{}'); await assert.rejects(() => buildReport(value, output), /raw output hash mismatch/)
  const raw = `${JSON.stringify({ document: { text: 'x', pages: [{ pageNumber: 2, tokens: [{}] }] } }, null, 2)}\n`; const hash = createHash('sha256').update(raw).digest('hex'); await writeFile(rawPath, raw)
  const summaryPath = join(output, value.cases[1].evaluatorDocumentDirectory, 'pages.summary.json'); const summary = JSON.parse(await (await import('node:fs/promises')).readFile(summaryPath, 'utf8')); summary[0].rawSha256 = hash; await writeFile(summaryPath, JSON.stringify(summary)); await assert.rejects(() => buildReport(value, output), /not a selected-page OCR result/)
})
test('missing expected route or OCR quality fails closed', async () => { const value = fixture(); value.cases.forEach((entry) => { entry.routing.expectedAction = 'ocr' }); let report = await buildReport(value, await evaluatorOutput(value)); assert.equal((report.gate as { status: string }).status, 'failed'); const quality = fixture(); quality.cases[1].quality.characterAccuracy = null; report = await buildReport(quality, await evaluatorOutput(quality)); assert.equal((report.gate as { qualityMissingCount: number }).qualityMissingCount, 1) })
test('schema, independent labels, malformed evidence and empty denominators fail closed', async () => {
  const value = fixture(); const legacy = { ...value, schemaVersion: 1 } as unknown as BenchmarkManifest
  assert.throws(() => validateManifest(legacy), /legacy structural/)
  value.adjudication.reviewerId = value.evaluatorRunId; assert.throws(() => validateManifest(value), /independent adjudicator/)
  value.adjudication.reviewerId = 'reviewer'; value.cases[0].checks.table.items = []
  assert.throws(() => validateManifest(value), /incomplete table/)
  value.cases[0].checks.table.items = [{ itemId: 'one', verdict: 'not_applicable', evidence: 'adjudicated' }, { itemId: 'two', verdict: 'pass', evidence: 'adjudicated' }]
  assert.throws(() => validateManifest(value), /non-applicability/)
  value.cases[0].checks.table.items = [{ itemId: 'one', verdict: 'pass', evidence: 'adjudicated' }, { itemId: 'one', verdict: 'pass', evidence: 'adjudicated' }]
  assert.throws(() => validateManifest(value), /invalid table item/)
  value.cases[0].checks.table.items = [{ itemId: 'one', verdict: 'pass', evidence: 'adjudicated' }]
  value.cases[0].checks.table.adjudicatedItemCount = 2
  assert.throws(() => validateManifest(value), /item count does not match/)
  value.cases[0].checks.table.adjudicatedItemCount = 1
  value.cases.forEach((entry) => { entry.checks.anchor.items[0].verdict = 'not_applicable'; entry.checks.anchor.adjudicatedItemCount = 0 })
  const report = await buildReport(value, await evaluatorOutput(value))
  assert.equal((report.routing as { recallDenominator: number }).recallDenominator > 0, true)
  assert.deepEqual((report.gate as { missingCriticalCoverage: string[] }).missingCriticalCoverage, ['anchor'])
})
test('routing requires exact recall and at least 90 percent precision', async () => {
  const missed = fixture(); const missedOutput = await evaluatorOutput(missed); missed.cases[0].routing.expectedAction = 'ocr'
  let report = await buildReport(missed, missedOutput)
  assert.equal((report.routing as { falseNegative: number; recall: number }).falseNegative, 1)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('routing'))
  const falseOcr = fixture(); const falseOcrOutput = await evaluatorOutput(falseOcr)
  falseOcr.cases.filter((entry) => entry.routing.expectedAction === 'ocr').slice(0, 6).forEach((entry) => { entry.routing.expectedAction = 'native' })
  report = await buildReport(falseOcr, falseOcrOutput)
  assert.ok((report.routing as { precision: number }).precision < 0.9)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('routing'))
})
test('all numeric thresholds accept their exact inclusive boundaries', async () => {
  const value = fixture()
  value.cases.forEach((entry) => { if (entry.routing.expectedAction === 'ocr') { entry.quality.characterAccuracy = 0.98; entry.quality.wordAccuracy = 0.95 } })
  value.billing.costPerBilledPage = 0.01
  value.hundredPageAcquisition = { measuredPages: 100, elapsedMs: 1200000, evidenceSha256: value.billing.evidenceSha256 }
  const output = await evaluatorOutput(value)
  for (const entry of value.cases) {
    const path = join(output, entry.evaluatorDocumentDirectory, 'pages.summary.json')
    const page = JSON.parse(await readFile(path, 'utf8')); page[0].elapsedMs = 10000; await writeFile(path, JSON.stringify(page))
  }
  const report = await buildReport(value, output)
  assert.equal((report.gate as { status: string }).status, 'local_evidence_linked_not_provider_approved')
  assert.equal((report.latency as { averageMs: number }).averageMs, 10000)
  assert.equal((report.billing as { fullyOcrHundredPageUsd: number }).fullyOcrHundredPageUsd, 1)
})
test('mean OCR accuracy thresholds, missing labels and category detail are enforced', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  const ocr = value.cases.filter((entry) => entry.routing.expectedAction === 'ocr')
  ocr.slice(0, 2).forEach((entry) => { entry.quality.characterAccuracy = 0 })
  ocr.slice(0, 3).forEach((entry) => { entry.quality.wordAccuracy = 0 })
  const report = await buildReport(value, output)
  assert.ok((report.quality as { characterAccuracy: number; wordAccuracy: number }).characterAccuracy < 0.98)
  assert.ok((report.quality as { characterAccuracy: number; wordAccuracy: number }).wordAccuracy < 0.95)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('ocr_quality_or_category_coverage'))
  assert.ok((report.quality as { categoryBreakdown: Record<string, unknown> }).categoryBreakdown.hindi)
  ocr[0].quality.characterAccuracy = null; assert.equal((await buildReport(value, output).then((result) => result.gate as { qualityMissingCount: number })).qualityMissingCount, 1)
})
test('latency and hundred-page bound are independent hard gates', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  const summaryPath = join(output, value.cases[0].evaluatorDocumentDirectory, 'pages.summary.json')
  const summary = JSON.parse(await readFile(summaryPath, 'utf8')); summary[0].elapsedMs = 600001; await writeFile(summaryPath, JSON.stringify(summary))
  let report = await buildReport(value, output); assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('latency'))
  const normal = fixture(); const normalOutput = await evaluatorOutput(normal)
  normal.hundredPageAcquisition = null; report = await buildReport(normal, normalOutput)
  assert.equal((report.latency as { hundredPageMs: null }).hundredPageMs, null)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('latency'))
  normal.hundredPageAcquisition = { measuredPages: 100, elapsedMs: 1200001, evidenceSha256: normal.billing.evidenceSha256 }
  report = await buildReport(normal, normalOutput); assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('latency'))
})
test('USD OCR ceiling and missing conversion evidence fail without invented FX', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  value.billing.costPerBilledPage = 0.010001
  let report = await buildReport(value, output)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('ocr_cost_usd'))
  value.billing.currency = 'INR'; value.billing.usdPerCurrencyUnit = null
  report = await buildReport(value, output)
  assert.equal((report.billing as { usdPerBilledPage: null }).usdPerBilledPage, null)
  assert.ok((report.gate as { failedThresholds: string[] }).failedThresholds.includes('ocr_cost_usd'))
})
test('material cells and anchors are item-exact; field correction cannot certify body', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  value.cases[1].checks.table.items.push({ itemId: 'cell-2', verdict: 'fail', evidence: 'adjudicated' })
  value.cases[1].checks.table.adjudicatedItemCount = 2
  value.cases[2].checks.anchor.items[0].verdict = 'unknown'
  value.cases[3].sourceDisposition = 'source_unreadable'
  value.cases[4].quality.characterAccuracy = 0.5
  const report = await buildReport(value, output)
  const pages = report.pages as Array<{ caseId: string; disposition: string }>
  assert.equal(pages[1].disposition, 'metadata_only')
  assert.equal(pages[2].disposition, 'metadata_only')
  assert.equal(pages[3].disposition, 'source_unreadable')
  assert.equal(pages[4].disposition, 'reacquire')
  assert.equal((report.checks as Record<string, { failed: number }>).table.failed, 1)
})
test('opened evidence rejects fabricated hashes, mismatched run/selection and altered source labels', async () => {
  const value = fixture(); const output = await evaluatorOutput(value); await writeAcceptanceEvidence(value, output)
  const direct = () => buildReportUnchecked(value, output, adjudicationHash)
  const originalAdjudicationHash = value.adjudication.receiptSha256
  value.adjudication.receiptSha256 = digest('fabricated'); await assert.rejects(direct, /adjudication-receipt.json evidence hash mismatch/)
  value.adjudication.receiptSha256 = originalAdjudicationHash
  const directory = join(output, 'acceptance-evidence'); const receiptPath = join(directory, 'adjudication-receipt.json')
  const { chmod } = await import('node:fs/promises'); await chmod(receiptPath, 0o644)
  await assert.rejects(direct, /private regular local evidence file/); await chmod(receiptPath, 0o600)
  const receipt = JSON.parse(await readFile(receiptPath, 'utf8'))
  receipt.evaluatorRunManifestSha256 = digest('wrong-run'); await writeFile(receiptPath, JSON.stringify(receipt)); value.adjudication.receiptSha256 = digest(JSON.stringify(receipt))
  await assert.rejects(direct, /does not bind evaluator run and selection/)
  receipt.evaluatorRunManifestSha256 = digest(await readFile(join(output, 'run-manifest.json'), 'utf8'))
  receipt.selectionSha256 = digest('wrong-selection'); await writeFile(receiptPath, JSON.stringify(receipt)); value.adjudication.receiptSha256 = digest(JSON.stringify(receipt))
  await assert.rejects(direct, /does not bind evaluator run and selection/)
  await writeAcceptanceEvidence(value, output)
  const comparisonPath = join(directory, 'source-comparison.json'); const comparison = JSON.parse(await readFile(comparisonPath, 'utf8'))
  comparison.cases[0].checks.date.items[0].verdict = 'fail'; await writeFile(comparisonPath, JSON.stringify(comparison))
  await assert.rejects(direct, /source-comparison.json evidence hash mismatch/)
})
test('billing and measured hundred-page source cannot be replaced by matching self-asserted manifest hashes', async () => {
  const value = fixture(); const output = await evaluatorOutput(value); await writeAcceptanceEvidence(value, output)
  const direct = () => buildReportUnchecked(value, output, adjudicationHash)
  const directory = join(output, 'acceptance-evidence')
  const billingPath = join(directory, 'billing-receipt.json'); const billing = JSON.parse(await readFile(billingPath, 'utf8'))
  billing.billedPages += 1; await writeFile(billingPath, JSON.stringify(billing)); value.billing.evidenceSha256 = digest(JSON.stringify(billing))
  await assert.rejects(direct, /billing receipt does not match actual linked pages/)
  await writeAcceptanceEvidence(value, output)
  const pricingPath = join(directory, 'pricing-source.json'); const pricing = JSON.parse(await readFile(pricingPath, 'utf8'))
  pricing.costPerBilledPage = 0.0001; await writeFile(pricingPath, JSON.stringify(pricing))
  await assert.rejects(direct, /pricing-source.json evidence hash mismatch/)
  await writeAcceptanceEvidence(value, output)
  const eventsPath = join(directory, 'hundred-page-events.json'); const events = JSON.parse(await readFile(eventsPath, 'utf8'))
  events.pages[99].endedAtMs += 1; await writeFile(eventsPath, JSON.stringify(events))
  await assert.rejects(direct, /hundred-page-events.json evidence hash mismatch/)
  const eventsSha256 = digest(JSON.stringify(events))
  const hundredPath = join(directory, 'hundred-run-manifest.json'); const hundred = JSON.parse(await readFile(hundredPath, 'utf8'))
  hundred.eventsSha256 = eventsSha256; await writeFile(hundredPath, JSON.stringify(hundred)); value.hundredPageAcquisition!.evidenceSha256 = digest(JSON.stringify(hundred))
  await assert.rejects(direct, /elapsed time does not match measured event span/)
})
test('global operational failure blocks otherwise accurate body and field Review remains separate', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  value.billing.costPerBilledPage = 0.010001
  value.cases[1].checks.date.items[0].verdict = 'fail'
  const report = await buildReport(value, output)
  const pages = report.pages as Array<{ disposition: string; fieldReviewClasses: string[]; indexingBlockedByBenchmarkGate: boolean; bodyIndexingEligibility: string }>
  assert.equal(pages[0].disposition, 'body_eligible_after_search_gates')
  assert.equal(pages[0].bodyIndexingEligibility, 'not_indexable_pending_global_gate')
  assert.equal(pages[0].indexingBlockedByBenchmarkGate, true)
  assert.deepEqual(pages[1].fieldReviewClasses, ['date'])
  assert.equal(pages[1].disposition, 'metadata_only')
  assert.equal((report.gate as { providerApproval: string }).providerApproval, 'not_evaluated')
})
test('category missing-label count is union of split character and word gaps', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  value.cases[1].quality.characterAccuracy = null
  value.cases[10].quality.wordAccuracy = null
  const result = await buildReport(value, output)
  const scanned = (result.quality as { categoryBreakdown: Record<string, { missingLabels: number; missingCharacterLabels: number; missingWordLabels: number }> }).categoryBreakdown.scanned_english
  assert.deepEqual({ missingLabels: scanned.missingLabels, character: scanned.missingCharacterLabels, word: scanned.missingWordLabels }, { missingLabels: 2, character: 1, word: 1 })
})
test('benchmark and evaluator CLIs have strict help and option exits', () => {
  const run = (script: string, args: string[]) => spawnSync(process.execPath, ['--import', 'tsx', script, ...args], { cwd: process.cwd(), encoding: 'utf8' }).status
  assert.equal(run('scripts/document-ai/ocr-acquisition-benchmark.ts', ['--help']), 0)
  assert.notEqual(run('scripts/document-ai/ocr-acquisition-benchmark.ts', ['--bogus', 'x']), 0)
  assert.equal(run('scripts/document-ai/evaluate-ocr.ts', ['--help']), 0)
  assert.notEqual(run('scripts/document-ai/evaluate-ocr.ts', ['--input', 'x', '--input', 'x']), 0)
  assert.notEqual(run('scripts/document-ai/evaluate-ocr.ts', ['--unknown', 'x']), 0)
})
test('synthetic CLI dry run writes private deterministic report and exits nonzero on failure', async () => {
  const value = fixture(); const output = await evaluatorOutput(value)
  const local = await mkdtemp(join(tmpdir(), 'ocr-benchmark-cli-'))
  const manifestPath = join(local, 'adjudication.json'); const reportPath = join(local, 'report.json')
  const execute = () => spawnSync(process.execPath, ['--import', 'tsx', 'scripts/document-ai/ocr-acquisition-benchmark.ts', '--manifest', manifestPath, '--evaluator-output', output, '--report', reportPath], { cwd: process.cwd(), encoding: 'utf8' })
  await writeAcceptanceEvidence(value, output); await writeFile(manifestPath, JSON.stringify(value), { mode: 0o600 })
  assert.equal(execute().status, 0)
  const first = await readFile(reportPath, 'utf8'); assert.equal((await stat(reportPath)).mode & 0o777, 0o600)
  await import('node:fs/promises').then(({ chmod }) => chmod(reportPath, 0o644))
  assert.equal(execute().status, 0); assert.equal(await readFile(reportPath, 'utf8'), first)
  assert.equal((await stat(reportPath)).mode & 0o777, 0o600)
  value.billing.usdPerCurrencyUnit = null; value.billing.currency = 'INR'; await writeAcceptanceEvidence(value, output); await writeFile(manifestPath, JSON.stringify(value), { mode: 0o600 })
  assert.equal(execute().status, 2)
  assert.equal((JSON.parse(await readFile(reportPath, 'utf8')).gate as { status: string }).status, 'failed')
})
