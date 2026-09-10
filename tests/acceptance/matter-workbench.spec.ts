import { expect, test } from '@playwright/test'

const matterId = 'd0010000-0000-0000-0000-000000000001'
const foreignMatterId = 'd0010000-0000-0000-0000-000000000002'

test('seeded owner opens an authorised Matter proceeding in the Workbench', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Email address').fill('owner@acceptance.test')
  await page.getByLabel('Password').fill('CaseChain-local-only-2026!')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)

  await page.goto(`/matters/${matterId}?view=chronology`)
  await expect(page.getByRole('heading', { name: 'Aster GST appeal' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Chronology' })).toBeVisible()
  await expect(page.getByRole('link', { name: /Order in Original/ })).toBeVisible()

  await page.getByRole('link', { name: /Order in Original/ }).click()
  await expect(page.getByRole('complementary', { name: 'Selected proceeding' })).toBeVisible()
  await page.getByRole('link', { name: 'Open document' }).click()

  await expect(page).toHaveURL(/\/documents\/e0010000-0000-0000-0000-000000000001/)
  await expect(page.getByRole('heading', { name: 'No file attached' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Back to Matter' })).toBeVisible()

  const foreignResponse = await page.goto(`/matters/${foreignMatterId}?view=chronology`)
  expect(foreignResponse?.status()).toBe(404)
})
