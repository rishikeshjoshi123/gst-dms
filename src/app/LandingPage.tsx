'use client'

import Link from 'next/link'
import { ArrowRight, Shield, Zap, Users, Cloud, Network, Briefcase, FileSearch, Clock, ChevronRight } from 'lucide-react'

export function LandingPage() {
  return (
    <div className="min-h-screen bg-[#0B0F17] text-slate-200 overflow-hidden selection:bg-blue-500/30 font-sans relative">
      {/* Animated Background Gradients */}
      <div className="fixed inset-0 z-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-[40%] -left-[10%] w-[70%] h-[70%] rounded-full bg-blue-900/20 blur-[120px] mix-blend-screen animate-pulse duration-[8000ms]" />
        <div className="absolute top-[20%] -right-[20%] w-[60%] h-[60%] rounded-full bg-indigo-900/20 blur-[120px] mix-blend-screen animate-pulse duration-[10000ms] delay-700" />
        <div className="absolute -bottom-[20%] left-[20%] w-[60%] h-[60%] rounded-full bg-violet-900/20 blur-[120px] mix-blend-screen animate-pulse duration-[12000ms] delay-1000" />
      </div>

      {/* Grid Pattern Overlay */}
      <div className="fixed inset-0 z-0 bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAiIGhlaWdodD0iMjAiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+PGNpcmNsZSBjeD0iMSIgY3k9IjEiIHI9IjEiIGZpbGw9InJnYmEoMjU1LDI1NSwyNTUsMC4wMykiLz48L3N2Zz4=')] opacity-50" />

      {/* Navigation */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-6 max-w-7xl mx-auto animate-in fade-in slide-in-from-top-4 duration-1000">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-lg flex items-center justify-center shadow-lg shadow-blue-500/25">
            <Shield size={18} className="text-white" />
          </div>
          <span className="text-xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-white to-slate-400">
            Project GST-DMS
          </span>
        </div>
        <div className="flex items-center gap-4">
          <Link href="/login" className="text-sm font-medium text-slate-300 hover:text-white transition-colors">
            Sign In
          </Link>
          <Link href="/login" className="text-sm font-semibold bg-white text-slate-900 px-5 py-2 rounded-full hover:bg-slate-100 transition-transform hover:scale-105 shadow-[0_0_15px_rgba(255,255,255,0.15)]">
            Get Started
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <main className="relative z-10 flex flex-col items-center justify-center min-h-[80vh] px-4 text-center">
        <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-blue-500/10 border border-blue-500/20 text-blue-400 text-xs font-semibold uppercase tracking-wider mb-8 animate-in fade-in slide-in-from-bottom-4 duration-700">
          <Zap size={14} className="animate-pulse" />
          The Future of Litigation Management
        </div>
        
        <h1 className="text-5xl md:text-7xl font-bold tracking-tight mb-6 max-w-4xl leading-[1.1] animate-in fade-in slide-in-from-bottom-6 duration-1000 delay-150">
          Transform Chaos into <br className="hidden md:block" />
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-400 via-indigo-400 to-purple-400">
            Strategic Clarity.
          </span>
        </h1>
        
        <p className="text-lg md:text-xl text-slate-400 max-w-2xl mb-10 animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-300">
          An intelligent, cloud-based document management system built exclusively for complex GST litigation. Automate parsing, visualize case timelines, and collaborate seamlessly.
        </p>
        
        <div className="flex flex-col sm:flex-row items-center gap-4 animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-500">
          <Link href="/login" className="flex items-center gap-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white px-8 py-4 rounded-full font-semibold text-lg hover:shadow-[0_0_30px_rgba(59,130,246,0.5)] transition-all hover:-translate-y-1 group">
            Start Your Workspace
            <ArrowRight size={20} className="group-hover:translate-x-1 transition-transform" />
          </Link>
          <a href="#features" className="flex items-center gap-2 px-8 py-4 rounded-full font-semibold text-lg text-slate-300 bg-slate-800/50 border border-slate-700 hover:bg-slate-800 transition-colors">
            Explore Features
          </a>
        </div>

        {/* Hero Image Mockup (CSS Representation) */}
        <div className="mt-16 w-full max-w-5xl relative animate-in fade-in slide-in-from-bottom-12 duration-1000 delay-700 group perspective-1000">
          <div className="absolute inset-0 bg-gradient-to-t from-[#0B0F17] via-transparent to-transparent z-10" />
          <div className="absolute -inset-1 bg-gradient-to-r from-blue-500 to-purple-500 rounded-xl blur opacity-20 group-hover:opacity-40 transition duration-1000" />
          <div className="relative rounded-xl border border-slate-800 bg-[#161E2E] shadow-2xl overflow-hidden transform-gpu transition-transform duration-700 group-hover:rotate-x-2 group-hover:scale-[1.01]">
            <div className="h-8 bg-slate-900 border-b border-slate-800 flex items-center px-4 gap-2">
              <div className="w-3 h-3 rounded-full bg-red-500/80" />
              <div className="w-3 h-3 rounded-full bg-amber-500/80" />
              <div className="w-3 h-3 rounded-full bg-green-500/80" />
            </div>
            <div className="p-8 aspect-video flex flex-col gap-4">
              <div className="w-1/3 h-6 bg-slate-800 rounded animate-pulse" />
              <div className="flex gap-4 h-full">
                <div className="w-1/4 h-full bg-slate-800/50 rounded-lg border border-slate-700/50" />
                <div className="flex-1 h-full bg-slate-800/30 rounded-lg border border-slate-700/50 flex items-center justify-center relative overflow-hidden">
                   <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(59,130,246,0.1)_0,transparent_100%)]" />
                   <Network size={64} className="text-blue-500/20" />
                </div>
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* Features Grid */}
      <section id="features" className="relative z-10 max-w-7xl mx-auto px-6 py-32">
        <div className="text-center mb-16">
          <h2 className="text-3xl md:text-5xl font-bold tracking-tight mb-4">Everything you need to win.</h2>
          <p className="text-slate-400 max-w-2xl mx-auto">Project GST-DMS replaces scattered folders and spreadsheets with a single, intelligent engine that understands your case.</p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <FeatureCard 
            icon={<FileSearch size={24} className="text-blue-400" />}
            title="System Document Parsing"
            desc="Automatically extract financial years, reference numbers, tax amounts, and summary context from complex GST notices."
          />
          <FeatureCard 
            icon={<Network size={24} className="text-indigo-400" />}
            title="Litigation Graph"
            desc="Visualize the entire lifecycle of a matter. See how SCNs connect to Replies, Appeals, and Orders in a dynamic timeline."
          />
          <FeatureCard 
            icon={<Briefcase size={24} className="text-purple-400" />}
            title="Client & Matter Hub"
            desc="Organize documents by client and specific matters. Never lose track of which file belongs to which financial year."
          />
          <FeatureCard 
            icon={<Users size={24} className="text-emerald-400" />}
            title="Team Collaboration"
            desc="Share CaseWikis, attach context-aware notes to specific pages in documents, and assign action items across your team."
          />
          <FeatureCard 
            icon={<Clock size={24} className="text-amber-400" />}
            title="Deadline Tracking"
            desc="Auto-extract due dates from notices and track all open action items from a centralized pending review dashboard."
          />
          <FeatureCard 
            icon={<Cloud size={24} className="text-cyan-400" />}
            title="Cloud-Native"
            desc="Access your entire litigation repository securely from anywhere. Scalable, lightning-fast, and always synced."
          />
        </div>
      </section>

      {/* CTA Section */}
      <section className="relative z-10 border-t border-slate-800 bg-slate-900/50 py-24">
        <div className="max-w-4xl mx-auto px-6 text-center">
          <h2 className="text-3xl font-bold mb-6">Ready to upgrade your practice?</h2>
          <Link href="/login" className="inline-flex items-center gap-2 bg-white text-slate-900 px-8 py-4 rounded-full font-bold text-lg hover:scale-105 hover:bg-slate-100 transition-all shadow-[0_0_20px_rgba(255,255,255,0.1)]">
            Get Started Now
            <ChevronRight size={20} />
          </Link>
        </div>
      </section>

      {/* Footer */}
      <footer className="relative z-10 border-t border-slate-800 py-8 text-center text-slate-500 text-sm">
        <p>© 2026 Project GST-DMS. All rights reserved.</p>
      </footer>
    </div>
  )
}

function FeatureCard({ icon, title, desc }: { icon: React.ReactNode, title: string, desc: string }) {
  return (
    <div className="group relative p-8 rounded-2xl bg-[#161E2E]/80 border border-slate-800 hover:border-slate-700 transition-colors overflow-hidden">
      <div className="absolute inset-0 bg-gradient-to-br from-white/[0.02] to-transparent pointer-events-none" />
      <div className="w-12 h-12 rounded-xl bg-slate-900 border border-slate-800 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform duration-500 shadow-lg">
        {icon}
      </div>
      <h3 className="text-xl font-bold text-slate-100 mb-3">{title}</h3>
      <p className="text-slate-400 leading-relaxed text-sm">{desc}</p>
    </div>
  )
}
