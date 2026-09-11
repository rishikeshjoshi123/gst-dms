import { defineConfig, devices } from '@playwright/test'

if (Number(process.versions.node.split('.')[0]) !== 24) {
  throw new Error(`Local acceptance requires Node 24 exactly; received ${process.versions.node}.`)
}

const appUrl = process.env.ONBOARDING_APP_URL ?? 'http://127.0.0.1:3200'

export default defineConfig({
  testDir: './tests/acceptance',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  outputDir: '/tmp/casechain-onboarding-playwright-results',
  reporter: [['line']],
  use: {
    baseURL: appUrl,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: `"${process.execPath}" scripts/acceptance/start-onboarding-server.mjs`,
    url: `${appUrl}/login`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
})
