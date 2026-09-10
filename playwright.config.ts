import { defineConfig, devices } from '@playwright/test'

if (Number(process.versions.node.split('.')[0]) !== 24) {
  throw new Error(
    `Local acceptance requires Node 24 exactly; received ${process.versions.node} from ${process.execPath}.`,
  )
}

export default defineConfig({
  testDir: './tests/acceptance',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 8_000 },
  outputDir: '/tmp/casechain-playwright-results',
  reporter: [['line']],
  use: {
    baseURL: 'http://127.0.0.1:3100',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'node scripts/acceptance/start-server.mjs',
    url: 'http://127.0.0.1:3100/login',
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
})
