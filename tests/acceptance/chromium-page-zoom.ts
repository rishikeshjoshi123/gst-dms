import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

import { chromium, type BrowserContext, type Page } from '@playwright/test'

const messageType = 'casechain-acceptance-page-zoom'

export async function closeChromiumPageZoom(context: Pick<BrowserContext, 'close'>, root: string) {
  let closeError: unknown
  let removeError: unknown
  try {
    await context.close()
  } catch (error) {
    closeError = error
  } finally {
    try {
      await rm(root, { force: true, recursive: true })
    } catch (error) {
      removeError = error
    }
  }
  if (closeError !== undefined && removeError !== undefined) {
    throw new AggregateError([closeError, removeError], 'Chromium page-zoom context and temporary-root cleanup both failed.')
  }
  if (closeError !== undefined) throw closeError
  if (removeError !== undefined) throw removeError
}

async function removeRootAfterFailure(root: string, context: BrowserContext | null, primaryError: unknown): Promise<never> {
  const cleanupErrors: unknown[] = []
  try {
    if (context) {
      try {
        await context.close()
      } catch (error) {
        cleanupErrors.push(error)
      }
    }
  } finally {
    try {
      await rm(root, { force: true, recursive: true })
    } catch (error) {
      cleanupErrors.push(error)
    }
  }
  if (cleanupErrors.length > 0) {
    throw new AggregateError(
      [primaryError, ...cleanupErrors],
      'Chromium page-zoom setup failed and its cleanup was incomplete.',
    )
  }
  throw primaryError
}

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
  let context: BrowserContext | null = null
  try {
    const extension = join(root, 'extension')
    const localUrl = new URL(baseURL)
    const expectedOrigin = localUrl.origin
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
        const expectedOrigin = ${JSON.stringify(expectedOrigin)}
        window.addEventListener('message', (event) => {
          if (window.location.origin !== expectedOrigin || event.origin !== expectedOrigin) return
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
    const page = context.pages()[0] ?? await context.newPage()
    const launchedContext = context
    return {
      context: launchedContext,
      page,
      setZoom: async (factor) => {
        await page.evaluate(({ origin, type, zoom }) => {
          window.postMessage({ type, zoom }, origin)
        }, { origin: expectedOrigin, type: messageType, zoom: factor })
      },
      close: () => closeChromiumPageZoom(launchedContext, root),
    }
  } catch (error) {
    return removeRootAfterFailure(root, context, error)
  }
}
