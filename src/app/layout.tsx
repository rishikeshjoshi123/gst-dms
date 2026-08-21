import type { Metadata } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import './globals.css'

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
  display: 'swap',
})

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: {
    default: 'CaseChain — GST Litigation DMS',
    template: '%s — CaseChain',
  },
  description:
    'Manage GST litigation cases, chain legal documents into a visual timeline, and track proceedings with AI-powered extraction.',
  robots: 'noindex, nofollow',
  icons: {
    icon: '/icon.svg',
    shortcut: '/icon.svg',
    apple: '/icon.svg',
  },
}

import { ThemeProvider } from '@/components/theme-provider'
import { Toaster } from 'sonner'

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} h-full`} suppressHydrationWarning>
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
