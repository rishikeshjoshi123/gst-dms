'use client'

import * as React from 'react'
import { ThemeProvider as NextThemesProvider } from 'next-themes'

export function ThemeProvider({
  children,
  scriptProps,
  ...props
}: React.ComponentProps<typeof NextThemesProvider>) {
  return (
    <NextThemesProvider
      {...props}
      // next-themes injects an inline pre-hydration script. React 19 warns (and
      // Next's dev overlay treats it as an error) if that script is rendered
      // again on the client. This is the compatibility pattern documented by
      // Next: executable on the server, inert during client rendering.
      scriptProps={{
        ...scriptProps,
        type: typeof window === 'undefined' ? 'text/javascript' : 'text/plain',
      }}
    >
      {children}
    </NextThemesProvider>
  )
}
