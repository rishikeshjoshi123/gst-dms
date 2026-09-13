import { expect, test, type Page } from '@playwright/test'
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { launchChromiumPageZoom } from './chromium-page-zoom'

const matter = 'd0010000-0000-0000-0000-000000000001'
const source = 'e0010000-0000-0000-0000-000000000001'
const target = 'e0010000-0000-0000-0000-000000000003'
function db(sql: string) {
  const workdir = process.env.RELATIONSHIP_AUTHORING_ACCEPTANCE_WORKDIR
  if (!workdir || !readFileSync(join(workdir, 'supabase/config.toml'), 'utf8').includes('project_id = "dms-relationship-authoring-155"')) throw new Error('Requires exclusively owned relationship acceptance project')
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_dms-relationship-authoring-155', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'], { input: sql, encoding: 'utf8' })
  if (result.status !== 0) throw new Error(result.stderr)
  return result.stdout.trim()
}
async function login(page: Page, role = 'owner') {
  await page.goto('/login')
  await page.getByLabel('Email address').fill(`${role}@acceptance.test`)
  await page.getByLabel('Password').fill('CaseChain-local-only-2026!')
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
}
async function noOverflow(page: Page) {
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
}
test('duplicate proceeding titles expose distinct record identities in selectors and confirmation', async ({ page }) => {
  const original = db(`SELECT json_agg(json_build_object('id',id,'title',display_title,'reference',reference_number)) FROM public.documents WHERE id IN ('${source}','${target}')`)
  try {
    db(`UPDATE public.documents SET display_title='Duplicate proceeding',reference_number=CASE WHEN id='${source}' THEN 'REF-155-SOURCE' ELSE NULL END WHERE id IN ('${source}','${target}')`)
    await login(page)
    await page.setViewportSize({ width: 320, height: 800 })
    await page.goto(`/matters/${matter}?view=chronology`)
    await page.getByRole('button', { name: 'Add relationship', exact: true }).click()
    await expect(page.getByLabel('1. Choose source document').locator(`option[value="${source}"]`)).toHaveText('Duplicate proceeding — Reference: REF-155-SOURCE')
    await page.getByLabel('1. Choose source document').selectOption(source)
    await expect(page.getByLabel('2. Choose target document').locator(`option[value="${target}"]`)).toHaveText('Duplicate proceeding — Record ID: …000000000003')
    await page.getByLabel('2. Choose target document').selectOption(target)
    await page.getByLabel('3. Choose relationship').selectOption('responds_to')
    await page.getByRole('button', { name: 'Review relationship', exact: true }).click()
    const confirmation = page.getByRole('dialog', { name: 'Add relationship?', exact: true })
    await expect(confirmation).toContainText('Source — Duplicate proceeding (Reference: REF-155-SOURCE). Target — Duplicate proceeding (Record ID: …000000000003).')
    await expect(confirmation).toContainText('Duplicate proceeding responds to Duplicate proceeding. Timeline progression: Duplicate proceeding answered by Duplicate proceeding.')
    await noOverflow(page)
    await page.keyboard.press('Escape')
  } finally {
    for (const row of JSON.parse(original) as { id: string; title: string; reference: string | null }[]) {
      db(`UPDATE public.documents SET display_title='${row.title.replaceAll("'", "''")}',reference_number=${row.reference === null ? 'NULL' : `'${row.reference.replaceAll("'", "''")}'`} WHERE id='${row.id}'`)
    }
  }
})
async function preview(page: Page) {
  await page.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect(page.getByLabel('2. Choose target document')).toBeDisabled()
  await page.getByLabel('1. Choose source document').selectOption(source)
  await expect(page.getByLabel('2. Choose target document').locator(`option[value="${source}"]`)).toHaveCount(0)
  await page.getByLabel('2. Choose target document').selectOption(target)
  await page.getByLabel('3. Choose relationship').selectOption('responds_to')
  await expect(page.getByText('Order in Original responds to Reply to Show Cause Notice', { exact: true })).toBeVisible()
  await expect(page.getByText('Reply to Show Cause Notice answered by Order in Original', { exact: true })).toBeVisible()
  await noOverflow(page)
  await expect(page.getByRole('dialog', { name: 'Add relationship', exact: true })).toHaveCSS('opacity', '1')
  await page.screenshot({ animations: 'disabled', path: test.info().outputPath(`authoring-${page.viewportSize()?.width}.png`) })
  await page.keyboard.press('Escape')
  await expect(page.getByRole('button', { name: 'Add relationship', exact: true })).toBeFocused()
}
test('chronology authoring remains usable at 320, 900 and true 200% zoom', async ({ page }) => {
  await login(page)
  await page.evaluate(() => localStorage.setItem('theme', 'dark'))
  db(`UPDATE public.documents SET display_title='${'Long proceeding identity '.repeat(8).trim()}' WHERE id='e0010000-0000-0000-0000-000000000004'`)
  for (const width of [320, 900]) {
    await page.setViewportSize({ width, height: 800 })
    await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' })
    await page.goto(`/matters/${matter}?view=chronology`)
    await preview(page)
    await page.getByRole('button', { name: 'Add relationship', exact: true }).click()
    await page.getByLabel('1. Choose source document').selectOption('e0010000-0000-0000-0000-000000000004')
    await noOverflow(page)
    await page.keyboard.press('Escape')
  }
  const zoom = await launchChromiumPageZoom('http://127.0.0.1:3105', { width: 1470, height: 900 })
  try {
    await login(zoom.page)
    await zoom.setZoom(2)
    await zoom.page.goto(`/matters/${matter}?view=chronology`)
    await preview(zoom.page)
  } finally { await zoom.close() }
})
test('Owner explicitly creates from graph and archives through the selected relationship inspector', async ({ page }) => {
  await login(page)
  await page.setViewportSize({ width: 1470, height: 900 })
  await page.goto(`/matters/${matter}?view=graph`)
  await expect(page.getByRole('heading', { name: 'Procedural timeline' })).toBeVisible()
  await page.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect(page.getByText('1. Choose the source document', { exact: false })).toBeVisible()
  await page.locator(`[data-authoring-document-id="${source}"] a`).focus()
  await page.keyboard.press('Enter')
  await expect(page.getByText('2. Choose the target document', { exact: false })).toBeVisible()
  await page.keyboard.press('Enter')
  await expect(page.getByText('Choose a different target document.', { exact: true })).toBeVisible()
  await page.locator(`[data-authoring-document-id="${target}"] a`).focus()
  await page.keyboard.press('Enter')
  await page.getByLabel('3. Choose relationship').selectOption('responds_to')
  await page.getByLabel('Reason (optional)').fill('Checked both procedural documents')
  db(`UPDATE public.documents SET display_title=display_title WHERE id='${source}'`)
  await page.getByRole('button', { name: 'Review relationship', exact: true }).click()
  const confirm = page.getByRole('dialog', { name: 'Add relationship?', exact: true })
  await expect(confirm).toContainText('Order in Original responds to Reply to Show Cause Notice')
  await expect(confirm).toContainText('Reply to Show Cause Notice answered by Order in Original')
  await expect(confirm).toHaveCSS('opacity', '1')
  await page.screenshot({ animations: 'disabled', path: test.info().outputPath('graph-confirmation.png') })
  await confirm.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect(confirm).toHaveCount(0)
  await expect(page.getByText('The selected record changed.', { exact: false })).toBeVisible()
  await expect(page.getByLabel('Reason (optional)')).toHaveValue('Checked both procedural documents')
  let lostResponse = false
  await page.route('**/matters/**', async route => {
    if (!lostResponse && route.request().method() === 'POST' && route.request().headers()['next-action'] && route.request().postData()?.includes('idempotencyKey')) {
      lostResponse = true
      await route.fetch()
      await route.abort('failed')
    } else await route.continue()
  })
  await page.getByRole('button', { name: 'Review relationship', exact: true }).click()
  await confirm.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect(page.getByText('The change could not be confirmed. Try again.', { exact: true })).toBeVisible()
  await expect(page.getByLabel('Reason (optional)')).toHaveValue('Checked both procedural documents')
  await page.getByRole('button', { name: 'Review relationship', exact: true }).click()
  await confirm.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect.poll(() => db(`SELECT count(*) FROM public.document_relationships WHERE matter_id='${matter}' AND relationship_type='responds_to' AND lifecycle_state='active'`)).toBe('1')
  await page.goto(`/matters/${matter}?view=graph&document=${source}&inspector=relationships`)
  const item = page.getByRole('complementary', { name: 'Selected proceeding' }).getByRole('listitem').filter({ hasText: 'Order in Original responds to Reply to Show Cause Notice' })
  await expect(item).toBeVisible()
  const sourceNode = page.locator(`.react-flow__node[data-id="${source}"]`)
  const position = await sourceNode.evaluate(element => (element as HTMLElement).style.transform)
  await item.getByRole('button', { name: 'Archive relationship', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Review archive', exact: true })).toBeDisabled()
  await page.getByLabel('Reason for archiving').fill('Confirmed obsolete procedural interpretation')
  await page.getByRole('button', { name: 'Review archive', exact: true }).click()
  await page.getByRole('dialog', { name: 'Archive relationship?', exact: true }).getByRole('button', { name: 'Archive relationship', exact: true }).click()
  await expect.poll(() => db(`SELECT lifecycle_state FROM public.document_relationships WHERE matter_id='${matter}' AND relationship_type='responds_to'`)).toBe('archived')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(item).toHaveCount(0)
  await expect(page.getByRole('complementary', { name: 'Selected proceeding' })).toBeFocused()
  await expect.poll(() => sourceNode.evaluate(element => (element as HTMLElement).style.transform)).toBe(position)
  expect(db(`SELECT lifecycle_state FROM public.document_relationships WHERE matter_id='${matter}' AND relationship_type='responds_to'`)).toBe('archived')
  expect(db(`SELECT count(*) FROM public.document_relationship_decisions WHERE matter_id='${matter}' AND relationship_type='responds_to'`)).toBe('2')
  expect(db(`SELECT count(*) FROM public.activity_events WHERE matter_id='${matter}' AND metadata->>'link_action' IN ('activate.responds_to','archive.responds_to')`)).toBe('2')
  await noOverflow(page)
})
test('Viewer has no relationship mutation controls', async ({ page }) => {
  await login(page, 'viewer')
  await page.goto(`/matters/${matter}?view=chronology&document=${source}&inspector=relationships`)
  await expect(page.getByRole('heading', { name: 'Chronology', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Add relationship', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Archive relationship', exact: true })).toHaveCount(0)
})

test('Associate can explicitly add a Timeline relationship from chronology', async ({ page }) => {
  await login(page, 'associate')
  await page.goto(`/matters/${matter}?view=chronology`)
  await page.getByRole('button', { name: 'Add relationship', exact: true }).click()
  await page.getByLabel('1. Choose source document').selectOption(source)
  await page.getByLabel('2. Choose target document').selectOption(target)
  await page.getByLabel('3. Choose relationship').selectOption('modifies')
  await page.getByRole('button', { name: 'Review relationship', exact: true }).click()
  await page.getByRole('dialog', { name: 'Add relationship?', exact: true }).getByRole('button', { name: 'Add relationship', exact: true }).click()
  await expect.poll(() => db(`SELECT count(*) FROM public.document_relationships WHERE matter_id='${matter}' AND relationship_type='modifies' AND lifecycle_state='active'`)).toBe('1')
  expect(db(`SELECT count(*) FROM public.document_relationship_decisions WHERE matter_id='${matter}' AND relationship_type='modifies' AND action='activate'`)).toBe('1')
  expect(db(`SELECT count(*) FROM public.activity_events WHERE matter_id='${matter}' AND metadata->>'link_action'='activate.modifies'`)).toBe('1')
})
