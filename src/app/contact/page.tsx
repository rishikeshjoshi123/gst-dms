'use client'

import { useState } from 'react'
import Link from 'next/link'
import { Link2, Mail, Phone, MapPin, ArrowLeft, Send, User, Briefcase } from 'lucide-react'
import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { toast } from 'sonner'

export default function ContactPage() {
  const [formState, setFormState] = useState({ name: '', email: '', message: '' })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    toast.info('Contact form coming soon — reach out directly via email or phone for now.')
  }

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--text-primary)] font-sans">
      {/* Mesh gradient background */}
      <div className="fixed inset-0 z-0 mesh-gradient-bg pointer-events-none" />

      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-5 max-w-7xl mx-auto">
        <Link href="/" className="flex items-center gap-2 group">
          <span className="text-xl font-bold tracking-tight text-[var(--text-primary)]">
            CaseChain
          </span>
          <span className="text-[10px] font-mono text-[var(--text-muted)] border border-[var(--border-strong)] rounded px-1.5 py-0.5 leading-none">
            working title
          </span>
        </Link>
        <div className="flex items-center gap-3">
          <ThemeToggle />
          <Link href="/" className="flex items-center gap-1.5 text-sm font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors">
            <ArrowLeft size={14} />
            Back
          </Link>
        </div>
      </nav>

      {/* Hero */}
      <section className="relative z-10 max-w-7xl mx-auto px-6 pt-12 pb-6 text-center">
        <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4 text-[var(--text-primary)]">
          Get in Touch
        </h1>
        <p className="text-[var(--text-secondary)] max-w-lg mx-auto text-base">
          Have questions about CaseChain? Want to discuss how it can help your practice? We&apos;d love to hear from you.
        </p>
      </section>

      {/* Content Grid */}
      <section className="relative z-10 max-w-5xl mx-auto px-6 py-12">
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-8">

          {/* Left — Founder Card */}
          <div className="lg:col-span-2">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-8 shadow-sm h-full">
              {/* Avatar placeholder with clean SVG outline */}
              <div className="w-16 h-16 rounded-full border border-[var(--border-strong)] bg-[var(--bg)] flex items-center justify-center mb-6">
                <User size={28} className="text-[var(--primary)]" />
              </div>

              <h2 className="text-xl font-bold text-[var(--text-primary)] mb-1">Shailendra Mathur</h2>
              <p className="text-sm text-[var(--primary)] font-semibold mb-4 flex items-center gap-1.5">
                <Briefcase size={14} />
                Design Owner, SPOC
              </p>

              <p className="text-sm text-[var(--text-secondary)] leading-relaxed mb-6">
                Enterprise technology leader with over three decades of experience in TCS, designing large-scale business solutions across Banking, Capital Markets, Cloud Transformation and AI-powered enterprise platforms. Enjoys building products and mentoring startups in AI and Fintech.
              </p>

              <div className="space-y-3 pt-4 border-t border-[var(--border)]">
                <a href="mailto:shailendra@example.com" className="flex items-center gap-3 text-sm text-[var(--text-secondary)] hover:text-[var(--primary)] transition-colors group">
                  <div className="w-8 h-8 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex items-center justify-center group-hover:border-[var(--primary)]/30 transition-colors">
                    <Mail size={14} className="text-[var(--text-muted)] group-hover:text-[var(--primary)]" />
                  </div>
                  sh_mathur@yahoo.com
                </a>
                <a href="tel:+919800000000" className="flex items-center gap-3 text-sm text-[var(--text-secondary)] hover:text-[var(--primary)] transition-colors group">
                  <div className="w-8 h-8 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex items-center justify-center group-hover:border-[var(--primary)]/30 transition-colors">
                    <Phone size={14} className="text-[var(--text-muted)] group-hover:text-[var(--primary)]" />
                  </div>
                  +91 92500 07903
                </a>
                <div className="flex items-center gap-3 text-sm text-[var(--text-secondary)]">
                  <div className="w-8 h-8 rounded-lg bg-[var(--bg)] border border-[var(--border)] flex items-center justify-center">
                    <MapPin size={14} className="text-[var(--text-muted)]" />
                  </div>
                  Gurugram, India
                </div>
              </div>
            </div>
          </div>

          {/* Right — Contact Form */}
          <div className="lg:col-span-3">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] p-8 shadow-sm h-full">
              <h3 className="text-lg font-bold text-[var(--text-primary)] mb-1">Send a Message</h3>
              <p className="text-sm text-[var(--text-muted)] mb-6">Fill out the form and we&apos;ll get back to you shortly.</p>

              <form onSubmit={handleSubmit} className="flex flex-col gap-5">
                <div>
                  <label htmlFor="contact-name" className="block text-xs font-semibold text-[var(--text-secondary)] mb-1.5">
                    Full Name <span className="text-red-500">*</span>
                  </label>
                  <input
                    id="contact-name"
                    type="text"
                    required
                    value={formState.name}
                    onChange={e => setFormState(s => ({ ...s, name: e.target.value }))}
                    placeholder="Your full name"
                    className="input-base"
                  />
                </div>
                <div>
                  <label htmlFor="contact-email" className="block text-xs font-semibold text-[var(--text-secondary)] mb-1.5">
                    Email Address <span className="text-red-500">*</span>
                  </label>
                  <input
                    id="contact-email"
                    type="email"
                    required
                    value={formState.email}
                    onChange={e => setFormState(s => ({ ...s, email: e.target.value }))}
                    placeholder="you@company.com"
                    className="input-base"
                  />
                </div>
                <div>
                  <label htmlFor="contact-message" className="block text-xs font-semibold text-[var(--text-secondary)] mb-1.5">
                    Message <span className="text-red-500">*</span>
                  </label>
                  <textarea
                    id="contact-message"
                    required
                    rows={5}
                    value={formState.message}
                    onChange={e => setFormState(s => ({ ...s, message: e.target.value }))}
                    placeholder="Tell us about your practice and how we can help..."
                    className="input-base resize-none"
                  />
                </div>
                <button
                  type="submit"
                  className="flex items-center justify-center gap-2 w-full py-3 rounded-lg text-white font-semibold transition-all hover:shadow-lg hover:-translate-y-0.5"
                  style={{ background: 'var(--primary-gradient)' }}
                >
                  <Send size={16} />
                  Send Message
                </button>
                <p className="text-xs text-[var(--text-muted)] text-center">
                  Or reach out directly via email or phone listed on the left.
                </p>
              </form>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="relative z-10 border-t border-[var(--border)] py-8 mt-12">
        <div className="max-w-7xl mx-auto px-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-5 h-5 rounded flex items-center justify-center" style={{ background: 'var(--primary-gradient)' }}>
              <Link2 size={10} className="text-white" />
            </div>
            <span className="text-xs text-[var(--text-muted)]">© 2026 Project CaseChain</span>
          </div>
          <Link href="/" className="text-xs text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors">
            ← Back to Home
          </Link>
        </div>
      </footer>
    </div>
  )
}
