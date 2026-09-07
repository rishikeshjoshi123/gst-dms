import { defineConfig } from '@trigger.dev/sdk'

export default defineConfig({
  project: 'proj_ejbymoiwjvnqcuvlbohm',
  dirs: ['./src/trigger'],
  runtime: 'node-24',
  // 5 minutes — enough for PDF download + Vertex AI analysis + embedding + DB writes
  maxDuration: 300,
})
