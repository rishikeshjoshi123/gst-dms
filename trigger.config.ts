import { defineConfig } from '@trigger.dev/sdk/v3'

export default defineConfig({
  project: 'proj_ejbymoiwjvnqcuvlbohm',
  dirs: ['./src/trigger'],
  // 5 minutes — enough for PDF download + Vertex AI analysis + embedding + DB writes
  maxDuration: 300,
})
