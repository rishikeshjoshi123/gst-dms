import { readFile, rm, writeFile } from 'node:fs/promises'

import { expect, test, type Locator, type Page, type Route } from '@playwright/test'

const password = 'CaseChain-local-only-2026!'
const matterId = 'd0010000-0000-0000-0000-000000000001'
const uploadMatterId = 'd0020000-0000-4000-8000-000000000001'
const foreignMatterId = 'd0010000-0000-0000-0000-000000000002'
const sourceDocumentId = 'e0010000-0000-0000-0000-000000000001'
const sourceVersionId = 'f1010000-0000-0000-0000-000000000001'
const missingDocumentId = 'e0010000-0000-0000-0000-000000000004'
const missingVersionId = 'f1010000-0000-0000-0000-000000000002'
const sourcePdfPath = 'tests/acceptance/fixtures/synthetic-multi-page.pdf'
const completionFileName = 'acceptance-browser-complete.pdf'
const cancellationFileName = 'acceptance-browser-cancel.pdf'
const cancellationFilePath = '/tmp/acceptance-browser-cancel.pdf'
const completionSuffix = '\n% CaseChain browser upload completion fixture\n'

let sourcePdf: Buffer

test.beforeAll(async () => {
  sourcePdf = await readFile(sourcePdfPath)
  const cancellationBytes = Buffer.concat([
    sourcePdf,
    Buffer.from('\n% CaseChain cancellable TUS fixture\n'),
    Buffer.alloc(7 * 1024 * 1024, 0x20),
  ])
  await writeFile(cancellationFilePath, cancellationBytes)
})

test.afterAll(async () => {
  await rm(cancellationFilePath, { force: true })
})

async function login(page: Page, email = 'owner@acceptance.test') {
  await page.goto('/login')
  await page.getByLabel('Email address').fill(email)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
}

async function expectNoPageHorizontalOverflow(page: Page) {
  await expect.poll(() => page.evaluate(() => (
    document.documentElement.scrollWidth <= window.innerWidth
    && document.body.scrollWidth <= window.innerWidth
  ))).toBe(true)
}

async function expectMinimumTarget(locator: Locator) {
  const box = await locator.boundingBox()
  expect(box).not.toBeNull()
  const pseudo = await locator.evaluate(element => {
    const style = getComputedStyle(element, '::before')
    return { width: Number.parseFloat(style.width), height: Number.parseFloat(style.height) }
  })
  expect(Math.max(box?.width ?? 0, pseudo.width || 0)).toBeGreaterThanOrEqual(43.9)
  expect(Math.max(box?.height ?? 0, pseudo.height || 0)).toBeGreaterThanOrEqual(43.9)
}

function workbenchPath(documentId: string, versionId: string, page: number) {
  return `/documents/${documentId}?matterId=${matterId}&version=${versionId}&page=${page}`
}

test('real private PDF opens at its exact requested Workbench page and missing source fails safely', async ({ page }) => {
  await login(page)

  await page.goto(workbenchPath(sourceDocumentId, sourceVersionId, 3))
  await expect(page.getByText('PDF source · Version 1 · Page 3 of 4')).toBeVisible()
  await expect(page.getByLabel('Current PDF page')).toHaveValue('3')
  await expect(page.locator('[data-pdf-page="3"] canvas')).toBeVisible()

  await page.goto(workbenchPath(missingDocumentId, missingVersionId, 1))
  await expect(page.getByRole('heading', { name: 'PDF access needs refreshing' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refresh PDF access' })).toBeVisible()
  await expect(page.locator('body')).not.toContainText('orgs/b0010000-0000-0000-0000-000000000001/assets')

  const foreignResponse = await page.goto(`/matters/${foreignMatterId}?section=timeline&view=chronology`)
  expect(foreignResponse?.status()).toBe(404)
})

test('Matter chronology filters restore across browser Back and Forward', async ({ page }) => {
  await login(page)
  await page.goto(`/matters/${matterId}?section=timeline&view=chronology`)

  await expect(page.getByRole('heading', { name: 'Aster GST appeal' })).toBeVisible()
  await expect(page.getByText('Showing 1–3 of 3 proceedings').first()).toBeVisible()
  await expect(page.getByRole('link', { name: /Order in Original/ })).toBeVisible()

  await page.getByRole('button', { name: 'Filter', exact: true }).click()
  await page.getByLabel('Title or reference').fill('Reply to Show Cause Notice')
  await page.getByRole('button', { name: 'Apply filters' }).click()
  await expect(page.getByText('Showing 1–1 of 1 proceedings · 3 in matter').first()).toBeVisible()
  await expect(page.getByRole('link', { name: /Reply to Show Cause Notice/ })).toBeVisible()

  await page.goBack()
  await expect(page.getByText('Showing 1–3 of 3 proceedings').first()).toBeVisible()
  await expect(page.getByRole('link', { name: /Order in Original/ })).toBeVisible()

  await page.goForward()
  await expect(page.getByText('Showing 1–1 of 1 proceedings · 3 in matter').first()).toBeVisible()
  await expect(page.getByRole('link', { name: /Order in Original/ })).toHaveCount(0)

  await page.goBack()
  const orderRow = page.getByRole('link', { name: /Order in Original/ })
  await orderRow.click()
  const inspector = page.getByRole('complementary', { name: 'Selected proceeding' })
  await expect(inspector).toBeVisible()
  await expect(page).toHaveURL(new RegExp(`document=${sourceDocumentId}`))

  await page.goBack()
  await expect(inspector).toHaveCount(0)
  await page.goForward()
  await expect(inspector).toBeVisible()

  await inspector.getByRole('link', { name: 'Close' }).click()
  await expect(inspector).toHaveCount(0)
  await expect(orderRow).toBeFocused()

  await orderRow.press('Enter')
  await expect(inspector).toBeVisible()
  await inspector.getByRole('link', { name: 'Open document' }).click()
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await page.getByRole('link', { name: 'Back to Matter' }).click()
  await expect(page).toHaveURL(new RegExp(`/matters/${matterId}.*document=${sourceDocumentId}`))
  await expect(page.getByRole('complementary', { name: 'Selected proceeding' })).toBeVisible()
})

test('Team owner sees suspended members and authorised emails', async ({ page }) => {
  await login(page)
  await page.goto('/team')

  await expect(page.getByText('4 members')).toBeVisible()
  await page.getByRole('button', { name: /Suspended Associate/ }).click()
  const details = page.getByRole('complementary', { name: 'Member details' })
  await expect(details).toContainText('suspended@acceptance.test')
  await expect(details).toContainText('Suspended')
})

test('Team Viewer sees active peers but only their own email', async ({ page }) => {
  await login(page, 'viewer@acceptance.test')
  await page.goto('/team')

  await expect(page.getByText('3 members')).toBeVisible()
  await expect(page.getByText('Suspended Associate')).toHaveCount(0)

  await page.getByRole('button', { name: /Acceptance Owner/ }).click()
  let details = page.getByRole('complementary', { name: 'Member details' })
  await expect(details.locator('dd').first()).toHaveText('Unavailable')
  await details.getByRole('button', { name: 'Close details' }).click()

  await page.getByRole('button', { name: /Read-only Viewer/ }).click()
  details = page.getByRole('complementary', { name: 'Member details' })
  await expect(details).toContainText('viewer@acceptance.test')
  await details.getByRole('button', { name: 'Close details' }).click()

  await page.getByLabel('Search members').fill('owner@acceptance.test')
  await page.getByRole('button', { name: 'Search', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'No matching members' })).toBeVisible()
})

test('Dashboard and Inbox lead to one authoritative local TUS completion', async ({ page }) => {
  await login(page)

  const documentHub = page.getByRole('link', { name: 'Document Hub' })
  await documentHub.focus()
  await documentHub.press('Enter')
  await expect(page).toHaveURL(/\/documents$/)

  await page.getByRole('button', { name: 'Upload PDFs' }).first().click()
  const dialog = page.getByRole('dialog', { name: 'Add Documents' })
  await expect(dialog).toContainText('Destination: Global Inbox')
  await dialog.locator('input[type="file"]').setInputFiles({
    name: completionFileName,
    mimeType: 'application/pdf',
    buffer: Buffer.concat([sourcePdf, Buffer.from(completionSuffix)]),
  })
  await expect(dialog).toHaveCount(0)
  await expect(page.getByRole('button', { name: new RegExp(completionFileName.replace('.', '\\.')) })).toBeVisible()

  await page.goto('/inbox')
  await expect(page).toHaveURL(/\/documents$/)
  await expect(page.getByRole('button', { name: 'Upload PDFs' }).first()).toBeVisible()
})

test('Matter upload can cancel in flight and reselect the same file', async ({ page }) => {
  test.setTimeout(60_000)
  await login(page)
  await page.goto(`/matters/${uploadMatterId}?section=details`)
  await page.getByRole('link', { name: 'Open Workbench' }).click()
  await expect(page).toHaveURL(new RegExp(`/documents\\?matterId=${uploadMatterId}`))

  await page.getByRole('button', { name: 'Upload PDFs' }).first().click()
  const dialog = page.getByRole('dialog', { name: 'Add Documents' })
  await expect(dialog).toContainText('Destination: Aster upload acceptance')
  const input = dialog.locator('input[type="file"]')

  for (let attempt = 0; attempt < 2; attempt++) {
    let releaseTransfer: () => void = () => undefined
    let transferObserved = false
    const transferGate = new Promise<void>(resolve => { releaseTransfer = resolve })
    const holdTusCreation = async (route: Route) => {
      if (route.request().method() === 'POST') {
        transferObserved = true
        await transferGate
      }
      await route.continue().catch(() => undefined)
    }
    await page.route('**/storage/v1/upload/resumable**', holdTusCreation)

    await input.setInputFiles(cancellationFilePath)
    const cancel = dialog.getByRole('button', { name: 'Cancel', exact: true })
    await expect(cancel).toBeVisible()
    await expect.poll(() => transferObserved).toBe(true)
    await cancel.click()
    releaseTransfer()
    await expect(dialog.getByText(cancellationFileName, { exact: true })).toHaveCount(0)
    await page.unroute('**/storage/v1/upload/resumable**', holdTusCreation)
  }

  await expect(dialog.getByRole('button', { name: /Choose PDF files/ })).toBeVisible()
  await dialog.getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('button', { name: 'Upload PDFs' }).first()).toBeFocused()
})

test('320px dark keyboard surfaces preserve targets, overflow, actions, and scroll ownership', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 480 })
  await login(page)

  const theme = page.getByRole('button', { name: 'Toggle color theme' })
  await theme.focus()
  await theme.press('Enter')
  await expect(page.locator('html')).toHaveClass(/dark/)

  await page.goto(workbenchPath(sourceDocumentId, sourceVersionId, 3))
  await expect(page.getByText('PDF source · Version 1 · Page 3 of 4')).toBeVisible()
  await expectNoPageHorizontalOverflow(page)
  const backToMatter = page.getByRole('link', { name: 'Back to Matter' })
  await expectMinimumTarget(backToMatter)
  const workbenchScroller = page.getByText('PDF source · Version 1 · Page 3 of 4').locator('xpath=../../..')
  await expect(workbenchScroller).toHaveCSS('overflow-y', 'auto')
  const backTop = (await backToMatter.boundingBox())?.y
  await workbenchScroller.evaluate(element => { element.scrollTop = element.scrollHeight })
  expect(Math.abs(((await backToMatter.boundingBox())?.y ?? 0) - (backTop ?? 0))).toBeLessThan(1)

  await page.goto(`/matters/${matterId}?section=timeline&view=chronology`)
  await expectNoPageHorizontalOverflow(page)
  const filter = page.getByRole('button', { name: 'Filter', exact: true })
  await expectMinimumTarget(filter)
  await expect(page.locator('#matter-section-body')).toHaveCSS('overflow-y', 'hidden')
  const chronologyScroller = page.getByRole('list', { name: 'Proceeding chronology' })
  await expect(chronologyScroller).toHaveCSS('overflow-y', 'auto')
  const filterTop = (await filter.boundingBox())?.y
  await chronologyScroller.evaluate(element => { element.scrollTop = element.scrollHeight })
  expect(Math.abs(((await filter.boundingBox())?.y ?? 0) - (filterTop ?? 0))).toBeLessThan(1)

  await page.goto('/team')
  await expectNoPageHorizontalOverflow(page)
  const search = page.getByRole('button', { name: 'Search', exact: true })
  await expectMinimumTarget(search)
  const teamScroller = page.getByLabel('Team members list')
  await expect(teamScroller).toHaveCSS('overflow-y', 'auto')
  const searchTop = (await search.boundingBox())?.y
  await teamScroller.evaluate(element => { element.scrollTop = element.scrollHeight })
  expect(Math.abs(((await search.boundingBox())?.y ?? 0) - (searchTop ?? 0))).toBeLessThan(1)
})
