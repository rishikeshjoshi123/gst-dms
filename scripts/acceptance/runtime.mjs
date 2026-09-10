import { fileURLToPath } from 'node:url'

const REQUIRED_NODE_MAJOR = 24

export function requireNode24({ version = process.versions.node, execPath = process.execPath } = {}) {
  const match = /^(\d+)\./.exec(version)
  const major = match ? Number(match[1]) : Number.NaN

  if (major !== REQUIRED_NODE_MAJOR) {
    throw new Error(
      `Local acceptance requires Node 24 exactly; received ${version} from ${execPath}.`,
    )
  }

  return execPath
}

export function acceptanceProjectPath(relativePath) {
  return fileURLToPath(new URL(`../../${relativePath}`, import.meta.url))
}

export function nodeModuleLaunch(modulePath, args = [], runtime) {
  return {
    command: requireNode24(runtime),
    args: [modulePath, ...args],
  }
}
