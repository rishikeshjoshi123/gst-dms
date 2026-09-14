import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir:'./tests/acceptance',testMatch:'manual-legal-deadlines.spec.ts',fullyParallel:false,workers:1,retries:0,timeout:60_000,expect:{timeout:15_000},outputDir:'/tmp/casechain-deadlines-playwright',reporter:[['line']],
  use:{baseURL:'http://127.0.0.1:3109',screenshot:'only-on-failure',trace:'retain-on-failure'},
  webServer:{command:`${process.execPath} scripts/acceptance/start-deadlines-server.mjs`,url:'http://127.0.0.1:3109/login',reuseExistingServer:false,timeout:180_000},
  projects:[{name:'chromium',use:{...devices['Desktop Chrome']}}],
})
