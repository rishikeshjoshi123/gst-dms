import type { Metadata } from 'next'
import Link from 'next/link'
import { Scale } from 'lucide-react'

export const metadata: Metadata = {
  title: 'Sign In',
}

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative min-h-screen flex items-center justify-center auth-grid-bg overflow-hidden">
      {/* Glow orbs */}
      <div className="auth-glow" style={{ top: '-100px', left: '-100px' }} />
      <div
        className="auth-glow"
        style={{
          bottom: '-100px',
          right: '-100px',
          background:
            'radial-gradient(circle, rgba(139,92,246,0.10) 0%, transparent 70%)',
        }}
      />

      <div className="relative w-full max-w-md mx-auto px-4 py-12">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2.5 justify-center mb-8">
          <span className="text-lg font-bold text-[--text-primary]">GST Litigation DMS</span>
        </Link>

        {/* Content card */}
        <div className="glass-card rounded-[--radius-xl] p-8 animate-fade-in">
          {children}
        </div>

        <p className="text-center text-xs text-[--text-muted] mt-6">
          Secure legal document management for GST proceedings
        </p>
      </div>
    </div>
  )
}
