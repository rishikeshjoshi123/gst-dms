import { defineConfig, devices } from '@playwright/test'

if (Number(process.versions.node.split('.')[0]) !== 24) {
  throw new Error(`Local acceptance requires Node 24 exactly; received ${process.versions.node}.`)
}

export default defineConfig({
  testDir: './tests/acceptance',
  testMatch: 'release-journey.spec.ts',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 420_000,
  expect: { timeout: 15_000 },
  outputDir: '/tmp/casechain-release-journey-playwright',
  reporter: [['line']],
  use: {
    baseURL: 'http://127.0.0.1:3113',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: `${process.execPath} scripts/acceptance/start-release-journey-server.mjs`,
    url: 'http://127.0.0.1:3113/login',
    reuseExistingServer: false,
    timeout: 240_000,
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
