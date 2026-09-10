import { expect, test, type Page } from '@playwright/test'

const password = 'CaseChain-local-only-2026!'
const matterId = 'd0010000-0000-0000-0000-000000000001'
const foreignMatterId = 'd0010000-0000-0000-0000-000000000002'
const sourceDocumentId = 'e0010000-0000-0000-0000-000000000001'
const sourceVersionId = 'f1010000-0000-0000-0000-000000000001'
const missingDocumentId = 'e0010000-0000-0000-0000-000000000004'
const missingVersionId = 'f1010000-0000-0000-0000-000000000002'

async function login(page: Page, email = 'owner@acceptance.test') {
  await page.goto('/login')
  await page.getByLabel('Email address').fill(email)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
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
