import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { spawnSync } from 'node:child_process'
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises'
import test from 'node:test'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { APPROVED_PROCESSOR_VERSION, buildReport as buildReportUnchecked, type BenchmarkManifest, validateManifest } from './ocr-acquisition-benchmark'

const adjudicationHash = createHash('sha256').update('test-adjudication').digest('hex')
const buildReport = (manifest: BenchmarkManifest, output: string) => buildReportUnchecked(manifest, output, adjudicationHash)

function fixture(): BenchmarkManifest {
  const categories = ['native_english', 'scanned_english', 'hindi', 'mixed_language', 'handwriting', 'stamps', 'tables', 'rotation', 'poor_scan'] as const
  return { schemaVersion: 1, benchmarkRunId: 'benchmark-1', evaluatorRunId: 'evaluator-1', processorVersion: APPROVED_PROCESSOR_VERSION, location: 'asia-south1', billing: { currency: 'INR', costPerBilledPage: 1 }, cases: Array.from({ length: 60 }, (_, index) => { const sourceSha256 = createHash('sha256').update(`fixture-source-${index + 1}`).digest('hex'); return { caseId: `case-${index + 1}`, sourceSha256, sourcePageNumber: 1, evaluatorDocumentDirectory: `doc-${index + 1}-${sourceSha256.slice(0, 12)}`, categories: [categories[index % categories.length]], routing: { expectedAction: index % 2 ? 'ocr' : 'native', evidence: 'adjudicated' }, checks: { gstin: { verdict: 'pass', evidence: 'adjudicated' }, reference: { verdict: 'pass', evidence: 'adjudicated' }, date: { verdict: 'pass', evidence: 'adjudicated' }, amount: { verdict: 'pass', evidence: 'adjudicated' }, table: { verdict: 'pass', evidence: 'adjudicated' }, anchor: { verdict: 'pass', evidence: 'adjudicated' } }, quality: { characterAccuracy: 1, wordAccuracy: 1, evidence: 'adjudicated' } } }) }
}

async function evaluatorOutput(manifest: BenchmarkManifest): Promise<string> {
  const output = await mkdtemp(join(tmpdir(), 'ocr-benchmark-'))
  await writeFile(join(output, 'run-manifest.json'), JSON.stringify({ schemaVersion: 2, runId: manifest.evaluatorRunId, mode: 'page', location: manifest.location, processorVersion: manifest.processorVersion, files: manifest.cases.map((entry) => ({ sourceFileName: `doc-${entry.caseId.slice(5)}.pdf`, sourceSha256: entry.sourceSha256, sourcePageCount: 1, selectedPages: [1], outputDirectory: entry.evaluatorDocumentDirectory })) }))
  for (const entry of manifest.cases) { const directory = join(output, entry.evaluatorDocumentDirectory); await mkdir(directory); const raw = JSON.stringify({ document: { text: 'x', pages: [{ pageNumber: 1, tokens: [{ layout: {} }] }] } }); const normalizedRaw = `${JSON.stringify(JSON.parse(raw), null, 2)}\n`; const hash = createHash('sha256').update(normalizedRaw).digest('hex'); if (entry.routing.expectedAction === 'ocr') await writeFile(join(directory, 'page-0001.raw.json'), normalizedRaw); await writeFile(join(directory, 'pages.summary.json'), JSON.stringify([{ sourcePageNumber: 1, providerPageNumber: entry.routing.expectedAction === 'ocr' ? 1 : 0, observedRoute: entry.routing.expectedAction, elapsedMs: 10, billedPages: entry.routing.expectedAction === 'ocr' ? 1 : 0, rawSha256: entry.routing.expectedAction === 'ocr' ? hash : null, nativeQuality: { accepted: entry.routing.expectedAction === 'native', reasons: [] }, textLength: 1, tokenCount: 1 }])) }
  return output
}

test('rejects a duplicate selected source page, including copied PDFs', () => { const value = fixture(); value.cases[1].sourceSha256 = value.cases[0].sourceSha256; assert.throws(() => validateManifest(value), /duplicate source page/) })
test('rejects missing category and mutable processor alias', () => { const value = fixture(); value.cases.forEach((entry) => { entry.categories = ['native_english'] }); assert.throws(() => validateManifest(value), /missing required category/); value.processorVersion = 'stable'; assert.throws(() => validateManifest(value), /approved pin/) })
test('reports unknown labels separately and fails closed', async () => { const value = fixture(); value.cases[0].checks.date.verdict = 'unknown'; const report = await buildReport(value, await evaluatorOutput(value)); const checks = report.checks as Record<string, { unknown: number }>; assert.equal(checks.date.unknown, 1); assert.equal((report.gate as { status: string }).status, 'structurally_incomplete') })
test('not applicable is separate from an unknown and does not fail an otherwise covered check', async () => { const value = fixture(); value.cases[0].checks.table.verdict = 'not_applicable'; const report = await buildReport(value, await evaluatorOutput(value)); const table = (report.checks as Record<string, { denominator: number; notApplicable: number; unknown: number }>).table; assert.deepEqual(table, { correct: 59, failed: 0, unknown: 0, notApplicable: 1, denominator: 59, accuracy: 1 }); assert.equal((report.gate as { status: string }).status, 'evidence_complete') })
test('missing applicable critical-fact coverage fails closed', async () => { const value = fixture(); value.cases.forEach((entry) => { entry.checks.amount.verdict = 'not_applicable' }); const report = await buildReport(value, await evaluatorOutput(value)); assert.deepEqual((report.gate as { missingCriticalCoverage: string[] }).missingCriticalCoverage, ['amount']); assert.equal((report.gate as { status: string }).status, 'structurally_incomplete') })
test('critical handwritten date failure cannot be hidden by aggregates', async () => { const value = fixture(); value.cases[4].checks.date.verdict = 'fail'; const report = await buildReport(value, await evaluatorOutput(value)); assert.equal((report.checks as Record<string, { failed: number }>).date.failed, 1); assert.equal((report.gate as { status: string }).status, 'structurally_incomplete') })
test('allows one output directory for multiple pages of one source but rejects source collisions', () => { const valid = fixture(); valid.cases[1].sourceSha256 = valid.cases[0].sourceSha256; valid.cases[1].sourcePageNumber = 2; valid.cases[1].evaluatorDocumentDirectory = valid.cases[0].evaluatorDocumentDirectory; assert.doesNotThrow(() => validateManifest(valid)); const collision = fixture(); collision.cases[1].evaluatorDocumentDirectory = collision.cases[0].evaluatorDocumentDirectory; assert.throws(() => validateManifest(collision), /more than one source SHA-256/) })
test('safe report excludes labels, output paths, and provider content', async () => { const value = fixture(); const result = await buildReport(value, await evaluatorOutput(value)); const report = JSON.stringify(result); assert.doesNotMatch(report, /evaluatorDocumentDirectory|sourceSha256|raw\.json|\/tmp\//); assert.match(report, /authoritativeEvaluatorRunManifestSha256/); assert.deepEqual(result.evaluatorRun, { generatedId: 'evaluator-1', provenance: 'matched_to_evaluator_run_manifest' }) })
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
test('missing expected route or OCR quality leaves the evidence structurally incomplete', async () => { const value = fixture(); value.cases.forEach((entry) => { entry.routing.expectedAction = 'ocr' }); let report = await buildReport(value, await evaluatorOutput(value)); assert.equal((report.gate as { status: string }).status, 'structurally_incomplete'); const quality = fixture(); quality.cases[1].quality.characterAccuracy = null; report = await buildReport(quality, await evaluatorOutput(quality)); assert.equal((report.gate as { qualityMissingCount: number }).qualityMissingCount, 1) })
test('benchmark and evaluator CLIs have strict help and option exits', () => {
  const run = (script: string, args: string[]) => spawnSync('npx', ['tsx', script, ...args], { cwd: process.cwd(), encoding: 'utf8' }).status
  assert.equal(run('scripts/document-ai/ocr-acquisition-benchmark.ts', ['--help']), 0)
  assert.notEqual(run('scripts/document-ai/ocr-acquisition-benchmark.ts', ['--bogus', 'x']), 0)
  assert.equal(run('scripts/document-ai/evaluate-ocr.ts', ['--help']), 0)
  assert.notEqual(run('scripts/document-ai/evaluate-ocr.ts', ['--input', 'x', '--input', 'x']), 0)
  assert.notEqual(run('scripts/document-ai/evaluate-ocr.ts', ['--unknown', 'x']), 0)
})
