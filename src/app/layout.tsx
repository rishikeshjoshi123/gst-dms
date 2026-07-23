import type { Metadata } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'

const inter = Inter({
  variable: '--font-inter',
  subsets: ['latin'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: {
    default: 'GST Litigation DMS',
    template: '%s — GST Litigation DMS',
  },
  description:
    'Manage GST litigation cases, chain legal documents into a visual timeline, and track proceedings with AI-powered extraction.',
  robots: 'noindex, nofollow', // private enterprise app
}

import { ThemeProvider } from '@/components/theme-provider'
import { Toaster } from 'sonner'

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${inter.variable} h-full`} suppressHydrationWarning>
      <body className="min-h-full flex flex-col antialiased">
        <ThemeProvider
          attribute="class"
          defaultTheme="light"
          enableSystem={true}
          disableTransitionOnChange
        >
          {children}
          <Toaster 
            position="top-right" 
            richColors 
            closeButton 
            toastOptions={{
              className: 'font-sans shadow-lg border rounded-lg',
            }}
          />
        </ThemeProvider>
      </body>
    </html>
  )
}
