import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: './tests/acceptance', testMatch: 'document-attachment.spec.ts', fullyParallel: false, workers: 1, retries: 0,
  timeout: 60000, expect: { timeout: 15000 }, outputDir: '/tmp/casechain-attachment-playwright', reporter: [['line']],
  use: { baseURL: 'http://127.0.0.1:3104', screenshot: 'only-on-failure', trace: 'retain-on-failure' },
  webServer: { command: `${process.execPath} scripts/acceptance/start-attachment-server.mjs`, url: 'http://127.0.0.1:3104/login', reuseExistingServer: false, timeout: 120000 },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
