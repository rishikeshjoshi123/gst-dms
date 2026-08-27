import { createHash, randomBytes } from 'node:crypto'

export const hashInvitationOpaqueValue = (value: string) =>
  createHash('sha256').update(value).digest('hex')

export const createInvitationSelector = () => randomBytes(32).toString('base64url')

export const safeInternalRedirect = (value: string | null | undefined, fallback = '/dashboard') =>
  value?.startsWith('/') && !value.startsWith('//') ? value : fallback
