import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: './tests/acceptance', testMatch: 'review-workspace.spec.ts', fullyParallel: false, workers: 1, retries: 0,
  timeout: 60000, expect: { timeout: 15000 }, outputDir: '/tmp/casechain-review-playwright', reporter: [['line']],
  use: { baseURL: 'http://127.0.0.1:3103', screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  webServer: { command: `${process.execPath} scripts/acceptance/start-review-server.mjs`, url: 'http://127.0.0.1:3103/login', reuseExistingServer: false, timeout: 120000 },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
