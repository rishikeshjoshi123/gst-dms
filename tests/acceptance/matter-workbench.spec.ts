import { mkdtemp, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { expect, test, type Locator, type Page, type Request, type Route } from '@playwright/test'

import { closeChromiumPageZoom, launchChromiumPageZoom } from './chromium-page-zoom'

const password = 'CaseChain-local-only-2026!'
const matterId = 'd0010000-0000-0000-0000-000000000001'
const uploadMatterId = 'd0020000-0000-4000-8000-000000000001'
const foreignMatterId = 'd0010000-0000-0000-0000-000000000002'
const sourceDocumentId = 'e0010000-0000-0000-0000-000000000001'
const sourceVersionId = 'f1010000-0000-0000-0000-000000000001'
const missingDocumentId = 'e0010000-0000-0000-0000-000000000004'
const missingVersionId = 'f1010000-0000-0000-0000-000000000002'
const graphSourceDocumentId = 'e0010000-0000-0000-0000-000000000001'
const graphTargetDocumentId = 'e0010000-0000-0000-0000-000000000003'
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

function observeServerActions(page: Page) {
  const requests: Request[] = []
  const listener = (request: Request) => {
    if (request.method() === 'POST' && request.headers()['next-action']) requests.push(request)
  }
  page.on('request', listener)
  return {
    count: () => requests.length,
    stop: () => page.off('request', listener),
  }
}

async function expectDesktopGraph(page: Page) {
  await expect(page.getByRole('heading', { name: 'Procedural timeline' })).toBeVisible({ timeout: 15_000 })
  return page.getByLabel('Procedural timeline graph')
}

test('Chromium page zoom helper cleans failed setup and failed context close', async () => {
  const zoomRoots = async () => (await readdir(tmpdir()))
    .filter(name => name.startsWith('casechain-graph-page-zoom-'))
    .sort()
  const rootsBeforeInvalidSetup = await zoomRoots()
  await expect(launchChromiumPageZoom('not a valid URL', { width: 1470, height: 751 })).rejects.toThrow()
  expect(await zoomRoots()).toEqual(rootsBeforeInvalidSetup)

  const root = await mkdtemp(join(tmpdir(), 'casechain-graph-page-zoom-close-test-'))
  const closeError = new Error('synthetic context close failure')
  await expect(closeChromiumPageZoom({ close: async () => { throw closeError } }, root)).rejects.toBe(closeError)
  await expect(stat(root)).rejects.toMatchObject({ code: 'ENOENT' })
})

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

test('Matter graph renders the governed relationship with accessible keyboard and pane behavior', async ({ page }) => {
  test.setTimeout(60_000)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await login(page)

  const graphStartedAt = performance.now()
  await page.goto(`/matters/${matterId}?section=timeline&view=graph`)
  const graph = await expectDesktopGraph(page)
  const graphReadyMs = Math.round(performance.now() - graphStartedAt)
  console.log(`[local graph timing] cold route-to-graph ${graphReadyMs}ms`)
  expect(graphReadyMs).toBeLessThan(15_000)

  await expect(page.locator('html')).not.toHaveClass(/dark/)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()
  await expect(page.getByText('Unlinked lane · 1 proceeding', { exact: true })).toBeVisible()
  await expect(page.locator('.react-flow__node')).toHaveCount(3)
  const nodeGeometry = await page.locator('.react-flow__node').evaluateAll(nodes => nodes.map(node => {
    const box = node.getBoundingClientRect()
    return { width: box.width, height: box.height }
  }))
  for (const box of nodeGeometry) {
    expect(box.width).toBeCloseTo(184, 1)
    expect(box.height).toBeCloseTo(120, 1)
  }
  await expect(page.locator(`[id="matter-timeline-row-${missingDocumentId}"]`).locator('..')).toHaveAttribute('data-unlinked', 'true')
  await expectNoPageHorizontalOverflow(page)
  await expect(page.locator('#matter-section-body')).toHaveCSS('overflow-y', 'hidden')
  await expect(graph).toHaveCSS('overflow-x', 'hidden')
  await expect.poll(() => page.evaluate(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)).toBe(true)
  const animationNames = await graph.locator('.react-flow__node, .react-flow__edge').evaluateAll(elements => (
    elements.map(element => getComputedStyle(element).animationName)
  ))
  expect(animationNames.every(name => name === 'none')).toBe(true)

  const orderNode = page.getByRole('link', { name: /Order in Original/ })
  const interactionStartedAt = performance.now()
  await orderNode.focus()
  await orderNode.press('Enter')
  const inspector = page.getByRole('complementary', { name: 'Selected proceeding' })
  await expect(inspector).toBeVisible()
  const interactionMs = Math.round(performance.now() - interactionStartedAt)
  console.log(`[local graph timing] keyboard-node-to-inspector ${interactionMs}ms`)
  expect(interactionMs).toBeLessThan(4_000)
  await expect(page).toHaveURL(new RegExp(`document=${graphSourceDocumentId}`))
  const inspectorScroller = inspector.locator('.custom-scrollbar')
  await expect(inspectorScroller).toHaveCSS('overflow-y', 'auto')
  const inspectorHeadingTop = (await inspector.getByText('Selected proceeding', { exact: true }).boundingBox())?.y
  const inspectorScroll = await inspectorScroller.evaluate(element => {
    element.scrollTop = element.scrollHeight
    return { clientHeight: element.clientHeight, scrollHeight: element.scrollHeight, scrollTop: element.scrollTop }
  })
  expect(inspectorScroll.scrollHeight).toBeGreaterThan(inspectorScroll.clientHeight)
  expect(inspectorScroll.scrollTop).toBeGreaterThan(0)
  expect(Math.abs(((await inspector.getByText('Selected proceeding', { exact: true }).boundingBox())?.y ?? 0) - (inspectorHeadingTop ?? 0))).toBeLessThan(1)
  await inspector.getByRole('link', { name: 'Close' }).click()
  await expect(inspector).toHaveCount(0)
  await expect(orderNode).toBeFocused()

  const relationshipSummary = page.locator('summary').filter({ hasText: 'Relationship list (1)' })
  await relationshipSummary.focus()
  await relationshipSummary.press('Enter')
  const relationshipList = page.getByRole('list', { name: 'Timeline relationships' })
  const relationshipLink = relationshipList.getByRole('link', { name: /Order in Original is issued pursuant to Reply to Show Cause Notice/ })
  await expect(relationshipLink).toBeVisible()
  await relationshipLink.press('Enter')
  await expect(inspector).toBeVisible()
  await expect(inspector).toContainText('Order in Original is issued pursuant to Reply to Show Cause Notice.')
  await expect(inspector).toContainText('Reply to Show Cause Notice results in Order in Original.')

  const theme = page.getByRole('button', { name: 'Toggle color theme' })
  await theme.click()
  await expect(page.locator('html')).toHaveClass(/dark/)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()
})

test('Matter graph filter and view state survive Back and Forward without reconnecting a hidden endpoint', async ({ page }) => {
  test.setTimeout(60_000)
  await login(page)
  await page.goto(`/matters/${matterId}?section=timeline&view=graph`)
  const graph = await expectDesktopGraph(page)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()

  await page.getByRole('link', { name: 'Chronology' }).click()
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  await expect(page).toHaveURL(/view=chronology/)
  await page.getByRole('link', { name: 'Graph' }).click()
  await expectDesktopGraph(page)
  await expect(page).toHaveURL(/view=graph/)

  await page.getByRole('button', { name: 'Filter', exact: true }).click()
  await page.getByLabel('Title or reference').fill('Reply to Show Cause Notice')
  await page.getByRole('button', { name: 'Apply filters' }).click()
  await expectDesktopGraph(page)
  await expect(page.getByText('Showing 1 of 3 proceedings', { exact: true })).toBeVisible()
  await expect(page.locator('.react-flow__node')).toHaveCount(1)
  await expect(page.locator(`#matter-timeline-row-${graphTargetDocumentId}`)).toBeVisible()
  await expect(graph.getByText('results in', { exact: true })).toHaveCount(0)
  await expect(page.locator('summary').filter({ hasText: 'Relationship list (0)' })).toBeVisible()

  await page.goBack()
  await expectDesktopGraph(page)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()
  await expect(page.locator('.react-flow__node')).toHaveCount(3)
  await page.goBack()
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  await expect(page).toHaveURL(/view=chronology/)
  await page.goForward()
  await expectDesktopGraph(page)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()
  await page.goForward()
  await expectDesktopGraph(page)
  await expect(page.locator('.react-flow__node')).toHaveCount(1)
  await expect(graph.getByText('results in', { exact: true })).toHaveCount(0)
})

test('constrained Timeline avoids graph requests, Viewer can read it, and Chromium 200% page zoom reflows to chronology', async ({ page, baseURL }) => {
  test.setTimeout(90_000)
  await page.setViewportSize({ width: 320, height: 480 })
  await login(page)
  const actions = observeServerActions(page)
  await page.goto(`/matters/${matterId}?section=timeline&view=graph`)
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Procedural timeline' })).toHaveCount(0)
  await expect(page.getByRole('link', { name: 'Graph' })).toHaveCount(0)
  await page.waitForTimeout(750)
  expect(actions.count()).toBe(0)
  await expectNoPageHorizontalOverflow(page)

  await page.setViewportSize({ width: 900, height: 751 })
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  await page.waitForTimeout(750)
  expect(actions.count()).toBe(0)
  await expectNoPageHorizontalOverflow(page)
  actions.stop()

  await page.context().clearCookies()
  await page.setViewportSize({ width: 1470, height: 751 })
  await login(page, 'viewer@acceptance.test')
  await page.goto(`/matters/${matterId}?section=timeline&view=graph`)
  const graph = await expectDesktopGraph(page)
  await expect(graph.getByText('results in', { exact: true })).toBeVisible()

  const zoomBrowser = await launchChromiumPageZoom(baseURL ?? 'http://127.0.0.1:3100', { width: 1470, height: 751 })
  try {
    await login(zoomBrowser.page, 'viewer@acceptance.test')
    await zoomBrowser.page.goto(`/matters/${matterId}?section=timeline&view=graph`)
    await expectDesktopGraph(zoomBrowser.page)
    const beforeZoom = await zoomBrowser.page.evaluate(() => ({
      devicePixelRatio,
      innerWidth,
      visualScale: window.visualViewport?.scale ?? null,
    }))
    await zoomBrowser.setZoom(2)
    await expect.poll(() => zoomBrowser.page.evaluate(() => window.innerWidth), { timeout: 5_000 }).toBeLessThan(1024)
    const afterZoom = await zoomBrowser.page.evaluate(() => ({
      devicePixelRatio,
      innerWidth,
      visualScale: window.visualViewport?.scale ?? null,
    }))
    console.log(`[local graph timing] Chromium 200% page zoom innerWidth ${beforeZoom.innerWidth}px -> ${afterZoom.innerWidth}px`)
    expect(afterZoom.devicePixelRatio).toBeCloseTo(beforeZoom.devicePixelRatio * 2, 5)
    expect(afterZoom.visualScale).toBe(beforeZoom.visualScale)
    await expect(zoomBrowser.page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
    await expect(zoomBrowser.page.getByRole('heading', { name: 'Procedural timeline' })).toHaveCount(0)
    await expectNoPageHorizontalOverflow(zoomBrowser.page)
  } finally {
    await zoomBrowser.close()
  }
})

test('Team owner sees suspended members and authorised emails', async ({ page }) => {
  await login(page)
  await page.goto('/team')

  await expect(page.getByText('5 members')).toBeVisible()
  await page.getByRole('button', { name: /Suspended Associate/ }).click()
  const details = page.getByRole('complementary', { name: 'Member details' })
  await expect(details).toContainText('suspended@acceptance.test')
  await expect(details).toContainText('Suspended')
})

test('Team Viewer sees active peers but only their own email', async ({ page }) => {
  await login(page, 'viewer@acceptance.test')
  await page.goto('/team')

  await expect(page.getByText('4 members')).toBeVisible()
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

test('Document Hub defaults to My uploads, allows Associate shared Intake, and hides Intake from Viewer', async ({ page }) => {
  await login(page, 'associate@acceptance.test')
  await page.goto('/documents')
  await expect(page.getByRole('button', { name: 'My uploads' })).toHaveAttribute('aria-pressed', 'true')
  await expect(page.getByRole('button', { name: /owner-shared-intake\.pdf/ })).toHaveCount(0)
  await page.getByRole('button', { name: 'All uploads' }).click()
  const sharedOwnerUpload = page.getByRole('button', { name: /owner-shared-intake\.pdf/ })
  await expect(sharedOwnerUpload).toBeVisible()
  await expect(page.getByRole('cell', { name: 'Acceptance Owner' })).toBeVisible()
  await sharedOwnerUpload.click()
  const sharedDetails = page.getByRole('complementary', { name: /Details for owner-shared-intake\.pdf/ })
  await expect(sharedDetails).toContainText('Uploaded by')
  await expect(sharedDetails).toContainText('Acceptance Owner')
  await expect(sharedDetails).not.toContainText('Uploaded by You')
  await sharedDetails.getByRole('button', { name: 'View original PDF' }).click()
  const sharedSource = page.getByRole('region', { name: 'Original PDF for owner-shared-intake.pdf' })
  await expect(sharedSource).toBeVisible()
  await expect(sharedSource.locator('[data-pdf-page="1"] canvas')).toBeVisible()
  await sharedSource.getByRole('button', { name: 'Close PDF' }).click()
  await expect(page.getByRole('button', { name: 'All uploads' })).toHaveAttribute('aria-pressed', 'true')
  await expect(sharedOwnerUpload).toBeVisible()
  await expect(page.getByRole('heading', { name: /No uploads/ })).toHaveCount(0)

  await page.context().clearCookies()
  await login(page, 'viewer@acceptance.test')
  await page.goto('/documents')
  await expect(page.getByRole('heading', { name: 'Document intake is not available' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'My uploads' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'All uploads' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Upload PDFs' })).toHaveCount(0)
  await expect(page.getByLabel('Search document queue')).toHaveCount(0)
  await expect(page.getByRole('button', { name: /owner-shared-intake\.pdf/ })).toHaveCount(0)
  await expect(page.locator('body')).not.toContainText('orgs/b0010000')
})

test('ready global Intake assignment opens the server-returned exact Workbench source and its Matter', async ({ page }) => {
  await login(page)
  await page.goto('/documents')

  const upload = page.getByRole('button', { name: /owner-shared-intake\.pdf/ })
  await expect(upload).toBeVisible()
  await upload.click()
  const details = page.getByRole('complementary', { name: /Details for owner-shared-intake\.pdf/ })
  await details.getByRole('tab', { name: 'Placement' }).click()
  await details.getByRole('textbox', { name: 'Matter', exact: true }).fill('Aster GST appeal')
  await details.getByRole('option', { name: /Aster GST appeal/ }).click()
  await details.getByRole('button', { name: 'Assign document' }).click()

  await expect(page).toHaveURL(new RegExp(`/documents/[0-9a-f-]+\\?matterId=${matterId}&version=[0-9a-f-]+&page=1`))
  await expect(page.getByText('PDF source · Version 1 · Page 1 of 4')).toBeVisible()
  await expect(page.locator('[data-pdf-page="1"] canvas')).toBeVisible()
  await page.getByRole('link', { name: 'Back to Matter' }).click()
  await expect(page).toHaveURL(new RegExp(`/matters/${matterId}`))
  await expect(page.getByRole('heading', { name: 'Aster GST appeal' })).toBeVisible()
})

test('Trash shows final-seven-day time and restricted blocked status without Dashboard attention', async ({ page }) => {
  await login(page)
  await expect(page.locator('body')).not.toContainText('Team attention')
  await page.goto('/trash')
  await expect(page.getByText(/Permanent deletion in 6 days/).first()).toBeVisible()
  await expect(page.getByText(/Permanent deletion blocked · 1 blocker/).first()).toBeVisible()
  await expectNoPageHorizontalOverflow(page)

  await page.context().clearCookies()
  await login(page, 'viewer@acceptance.test')
  await page.goto('/trash')
  await expect(page.getByText('Blocked retention fixture')).toHaveCount(0)
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

  await page.goto('/trash')
  await expectNoPageHorizontalOverflow(page)
  const finalWindow = page.getByRole('button', { name: /View details for Final-window retention fixture/ })
  await expectMinimumTarget(finalWindow)
  await finalWindow.focus()
  await finalWindow.press('Enter')
  const trashDetails = page.getByRole('complementary', { name: /Trash details/ })
  await expect(trashDetails).toBeVisible()
  await expect(trashDetails).toContainText(/Permanent deletion in 6 days/)
})
