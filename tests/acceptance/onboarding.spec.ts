import { expect, test, type APIRequestContext, type Page } from '@playwright/test'

const capturedMailUrl = process.env.ONBOARDING_INBUCKET_URL
if (!capturedMailUrl || !['127.0.0.1', 'localhost'].includes(new URL(capturedMailUrl).hostname)) {
  throw new Error('A loopback captured-mail URL is required for onboarding acceptance.')
}

async function signUp(page: Page, details: { name: string; email: string }) {
  await page.goto('/signup')
  await page.getByLabel('Full name').fill(details.name)
  await page.getByLabel('Work email').fill(details.email)
  await page.getByLabel(/^Password/).fill('Acceptance-pass-2026')
  await page.getByLabel('Confirm password').fill('Acceptance-pass-2026')
  await page.getByRole('button', { name: 'Create account' }).click()
  await expect(page.getByRole('status')).toContainText('check your email')
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
    const message = messages.find((candidate) =>
      JSON.stringify(candidate).toLowerCase().includes(email.toLowerCase()),
    )
    const messageId = message?.id ?? message?.ID
    if (!messageId) return null
    const detail = await request.get(`${capturedMailUrl}${detailPath}${encodeURIComponent(String(messageId))}`)
    if (!detail.ok()) return null
    const content = collectStrings(await detail.json())
      .join('\n')
      .replaceAll('&amp;', '&')
      .replaceAll('=3D', '=')
      .replace(/=\r?\n/g, '')
    found = content.match(/https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/)?.[0] ?? null
    return found
  }, { timeout: 15_000, message: `verification mail for ${email}` }).not.toBeNull()
  if (!found) throw new Error(`Captured verification message for ${email} had no verification URL.`)
  return found
}

async function confirmEmail(page: Page, request: APIRequestContext, email: string) {
  const response = await request.get(await verificationLink(request, email), { maxRedirects: 0 })
  expect([302, 303]).toContain(response.status())
  const destination = new URL(response.headers().location, capturedMailUrl)
  expect(destination.hostname).toBe('127.0.0.1')
  expect(destination.port).toBe('3200')
  expect(destination.pathname).toBe('/auth/callback')
  expect(destination.searchParams.has('code')).toBe(true)
  await page.goto(destination.toString())
  expect(`${new URL(page.url()).pathname}${new URL(page.url()).search}`).toBe('/onboarding')
}

test.describe.serial('normal confirmation-required onboarding', () => {
  test('verified signup with no invitations creates a complete organisation', async ({ page, request }) => {
    await signUp(page, { name: 'Browser Creator', email: 'create-browser@onboarding.test' })
    await confirmEmail(page, request, 'create-browser@onboarding.test')
    await expect(page.getByRole('heading', { name: 'Set up your workspace' })).toBeVisible()
    await expect(page.getByText('No pending invitations')).toBeVisible()
    const creationKey = page.locator('input[name="idempotency_key"]')
    await expect(creationKey).toHaveValue(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
    const stableCreationKey = await creationKey.inputValue()
    await page.getByLabel('Organisation name').fill('Browser-created organisation')
    await expect(creationKey).toHaveValue(stableCreationKey)
    await page.getByRole('button', { name: 'Create organisation' }).click()
    await expect(page).toHaveURL(/\/dashboard$/)
  })

  test('multiple pending invitations remain explicit and one can be accepted on a narrow dark viewport', async ({ page, request }) => {
    await page.setViewportSize({ width: 320, height: 720 })
    await page.emulateMedia({ colorScheme: 'dark' })
    await signUp(page, { name: 'Browser Joiner', email: 'join-browser@onboarding.test' })
    await confirmEmail(page, request, 'join-browser@onboarding.test')

    await expect(page.getByRole('heading', { name: 'Pending invitations' })).toBeVisible()
    await expect(page.getByText('Bengaluru Indirect Tax Chambers')).toBeVisible()
    await expect(page.getByText(/A very long invited organisation name/)).toBeVisible()
    await expect(page.getByRole('button', { name: 'Create organisation' })).toBeVisible()
    await expect(page.getByText(/expired/i)).toHaveCount(0)
    await expect(page.getByText(/revoked/i)).toHaveCount(0)
    await expect(page.getByText(/foreign-browser/i)).toHaveCount(0)

    const accepts = page.getByRole('button', { name: 'Accept invitation' })
    await expect(accepts).toHaveCount(2)
    const target = accepts.first()
    const box = await target.boundingBox()
    expect(box).not.toBeNull()
    const pseudo = await target.evaluate((element) => {
      const style = getComputedStyle(element, '::before')
      return { width: Number.parseFloat(style.width), height: Number.parseFloat(style.height) }
    })
    expect(Math.max(box?.width ?? 0, pseudo.width || 0)).toBeGreaterThanOrEqual(43.9)
    expect(Math.max(box?.height ?? 0, pseudo.height || 0)).toBeGreaterThanOrEqual(43.9)
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(overflow).toBeLessThanOrEqual(1)

    await page.keyboard.press('Home')
    await target.focus()
    await expect(target).toBeFocused()
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/dashboard$/)
  })
})
