import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { chromium, type BrowserContext, type Page } from '@playwright/test'

const messageType = 'casechain-acceptance-page-zoom'

export type ChromiumPageZoom = {
  context: BrowserContext
  page: Page
  setZoom: (factor: number) => Promise<void>
  close: () => Promise<void>
}

/**
 * Chrome handles browser page zoom above renderer input dispatch, so headless
 * key events cannot exercise it. This disposable extension uses Chromium's
 * tabs.setZoom API and lets the acceptance suite assert real page zoom rather
 * than substituting viewport resizing or pinch zoom.
 */
export async function launchChromiumPageZoom(
  baseURL: string,
  viewport: { width: number; height: number },
): Promise<ChromiumPageZoom> {
  const root = await mkdtemp(join(tmpdir(), 'casechain-graph-page-zoom-'))
  const extension = join(root, 'extension')
  const localUrl = new URL(baseURL)
  const extensionMatch = `${localUrl.protocol}//${localUrl.hostname}/*`
  await mkdir(extension)
  await Promise.all([
    writeFile(join(extension, 'manifest.json'), JSON.stringify({
      manifest_version: 3,
      name: 'CaseChain acceptance page zoom',
      version: '1.0.0',
      permissions: ['tabs'],
      background: { service_worker: 'worker.js' },
      content_scripts: [{
        matches: [extensionMatch],
        js: ['content.js'],
        run_at: 'document_start',
      }],
    })),
    writeFile(join(extension, 'content.js'), `
      window.addEventListener('message', (event) => {
        if (event.source !== window || event.data?.type !== '${messageType}') return
        chrome.runtime.sendMessage({ zoom: event.data.zoom })
      })
    `),
    writeFile(join(extension, 'worker.js'), `
      chrome.runtime.onMessage.addListener((message, sender) => {
        if (!sender.tab?.id || typeof message.zoom !== 'number') return
        chrome.tabs.setZoom(sender.tab.id, message.zoom)
      })
    `),
  ])

  let context: BrowserContext
  try {
    context = await chromium.launchPersistentContext(join(root, 'profile'), {
      baseURL,
      channel: 'chromium',
      headless: true,
      viewport,
      args: [
        `--disable-extensions-except=${extension}`,
        `--load-extension=${extension}`,
      ],
    })
  } catch (error) {
    await rm(root, { force: true, recursive: true })
    throw error
  }

  const page = context.pages()[0] ?? await context.newPage()
  return {
    context,
    page,
    setZoom: async (factor) => {
      await page.evaluate(({ type, zoom }) => {
        window.postMessage({ type, zoom }, '*')
      }, { type: messageType, zoom: factor })
    },
    close: async () => {
      await context.close()
      await rm(root, { force: true, recursive: true })
    },
  }
}
