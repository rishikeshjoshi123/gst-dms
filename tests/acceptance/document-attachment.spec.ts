import { expect, test, type Page } from '@playwright/test'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { createHash } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { PDFDocument } from 'pdf-lib'
import { launchChromiumPageZoom } from './chromium-page-zoom'

const documentId = '154e0000-0000-0000-0000-000000000008'
function localContext() {
  const workdir = process.env.ATTACHMENT_ACCEPTANCE_WORKDIR
  if (!workdir || !readFileSync(join(workdir, 'supabase/config.toml'), 'utf8').includes('project_id = "dms-attachment-154"')) throw new Error('Requires owned disposable attachment stack.')
  const result = spawnSync(process.execPath, ['node_modules/supabase/dist/supabase.js', 'status', '--workdir', workdir, '-o', 'json'], { encoding: 'utf8' })
  if (result.status !== 0) throw new Error('Disposable status unavailable')
  const local = JSON.parse(result.stdout)
  if (local.API_URL !== 'http://127.0.0.1:56321' || new URL(local.DB_URL).port !== '56322') throw new Error('Unexpected acceptance destination')
  return local
}
function db(sql: string) {
  localContext()
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_dms-attachment-154', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: sql, encoding: 'utf8', timeout: 15000 })
  if (result.status !== 0) throw new Error(result.stderr)
  return result.stdout.trim()
}
async function login(page: Page, user = 1) {
  await page.goto('/login')
  await page.getByLabel('Email address').fill(`attachment-${user}@example.test`)
  await page.getByLabel('Password').fill('AttachmentFixture154!')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
}
test('real private TUS first attachment preserves record and opens canonical four-page PDF', async ({ page }) => {
  await login(page)
  await page.setViewportSize({ width: 320, height: 740 })
  await page.goto(`/documents/${documentId}`)
  await expect(page.getByRole('heading', { name: 'No file attached' })).toBeVisible()
  const bytes = readFileSync('tests/acceptance/fixtures/synthetic-multi-page.pdf')
  await page.getByLabel('PDF file', { exact: true }).setInputFiles({ name: `${'long-source-name-'.repeat(10)}.pdf`, mimeType: 'application/pdf', buffer: bytes })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.getByRole('button', { name: 'Attach PDF', exact: true }).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByRole('button', { name: 'Check attachment status' })).toBeVisible()
  const local = localContext()
  const client = createClient(local.API_URL, local.SERVICE_ROLE_KEY, { auth: { persistSession: false } })
  const event = db(`SELECT e.id FROM public.outbox_events e JOIN public.document_attachment_intents a ON a.upload_session_id=e.aggregate_id WHERE a.document_id='${documentId}' AND e.event_kind='document.upload_validation_requested.v1';`)
  const { data: claims, error } = await client.rpc('claim_document_validation_work', { p_event_id: event })
  expect(error).toBeNull()
  const claim = claims[0]
  expect(claim.code).toBe('claimed')
  const { data: stored, error: storageError } = await client.storage.from(claim.bucket_id).download(claim.object_key)
  expect(storageError).toBeNull()
  const storedBytes = Buffer.from(await stored!.arrayBuffer())
  expect(createHash('sha256').update(storedBytes).digest('hex')).toBe(createHash('sha256').update(bytes).digest('hex'))
  const pdf = await PDFDocument.load(storedBytes)
  expect(pdf.getPageCount()).toBe(4)
  const finish = await client.rpc('finish_document_validation_work', { p_source_run_id: claim.source_run_id, p_lease_token: claim.lease_token, p_outcome: 'ready', p_page_count: pdf.getPageCount() })
  expect(finish.error).toBeNull()
  const validated = db(`SELECT id FROM public.outbox_events WHERE aggregate_id='${claim.intake_id}' AND event_kind='document.intake_validated.v1';`)
  const routed = await client.rpc('auto_assign_intended_matter_intake', { p_intake_id: claim.intake_id, p_validation_event_id: validated })
  expect(routed.error).toBeNull()
  expect(routed.data[0].code).toBe('ok')
  expect(routed.data[0].document_id).toBe(documentId)
  await page.getByRole('button', { name: 'Check attachment status' }).click()
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await expect(page.locator('[data-pdf-page="1"] canvas')).toBeVisible()
  await expect(page.getByRole('region', { name: 'Document workbench' })).toBeFocused()
  await expect(page.getByRole('button', { name: 'Attach PDF', exact: true })).toHaveCount(0)
  expect(db(`SELECT reference_number||':'||doc_type FROM public.documents WHERE id='${documentId}';`)).toBe('HUMAN-154:SCN')
  expect(db(`SELECT count(*) FROM public.document_processing_runs WHERE document_id='${documentId}';`)).toBe('0')
})
test('Viewer cannot attach a PDF to a metadata-only record', async ({ page }) => {
  await login(page, 3)
  await page.goto('/documents/154e0000-0000-0000-0000-000000000007')
  await expect(page.getByRole('heading', { name: 'No file attached' })).toBeVisible()
  await expect(page.getByRole('form', { name: 'Attach first PDF' })).toHaveCount(0)
})

test('dark reduced-motion attachment form wraps and reports invalid local PDF with a retry path', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' })
  await page.setViewportSize({ width: 320, height: 740 })
  await login(page)
  await page.goto('/documents/154e0000-0000-0000-0000-000000000007')
  const input = page.getByLabel('PDF file', { exact: true })
  await input.setInputFiles({ name: `${'invalid-long-name-'.repeat(10)}.pdf`, mimeType: 'application/pdf', buffer: Buffer.from('This is not a PDF.') })
  const action = page.getByRole('button', { name: 'Attach PDF', exact: true })
  expect((await action.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await action.click()
  await expect(action).toBeEnabled()
  await expect(page.getByRole('form', { name: 'Attach first PDF' }).getByRole('status')).toContainText(/PDF|upload/i)
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await expect(input).toBeEnabled()
  expect(db("SELECT count(*) FROM public.document_versions WHERE document_id='154e0000-0000-0000-0000-000000000007';")).toBe('0')
})

test('desktop and true 200% zoom preserve retry, cancellation and keyboard focus', async () => {
  const zoom = await launchChromiumPageZoom('http://127.0.0.1:3104', { width: 1440, height: 1000 })
  try {
    const page = zoom.page
    await login(page)
    await page.goto('/documents/154e0000-0000-0000-0000-000000000007')
    await expect(page.getByRole('form', { name: 'Attach first PDF' })).toBeVisible()
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await zoom.setZoom(2)
    await expect.poll(() => page.evaluate(() => window.devicePixelRatio)).toBe(2)
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    const input = page.getByLabel('PDF file', { exact: true })
    await input.setInputFiles('tests/acceptance/fixtures/synthetic-multi-page.pdf')
    let failedOnce = false
    await page.route('**/documents/154e0000-0000-0000-0000-000000000007', async route => {
      if (!failedOnce && route.request().method() === 'POST') { failedOnce = true; await route.abort('internetdisconnected') }
      else await route.continue()
    })
    const action = page.getByRole('button', { name: 'Attach PDF', exact: true })
    await action.focus()
    await page.keyboard.press('Enter')
    await expect(page.getByRole('form', { name: 'Attach first PDF' }).getByRole('status')).toContainText('Retry with this file')
    await expect(action).toBeEnabled()
    await page.unroute('**/documents/154e0000-0000-0000-0000-000000000007')
    // Disposable browser transport fault keeps the real reservation cancellable;
    // no production fault hook or provider is involved.
    await page.route('**/storage/v1/upload/resumable/**', route => route.abort('internetdisconnected'))
    await action.click()
    const cancel = page.getByRole('button', { name: 'Cancel upload' })
    await expect(cancel).toBeVisible()
    await expect(page.getByRole('button', { name: 'Attaching PDF…' })).toBeDisabled()
    await cancel.focus()
    await page.keyboard.press('Enter')
    await expect(page.getByRole('form', { name: 'Attach first PDF' }).getByRole('status')).toContainText(/cancelled/i)
    await expect(input).toBeFocused()
    await expect(action).toBeEnabled()
    expect(db("SELECT count(*) FROM public.document_versions WHERE document_id='154e0000-0000-0000-0000-000000000007';")).toBe('0')
  } finally { await zoom.close() }
})
