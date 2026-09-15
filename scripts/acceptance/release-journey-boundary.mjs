const loopbackHosts = new Set(['127.0.0.1', 'localhost'])

function exactOrigin(value, label) {
  const url = new URL(value)
  if (!loopbackHosts.has(url.hostname)) throw new Error(`Refusing non-loopback ${label}.`)
  return url.origin
}

export function validateVerificationUrl(value, { authOrigin, appOrigin }) {
  const expectedAuthOrigin = exactOrigin(authOrigin, 'Auth origin')
  const expectedAppOrigin = exactOrigin(appOrigin, 'application origin')
  const url = new URL(value)
  if (url.origin !== expectedAuthOrigin || url.pathname !== '/auth/v1/verify') {
    throw new Error('Captured verification URL has an unexpected local destination.')
  }
  const keys = [...url.searchParams.keys()].sort()
  if (keys.join(',') !== 'redirect_to,token,type' || !url.searchParams.get('token') || url.searchParams.get('type') !== 'signup') {
    throw new Error('Captured verification URL has an unexpected query contract.')
  }
  const redirect = new URL(url.searchParams.get('redirect_to'))
  if (redirect.origin !== expectedAppOrigin || redirect.pathname !== '/auth/callback' || redirect.searchParams.get('next') !== '/onboarding') {
    throw new Error('Captured verification URL has an unexpected callback destination.')
  }
  return url.toString()
}

export function validateCallbackLocation(value, { authOrigin, appOrigin }) {
  const expectedAuthOrigin = exactOrigin(authOrigin, 'Auth origin')
  const expectedAppOrigin = exactOrigin(appOrigin, 'application origin')
  const callback = new URL(value, expectedAuthOrigin)
  if (callback.origin !== expectedAppOrigin || callback.pathname !== '/auth/callback' ||
      callback.searchParams.get('next') !== '/onboarding' || !callback.searchParams.get('code')) {
    throw new Error('Auth verification returned an unexpected callback destination.')
  }
  return callback.toString()
}
