import { expect, test, type APIRequestContext, type Locator, type Page } from '@playwright/test'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { validateCallbackLocation, validateVerificationUrl } from '../../scripts/acceptance/release-journey-boundary.mjs'
import { assessNativePageQuality, extractNativePdfPages } from '../../src/lib/documents/native-pdf-pages'

const capturedMailUrl = process.env.RELEASE_JOURNEY_INBUCKET_URL
const workdir = process.env.RELEASE_JOURNEY_SUPABASE_WORKDIR
if (!capturedMailUrl || !['127.0.0.1', 'localhost'].includes(new URL(capturedMailUrl).hostname)) {
  throw new Error('Release-journey acceptance requires loopback captured mail.')
}
if (!workdir || !readFileSync(join(workdir, 'supabase/config.toml'), 'utf8').includes('project_id = "dms-release-journey-162"')) {
  throw new Error('Release-journey acceptance requires its exclusively owned disposable stack.')
}

const ownerEmail = process.env.RELEASE_JOURNEY_OWNER_EMAIL
if (!ownerEmail || !/^release-owner-[0-9a-f]{12}@acceptance\.test$/.test(ownerEmail)) throw new Error('Release-journey acceptance requires its per-run Owner address.')
const password = 'Release-journey-only-2026!'
const sourcePdf = readFileSync(join(process.cwd(), 'tests/acceptance/fixtures/synthetic-multi-page.pdf'))
const conflictPdf = readFileSync(join(process.cwd(), 'tests/acceptance/fixtures/synthetic-extraction-conflict.pdf'))
const conflictUploadSuffix = '\n% conflict-release-journey\n'
const conflictUploadHash = createHash('sha256').update(Buffer.concat([conflictPdf, Buffer.from(conflictUploadSuffix)])).digest('hex')
const globalUploadBytes = Buffer.concat([sourcePdf, Buffer.from('\n% global-release-journey\n')])
const globalUploadHash = createHash('sha256').update(globalUploadBytes).digest('hex')
const isolatedApiUrl = process.env.RELEASE_JOURNEY_API_URL
const isolatedServiceKey = process.env.RELEASE_JOURNEY_SERVICE_ROLE_KEY
if (isolatedApiUrl !== 'http://127.0.0.1:56221' || !isolatedServiceKey) {
  throw new Error('Object-loss acceptance requires the exclusively owned loopback Storage service.')
}
let conflictPageTexts: string[] = []

function databaseOperation(operation: 'prepare' | 'activate-relationship' | 'verify' | 'signup-diagnostic' | 'loss-target' | 'loss-verify' | 'extraction-closure') {
  const result = spawnSync(process.execPath, ['scripts/acceptance/release-journey-db.mjs', operation], {
    cwd: process.cwd(), env: { ...process.env, RELEASE_JOURNEY_CONFLICT_PAGE_TEXTS: JSON.stringify(conflictPageTexts), RELEASE_JOURNEY_CONFLICT_UPLOAD_SHA256: conflictUploadHash, RELEASE_JOURNEY_GLOBAL_UPLOAD_SHA256: globalUploadHash, RELEASE_JOURNEY_GLOBAL_UPLOAD_BYTES: String(globalUploadBytes.length) }, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024,
  })
  if (result.error || result.status !== 0) {
    if (operation === 'loss-target') throw new Error('Exact disposable source-loss target lookup failed.')
    throw new Error(result.error?.message ?? `${result.stderr}\n${result.stdout}`)
  }
  return result.stdout.trim()
}

async function expectSignupAccepted(page: Page, request: APIRequestContext) {
  const status = page.getByRole('status')
  const failure = page.getByText('The account could not be created. Check the details and try again.')
  let state = 'pending'
  try {
    await expect.poll(async () => {
      if (await status.isVisible().catch(() => false)) return 'accepted'
      if (await failure.isVisible().catch(() => false)) return 'rejected'
      return 'pending'
    }).toBe('accepted')
    state = 'accepted'
  } catch {
    state = await failure.isVisible().catch(() => false) ? 'rejected' : 'timed_out'
  }
  if (state === 'accepted') return
  const [authHealth, mailHealth] = await Promise.all([
    request.get('http://127.0.0.1:56221/auth/v1/health'),
    request.get(`${capturedMailUrl}/api/v1/mailbox`),
  ])
  throw new Error(`Confirmation-required signup ${state}; safe diagnostics: auth_health=${authHealth.status()}, mail_capture=${mailHealth.status()}, database=${databaseOperation('signup-diagnostic')}`)
}

function collectStrings(value: unknown): string[] {
  if (typeof value === 'string') return [value]
  if (Array.isArray(value)) return value.flatMap(collectStrings)
  if (value && typeof value === 'object') return Object.values(value).flatMap(collectStrings)
  return []
}

async function verificationLink(request: APIRequestContext, email: string) {
  let found: string | null = null
  await expect.poll(async () => {
    const mailpit = await request.get(`${capturedMailUrl}/api/v1/messages?limit=50`)
    let messages: Array<Record<string, unknown>> = []
    let detailPath = ''
    if (mailpit.ok()) {
      const payload = await mailpit.json()
      messages = Array.isArray(payload) ? payload : payload.messages ?? []
      detailPath = '/api/v1/message/'
    } else {
      const inbucket = await request.get(`${capturedMailUrl}/api/v1/mailbox/${encodeURIComponent(email)}`)
      if (!inbucket.ok()) return null
      const payload = await inbucket.json()
      messages = Array.isArray(payload) ? payload : payload.messages ?? []
      detailPath = `/api/v1/mailbox/${encodeURIComponent(email)}/`
    }
    const message = messages.find((candidate) => JSON.stringify(candidate).toLowerCase().includes(email.toLowerCase()))
    const messageId = message?.id ?? message?.ID
    if (!messageId) return null
    const detail = await request.get(`${capturedMailUrl}${detailPath}${encodeURIComponent(String(messageId))}`)
    if (!detail.ok()) return null
    const content = collectStrings(await detail.json()).join('\n').replaceAll('&amp;', '&').replaceAll('=3D', '=').replace(/=\r?\n/g, '')
    found = content.match(/https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/)?.[0] ?? null
    return found
  }, { timeout: 15_000 }).not.toBeNull()
  if (!found) throw new Error('Captured verification mail had no verification URL.')
  return validateVerificationUrl(found, { authOrigin: 'http://127.0.0.1:56221', appOrigin: 'http://127.0.0.1:3113' })
}

async function expectNoOverflow(page: Page) {
  await expect.poll(() => page.evaluate(() =>
    document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1
    && document.body.scrollWidth <= document.body.clientWidth + 1,
  )).toBe(true)
}

async function expectMinimumTarget(locator: Locator) {
  const box = await locator.boundingBox()
  expect(box).not.toBeNull()
  const pseudo = await locator.evaluate((element) => {
    const style = getComputedStyle(element, '::before')
    return { width: Number.parseFloat(style.width) || 0, height: Number.parseFloat(style.height) || 0 }
  })
  expect(Math.max(box?.width ?? 0, pseudo.width)).toBeGreaterThanOrEqual(43.9)
  expect(Math.max(box?.height ?? 0, pseudo.height)).toBeGreaterThanOrEqual(43.9)
}

async function uploadPdf(page: Page, filename: string, suffix: string, destination: string, source: Buffer = sourcePdf) {
  await page.getByRole('button', { name: 'Upload PDFs' }).first().click()
  const dialog = page.getByRole('dialog', { name: 'Add Documents' })
  await expect(dialog).toContainText(destination)
  await dialog.locator('input[type="file"]').setInputFiles({
    name: filename,
    mimeType: 'application/pdf',
    buffer: Buffer.concat([source, Buffer.from(suffix)]),
  })
  await expect(dialog).toHaveCount(0)
  await expect(page.getByRole('button', { name: new RegExp(filename.replace('.', '\\.')) })).toBeVisible()
}

test('fresh Owner completes the coherent local mandatory first-release rehearsal', async ({ page, request }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  const acquiredPages = await extractNativePdfPages(conflictPdf)
  expect(acquiredPages).toHaveLength(4)
  for (const acquired of acquiredPages) expect(assessNativePageQuality(acquired)).toEqual({ accepted: true, reasons: [] })
  conflictPageTexts = acquiredPages.map(acquired => acquired.text)
  expect(conflictPageTexts[0]).toContain('Document type OIO')
  expect(conflictPageTexts[1]).toContain('Document type SCN')
  expect(conflictPageTexts[0].match(/\bOIO\b/g)).toHaveLength(1)
  expect(conflictPageTexts[1].match(/\bSCN\b/g)).toHaveLength(1)

  await page.goto('/signup')
  await page.getByLabel('Full name').fill('Release Journey Owner')
  await page.getByLabel('Work email').fill(ownerEmail)
  await page.getByLabel(/^Password/).fill(password)
  await page.getByLabel('Confirm password').fill(password)
  await page.getByRole('button', { name: 'Create account' }).click()
  await expectSignupAccepted(page, request)
  await expect(page.getByRole('status')).toContainText('check your email')
  const response = await request.get(await verificationLink(request, ownerEmail), { maxRedirects: 0 })
  expect([302, 303]).toContain(response.status())
  const location = response.headers().location
  if (!location) throw new Error('Auth verification did not return a callback location.')
  const callback = validateCallbackLocation(location, { authOrigin: 'http://127.0.0.1:56221', appOrigin: 'http://127.0.0.1:3113' })
  await page.goto(callback)
  await expect(page).toHaveURL(/\/onboarding$/)
  await page.getByLabel('Organisation name').fill('Release Journey Organisation')
  await page.getByRole('button', { name: 'Create organisation' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)

  await page.goto('/clients')
  await page.getByRole('button', { name: 'New Client' }).first().click()
  await page.getByLabel('Client name').fill('Release Journey Client')
  await page.getByLabel('GSTIN').fill('27AABCR1234F1Z5')
  await page.getByRole('button', { name: 'Create client' }).click()
  const clientLink = page.getByRole('link', { name: /Release Journey Client/ })
  await expect(clientLink).toBeVisible()
  await clientLink.click()
  await expect(page).toHaveURL(/\/clients\/[0-9a-f-]+$/)
  const clientUrl = page.url()

  await page.getByRole('button', { name: 'New Matter' }).first().click()
  await page.getByLabel('Matter Title').fill('Release Journey Primary')
  await page.getByLabel('Financial Year').selectOption('2024-25')
  await page.getByLabel('Description').fill('Lifecycle-active synthetic production rehearsal matter')
  await page.getByRole('button', { name: 'Create matter' }).click()
  await expect(page).toHaveURL(/\/matters\/[0-9a-f-]+$/)
  const primaryMatterId = new URL(page.url()).pathname.split('/').at(-1)!

  await page.goto(clientUrl)
  await page.getByRole('button', { name: 'New Matter' }).click()
  await page.getByLabel('Matter Title').fill('Release Journey Alternate')
  await page.getByLabel('Financial Year').selectOption('2023-24')
  await page.getByRole('button', { name: 'Create matter' }).click()
  await expect(page).toHaveURL(/\/matters\/[0-9a-f-]+$/)

  await page.goto('/documents')
  const inboxNav = page.getByRole('link', { name: 'Document Inbox' })
  await inboxNav.focus()
  await expect(inboxNav).toBeFocused()
  await expect(page.getByRole('heading', { name: 'Upload Queue', exact: true })).toBeVisible()
  await expect(page.getByRole('textbox', { name: 'Search Upload Queue' })).toBeVisible()
  await uploadPdf(page, 'release-global-intake.pdf', '\n% global-release-journey\n', 'Destination: Global Inbox')
  await page.goto(`/matters/${primaryMatterId}?section=details`)
  await page.getByRole('link', { name: 'Open Workbench' }).click()
  await expect(page).toHaveURL(new RegExp(`/documents\\?matterId=${primaryMatterId}`))
  await expect(page.getByRole('link', { name: 'Return to Matter' })).toHaveAttribute('href', `/matters/${primaryMatterId}`)
  await expect(page.getByRole('button', { name: 'Clear Matter context' })).toBeVisible()
  await uploadPdf(page, 'release-matter-origin.pdf', '\n% matter-release-journey\n', 'Destination: Release Journey Primary')
  await uploadPdf(page, 'release-extraction-conflict.pdf', conflictUploadSuffix, 'Destination: Release Journey Primary', conflictPdf)

  const prepared = JSON.parse(databaseOperation('prepare').split('\n').at(-1)!)
  expect(prepared.primaryMatterId).toBe(primaryMatterId)
  expect(prepared.extractionReviewId).toMatch(/^[0-9a-f-]{36}$/)
  await page.goto('/review?type=extraction_conflict&search=release-extraction-conflict')
  await page.getByRole('button', { name: /^Review type/ }).click()
  await expect(page.getByText('Document version 1')).toBeVisible()
  await expect(page.getByText('Evidence 1 · Page 1')).toBeVisible()
  await expect(page.getByText('Evidence 2 · Page 2')).toBeVisible()
  await expect(page.locator('blockquote').first()).toContainText('Document type OIO')
  await expect(page.locator('blockquote').last()).toContainText('Document type SCN')
  const citedPage = page.getByRole('link', { name: 'Open exact source · Page 2' })
  await expect(citedPage).toHaveAttribute('href', `/documents/${prepared.extractionDocumentId}?version=${prepared.extractionVersionId}&page=2`)
  await citedPage.click()
  await expect(page).toHaveURL(new RegExp(`/documents/${prepared.extractionDocumentId}\\?version=${prepared.extractionVersionId}&page=2$`))
  await expect(page.getByText('PDF source · Version 1 · Page 2 of 4')).toBeVisible()
  await expect(page.locator('[data-pdf-page="2"] canvas')).toBeVisible()
  await page.goto('/review?type=extraction_conflict&search=release-extraction-conflict')
  await page.getByRole('button', { name: /^Review type/ }).click()
  await page.getByRole('button', { name: 'View decision' }).click()
  await page.getByRole('radio', { name: /Use SCN/ }).check()
  await page.getByRole('button', { name: 'Review decision' }).click()
  await expect(page.getByRole('dialog')).toContainText('Competing item candidates will be rejected')
  await page.getByLabel('Reason', { exact: true }).fill('The printed page-two SCN label is the chosen current-version document type.')
  await page.getByRole('button', { name: 'Confirm selected value' }).click()
  // The client refresh can replace its transient confirmation message before
  // Playwright observes it. Assert the durable typed decision instead.
  await expect.poll(() => JSON.parse(databaseOperation('extraction-closure')).closed).toBe(1)
  await page.goto(`/documents/${prepared.extractionDocumentId}?version=${prepared.extractionVersionId}&page=2`)
  await expect(page.getByText('PDF source · Version 1 · Page 2 of 4')).toBeVisible()

  await page.goto('/review?type=processing_recovery&search=release-matter-origin')
  await page.getByRole('button', { name: /^Continue document manually/ }).click()
  await expect(page.getByRole('link', { name: 'Open exact source · Page 1' })).toHaveAttribute('href', /version=.*page=1/)
  await page.getByRole('button', { name: 'View decision' }).click()
  await page.getByLabel('Document type').selectOption('SCN')
  await page.getByLabel('Reference number').fill('SCN/RELEASE/2026/01')
  await page.getByLabel('Document date').fill('2026-09-15')
  await page.getByLabel('Direction').selectOption('incoming')
  await page.getByLabel('Issued by').fill('Synthetic GST Authority')
  await page.getByRole('button', { name: 'Review manual continuation' }).click()
  await expect(page.getByRole('dialog')).toContainText('Automated extraction will not be retried.')
  await page.getByLabel('Reason', { exact: true }).fill('Provider failure recorded; core facts verified against the immutable local PDF.')
  await page.getByRole('button', { name: 'Continue manually' }).click()
  await expect(page.getByText('Manual continuation recorded', { exact: true })).toBeVisible()

  await page.goto('/review?type=ambiguous_placement&search=release-global-intake')
  await page.getByRole('button', { name: /^Choose a Matter destination/ }).click()
  await page.getByRole('button', { name: 'View decision' }).click()
  await page.getByRole('radio', { name: /Place in Release Journey Primary/ }).check()
  await page.getByRole('button', { name: 'Review destination' }).click()
  await page.getByLabel('Reason', { exact: true }).fill('The verified client identifier places this PDF in the primary proceeding.')
  await page.getByRole('button', { name: 'Place in selected Matter' }).click()
  await expect(page).toHaveURL(/\/documents\/[0-9a-f-]+\?version=[0-9a-f-]+&page=1/)
  const exactWorkbenchUrl = page.url()
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await expect(page.locator('[data-pdf-page="1"] canvas')).toBeVisible()
  const backToMatter = page.getByRole('link', { name: 'Back to Matter' })
  await expect(backToMatter).toHaveAttribute('href', `/matters/${primaryMatterId}`)
  await backToMatter.click()
  await expect(page).toHaveURL(new RegExp(`/matters/${primaryMatterId}`))

  await page.goto(`/matters/${primaryMatterId}?section=timeline&view=chronology`)
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  const chronology = page.getByRole('table')
  await expect(chronology).toContainText('release-global-intake')
  await expect(chronology).toContainText('release-matter-origin')
  databaseOperation('activate-relationship')
  await page.goto(`/matters/${primaryMatterId}?section=timeline&view=graph`)
  await expect(page.getByLabel('Procedural timeline graph')).toBeVisible()
  await page.getByText(/Relationship list \(1\)/).click()
  await expect(page.getByRole('list', { name: 'Timeline relationships' })).toContainText('responds')

  await page.goto(`/matters/${primaryMatterId}?section=deadlines`)
  await page.getByRole('button', { name: 'Add deadline' }).first().click()
  await page.getByLabel('Concise title').fill('File release rehearsal response')
  await page.getByLabel('Obligation').fill('File the synthetic response with the tribunal registry')
  await page.getByLabel('Legal deadline type').selectOption('reply_due')
  await page.getByLabel('Due date').fill('2030-10-15')
  await page.getByLabel('Manual basis').fill('Synthetic tribunal direction checked by the Owner')
  await page.getByRole('button', { name: 'Add deadline', exact: true }).last().click()
  await expect(page.getByRole('dialog', { name: 'Add legal deadline' })).toHaveCount(0)
  await page.goto(`/matters/${primaryMatterId}?section=deadlines`)
  await expect(page.getByText('Legal date agenda')).toBeVisible()
  const deadlineRow = page.getByRole('row', { name: /File release rehearsal response/ })
  await expect(deadlineRow).toContainText('Upcoming')
  await deadlineRow.getByRole('button', { name: 'View details' }).click()
  await expect(page.getByText('Synthetic tribunal direction checked by the Owner')).toBeVisible()

  await page.setViewportSize({ width: 320, height: 740 })
  await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' })
  await page.evaluate(() => { localStorage.setItem('theme', 'dark'); document.documentElement.classList.add('dark') })
  await page.goto(exactWorkbenchUrl)
  await expect(page.locator('html')).toHaveClass(/dark/)
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await expectMinimumTarget(page.getByRole('link', { name: 'Back to Matter' }))
  await expectNoOverflow(page)
  await page.goto(`/matters/${primaryMatterId}?section=timeline&view=chronology`)
  const filter = page.getByRole('button', { name: 'Filter', exact: true })
  await filter.focus()
  await expect(filter).toBeFocused()
  await expectMinimumTarget(filter)
  await expectNoOverflow(page)
  await page.goto('/review?status=closed&type=ambiguous_placement&search=release-global-intake')
  await expect(page.getByRole('button', { name: /^Choose a Matter destination/ })).toBeVisible()
  await expectNoOverflow(page)
  await page.goto(`/documents?matterId=${primaryMatterId}`)
  await expect(page.getByRole('heading', { name: 'Upload Queue', exact: true })).toBeVisible()
  await expectMinimumTarget(page.getByRole('link', { name: 'Return to Matter' }))
  await expectMinimumTarget(page.getByRole('button', { name: 'Clear Matter context' }))
  await expectNoOverflow(page)

  expect(databaseOperation('verify')).toContain('Release journey cross-feature SQL assertions passed.')

  // A formerly valid, placed canonical source is removed only from this owned
  // disposable Storage stack. SQL identity and typed Review remain authoritative.
  const lossTarget = JSON.parse(databaseOperation('loss-target')) as { bucket: string; key: string }
  const isolatedStorage = createClient(isolatedApiUrl, isolatedServiceKey, { auth: { persistSession: false } }).storage
  const { data: removed, error: removalError } = await isolatedStorage.from(lossTarget.bucket).remove([lossTarget.key])
  if (removalError || removed?.length !== 1) throw new Error('Exact disposable Storage object removal failed.')
  const { error: missingInfoError } = await isolatedStorage.from(lossTarget.bucket).info(lossTarget.key)
  console.log(`Missing-object Storage info safe status: HTTP ${missingInfoError?.status ?? 'unavailable'}, API ${missingInfoError?.statusCode ?? 'unavailable'}`)
  if (missingInfoError?.statusCode !== '404') throw new Error('Disposable missing-object probe did not return trusted Storage API 404.')
  expect(databaseOperation('loss-verify')).toContain('Missing-object metadata and Review identity remain exact.')

  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto(exactWorkbenchUrl)
  await expect(page.getByText('PDF file unavailable')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refresh PDF access' })).toHaveCount(0)
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await page.goto(`/matters/${primaryMatterId}?section=timeline&view=chronology`)
  await expect(page.getByRole('table')).toContainText('release-global-intake')
  await page.getByRole('link', { name: /release-global-intake/ }).first().click()
  await page.getByRole('link', { name: 'Open document' }).click()
  await expect(page.getByText('PDF file unavailable')).toBeVisible()
  await page.goto('/documents')
  await expect(page.getByRole('heading', { name: 'Upload Queue', exact: true })).toBeVisible()
  // Placed Intake leaves the active Upload Queue; its assigned identity is
  // asserted in SQL and its missing exact source remains reachable from Matter.
  await expect(page.getByRole('button', { name: 'View details for release-global-intake.pdf' })).toHaveCount(0)
  await page.goto(`/documents/${prepared.extractionDocumentId}?version=${prepared.extractionVersionId}&page=2`)
  await expect(page.locator('[data-pdf-page="2"] canvas')).toBeVisible()

  await page.setViewportSize({ width: 320, height: 740 })
  await page.goto(exactWorkbenchUrl)
  const lostStatus = page.getByText('PDF file unavailable')
  await page.getByRole('link', { name: 'Back to Matter' }).focus()
  await expect(page.getByRole('link', { name: 'Back to Matter' })).toBeFocused()
  await expect(lostStatus).toBeVisible()
  await expectNoOverflow(page)
  expect(databaseOperation('loss-verify')).toContain('Missing-object metadata and Review identity remain exact.')
})
