'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import {
  ArrowRight, FileSearch, Network, Users, Clock, Search, Cloud,
  Upload, Cpu, Eye, FileText, CheckCircle2,
  XCircle, ShieldCheck, Building2, Sparkles, AlertCircle,
  Scale, FileCheck2, Play, Pause
} from 'lucide-react'
import { ThemeToggle } from '@/components/nav/ThemeToggle'

/* ─── 1. Hero Case Chain Demo Data (Uses REAL DB attributes) ──────── */
const MOCK_CHAIN = [
  {
    id: 'scn',
    shortTitle: 'Show Cause Notice (Form DRC-01)',
    ref: 'SCN/2023-24/091',
    date: '14 Jul 2023',
    fy: 'FY 2021-22',
    direction: 'Incoming',
    directionColor: 'bg-[var(--danger-muted)] text-[var(--danger)] border-[color-mix(in_srgb,var(--danger)_20%,transparent)]',
    issuer: 'Superintendent, Range-IV, Mumbai',
    demand: '₹42,50,000',
    tax: '₹35,00,000',
    penalty: '₹3,50,000',
    interest: '₹4,00,000',
    deadline: 'Reply due within 30 days',
    linkedTo: 'Initiated Matter (Root Notice)',
    summary: 'Demand alleging ITC mismatch between GSTR-3B monthly returns and GSTR-2A statement.',
    icon: AlertCircle,
  },
  {
    id: 'reply',
    shortTitle: 'Taxpayer Reply (Form DRC-06)',
    ref: 'AG/GST/2023/412',
    date: '12 Aug 2023',
    fy: 'FY 2021-22',
    direction: 'Outgoing',
    directionColor: 'bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] text-[var(--primary)] border-[color-mix(in_srgb,var(--primary)_20%,transparent)]',
    issuer: 'M/s Apex Global Industries',
    demand: 'Disputed in Full',
    tax: '₹0 (Disputed)',
    penalty: '₹0',
    interest: '₹0',
    deadline: 'Filed 2 days before due date',
    linkedTo: 'Responds to SCN/2023-24/091',
    summary: 'Written submission attaching GSTR-1 supplier filings and reconciliation statements.',
    icon: FileText,
  },
  {
    id: 'order',
    shortTitle: 'Order-in-Original (Form DRC-07)',
    ref: 'OIO/MUM/2023/512',
    date: '20 Oct 2023',
    fy: 'FY 2021-22',
    direction: 'Incoming',
    directionColor: 'bg-[var(--warning-muted)] text-[var(--warning)] border-[color-mix(in_srgb,var(--warning)_20%,transparent)]',
    issuer: 'Assistant Commissioner, CGST',
    demand: '₹14,20,000',
    tax: '₹10,00,000',
    penalty: '₹2,20,000',
    interest: '₹2,00,000',
    deadline: 'Appeal due within 90 days',
    linkedTo: 'Adjudicates SCN & Reply',
    summary: 'Adjudication order confirming partial demand of ₹14.2L. Balance ₹28.3L dropped.',
    icon: Scale,
  },
  {
    id: 'appeal',
    shortTitle: 'Appeal to Appellate Authority (Form APL-01)',
    ref: 'APL/MUM/2023/881',
    date: '18 Dec 2023',
    fy: 'FY 2021-22',
    direction: 'Outgoing',
    directionColor: 'bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] text-[var(--primary)] border-[color-mix(in_srgb,var(--primary)_20%,transparent)]',
    issuer: 'M/s Apex Global Industries',
    demand: '₹14,20,000 (Challenged)',
    tax: '₹1,00,000 (Pre-Deposit Paid)',
    penalty: '₹2,20,000',
    interest: '₹2,00,000',
    deadline: 'Awaiting hearing notification',
    linkedTo: 'Challenges OIO/MUM/2023/512',
    summary: 'Appeal filed challenging the confirmed demand before Joint Commissioner (Appeals).',
    icon: FileCheck2,
  },
]

/* ─── 2. Original 4 Points — Simplified & Plain Language ─────────── */
const COMPARISON_ITEMS = [
  {
    id: 0,
    tabLabel: '01. Scattered Files',
    title: 'Scattered Case Documents',
    painDesc:
      'Case notices, replies, and orders get saved in different folders, sent over WhatsApp, or buried in email attachments. When you need a file quickly, you spend hours searching across multiple places.',
    solutionDesc:
      'Upload your documents once. CaseChain automatically tags and organizes every file by client, matter, and financial year in a single centralized space.',
    painPoints: [
      'Files scattered across emails, WhatsApp, and folders',
      'No single place to view all documents of a client',
      'High risk of losing key attachments or draft replies',
    ],
    solutionPoints: [
      'All files auto-organized by client, matter, and financial year',
      'One clean workspace for your entire legal team',
      'Instant access to any case document from any device',
    ],
  },
  {
    id: 1,
    tabLabel: '02. Tracing Case History',
    title: 'Tracing Case History',
    painDesc:
      'A single case can stretch over years with multiple notices, replies, and orders. Trying to figure out which reply responds to which notice requires digging through pages of old files.',
    solutionDesc:
      'CaseChain connects related documents automatically into a visual timeline. You can see the full story of a case — from the first notice to the latest order — at a glance.',
    painPoints: [
      'Hours spent piecing together chronological case history',
      'Hard to see which reply corresponds to which notice',
      'Difficulty explaining case status before hearings',
    ],
    solutionPoints: [
      'Visual case timeline shows the complete sequence in seconds',
      'Clear parent-child links between notices, replies, and orders',
      'Instant clarity for partners and clients before court',
    ],
  },
  {
    id: 2,
    tabLabel: '03. Tracking Due Dates',
    title: 'Tracking Due Dates',
    painDesc:
      'Important reply and appeal due dates are easy to miss when they are hidden inside lengthy PDF notices, especially during busy tax filing months.',
    solutionDesc:
      'Due dates are detected automatically when you upload a notice. CaseChain tracks upcoming deadlines and alerts your team so nothing gets missed.',
    painPoints: [
      'Due dates hidden inside multi-page PDF documents',
      'Manual calendar entries that get forgotten during busy months',
      'Risk of missing statutory reply or appeal deadlines',
    ],
    solutionPoints: [
      'Due dates extracted and logged automatically on upload',
      'Centralized deadline tracker for your whole practice',
      'Timely reminder alerts keep your team ahead of schedule',
    ],
  },
  {
    id: 3,
    tabLabel: '04. Finding Past Work',
    title: 'Finding Past Work',
    painDesc:
      'When starting a new case or onboarding a team member, finding previous replies or similar case arguments means asking around or opening files one by one.',
    solutionDesc:
      'Search across all your cases instantly. Type a GST number, financial year, or document type to find exact files and past submissions in seconds.',
    painPoints: [
      'Hard to find previous legal replies and case precedents',
      'Repeated effort re-drafting similar submissions',
      'Time-consuming onboarding for new team members',
    ],
    solutionPoints: [
      'Instant search across all clients, matters, and documents',
      'Reuse successful arguments from previous matters easily',
      'Shared case knowledge that stays with your firm',
    ],
  },
]

/* ─── 3. Features Data ───────────────────────────────────────────── */
const FEATURES_LARGE = [
  {
    icon: FileSearch,
    color: 'text-[var(--primary)]',
    title: 'Smart Document Parsing',
    summary: 'Upload a GST notice and get structured data in seconds.',
    detail:
      'CaseChain parses every uploaded document — SCNs, orders, replies, appeals — and automatically extracts reference numbers, GSTINs, financial years, tax amounts, and deadlines. No manual data entry. Documents are tagged, categorized, and linked to the correct client and matter.',
    parseFields: [
      { label: 'GSTIN', value: '27AAACA123411Z' },
      { label: 'Notice Type', value: 'Form DRC-01 (Section 73)' },
      { label: 'Financial Year', value: 'FY 2021-22' },
      { label: 'Demand Amount', value: '₹42,50,000' },
      { label: 'Extracted Due Date', value: '13 Aug 2023 (30 Days)' },
    ],
  },
  {
    icon: Network,
    color: 'text-[var(--primary)]',
    title: 'Visual Litigation Timeline',
    summary: 'See how every document in a case connects.',
    detail:
      'Traditional file management shows documents as a flat list. CaseChain builds a visual graph — a chain — showing exactly how an SCN led to a Reply, which led to an Order-in-Original, which was challenged by an Appeal. You see the entire litigation lifecycle at a glance.',
  },
]

const FEATURES_SMALL = [
  {
    icon: Users,
    color: 'text-[var(--success)]',
    title: 'Client & Matter Hub',
    summary: 'Organize everything by client, matter, and financial year.',
  },
  {
    icon: Clock,
    color: 'text-[var(--warning)]',
    title: 'Deadline Tracking',
    summary: 'Auto-extracted due dates with countdown alerts.',
  },
  {
    icon: Search,
    color: 'text-[var(--primary)]',
    title: 'Smart Search',
    summary: 'Find any document across all cases in one search.',
  },
  {
    icon: Cloud,
    color: 'text-[var(--primary)]',
    title: 'Cloud-Native',
    summary: 'Secure, always-synced access from anywhere.',
  },
]

/* ─── 4. How It Works Data ────────────────────────────────────────── */
const HOW_IT_WORKS = [
  {
    step: '01',
    title: '1. Ingestion',
    desc: 'Drop your GST PDFs — SCNs, replies, orders, appeals. System ingests them instantly.',
    icon: Upload,
    demoAction: 'PDF File Dropped → Staged for Parsing',
  },
  {
    step: '02',
    title: '2. Auto-Parsing & Chaining',
    desc: 'Extract GSTIN, FY, notice type, amounts, and auto-link to parent case documents.',
    icon: Cpu,
    demoAction: 'Extracted: DRC-01 · ₹42.5L Demand · Linked to Matter',
  },
  {
    step: '03',
    title: '3. Chain & Alerts',
    desc: 'Browse the visual case graph, track appeal windows, and search across matters.',
    icon: Eye,
    demoAction: 'Visual Graph Built · 30-Day Reply Clock Active',
  },
]

/* ─── 5. Graph Animation Node Data for Feature Card 2 ─────────────── */
const GRAPH_NODES = [
  { id: 'scn', label: 'Form DRC-01', type: 'SCN', x: 20, y: 30, color: 'border-[var(--danger)] text-[var(--danger)] bg-[var(--danger-muted)]' },
  { id: 'reply', label: 'Form DRC-06', type: 'REPLY', x: 80, y: 30, color: 'border-[var(--primary)] text-[var(--primary)] bg-[color-mix(in_srgb,var(--primary)_10%,transparent)]' },
  { id: 'order', label: 'Form DRC-07', type: 'ORDER', x: 80, y: 80, color: 'border-[var(--warning)] text-[var(--warning)] bg-[var(--warning-muted)]' },
  { id: 'appeal', label: 'Form APL-01', type: 'APPEAL', x: 20, y: 80, color: 'border-[var(--primary)] text-[var(--primary)] bg-[color-mix(in_srgb,var(--primary)_10%,transparent)]' },
]

const GRAPH_STATUS_MESSAGES = [
  '⚡ Step 1: Root Show Cause Notice (Form DRC-01) Ingested',
  '⚡ Step 2: Linked Taxpayer Reply (Form DRC-06) ➔ SCN',
  '⚡ Step 3: Linked Adjudication Order (Form DRC-07) ➔ Reply',
  '⚡ Step 4: Linked Statutory Appeal (Form APL-01) ➔ Order',
]

/* ─── Landing Page Main Component ────────────────────────────────── */
export function LandingPage() {
  // Hero Auto-play state
  const [selectedNodeId, setSelectedNodeId] = useState<string>('order')
  const [isHeroPlaying, setIsHeroPlaying] = useState<boolean>(true)

  // Problem vs Solution Auto-play state
  const [activeCompareIdx, setActiveCompareIdx] = useState<number>(0)
  const [isComparePlaying, setIsComparePlaying] = useState<boolean>(true)

  // Features Parsing Auto-play state
  const [activeParseFieldIdx, setActiveParseFieldIdx] = useState<number>(0)

  // Card 2 Animated Graph State
  const [activeGraphStep, setActiveGraphStep] = useState<number>(0)
  const [isGraphPlaying, setIsGraphPlaying] = useState<boolean>(true)

  // How-It-Works Pipeline Auto-play state
  const [activeStepIdx, setActiveStepIdx] = useState<number>(0)
  const [isPipelinePlaying, setIsPipelinePlaying] = useState<boolean>(true)

  // 1. Hero Auto-cycle (4s)
  useEffect(() => {
    if (!isHeroPlaying) return
    const timer = setInterval(() => {
      setSelectedNodeId(prev => {
        const idx = MOCK_CHAIN.findIndex(n => n.id === prev)
        return MOCK_CHAIN[(idx + 1) % MOCK_CHAIN.length].id
      })
    }, 4000)
    return () => clearInterval(timer)
  }, [isHeroPlaying])

  // 2. Compare Section Auto-cycle (5s)
  useEffect(() => {
    if (!isComparePlaying) return
    const timer = setInterval(() => {
      setActiveCompareIdx(prev => (prev + 1) % COMPARISON_ITEMS.length)
    }, 5000)
    return () => clearInterval(timer)
  }, [isComparePlaying])

  // 3. Feature Parsing Field Highlight Auto-cycle (2.5s)
  useEffect(() => {
    const timer = setInterval(() => {
      setActiveParseFieldIdx(prev => (prev + 1) % 5)
    }, 2500)
    return () => clearInterval(timer)
  }, [])

  // 4. Card 2 Animated Graph Linker Auto-cycle (3s)
  useEffect(() => {
    if (!isGraphPlaying) return
    const timer = setInterval(() => {
      setActiveGraphStep(prev => (prev + 1) % 4)
    }, 3000)
    return () => clearInterval(timer)
  }, [isGraphPlaying])

  // 5. How It Works Pipeline Auto-cycle (3.5s)
  useEffect(() => {
    if (!isPipelinePlaying) return
    const timer = setInterval(() => {
      setActiveStepIdx(prev => (prev + 1) % HOW_IT_WORKS.length)
    }, 3500)
    return () => clearInterval(timer)
  }, [isPipelinePlaying])

  const selectedNode = MOCK_CHAIN.find(n => n.id === selectedNodeId) || MOCK_CHAIN[2]
  const activeCompare = COMPARISON_ITEMS[activeCompareIdx]

  return (
    <div className="min-h-screen bg-[var(--bg)] text-[var(--text-primary)] overflow-x-hidden selection:bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] font-sans">
      {/* ── Navigation ────────────────────────────────────────────── */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-5 max-w-7xl mx-auto">
        <Link href="/" className="flex items-center group">
          <span className="text-xl font-bold tracking-tight text-[var(--text-primary)]">
            CaseChain
          </span>
        </Link>

        <div className="flex items-center gap-3">
          <ThemeToggle />
          <Link href="/login" className="text-sm font-semibold text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors hidden sm:inline-flex">
            Sign In
          </Link>
          <Link href="/login" className="inline-flex min-h-11 items-center whitespace-nowrap rounded-[var(--radius-sm)] px-5 py-2 text-sm font-semibold text-[var(--on-accent)] shadow-sm transition-colors hover:bg-[var(--primary-hover)]" style={{ background: 'var(--primary-gradient)' }}>
            Get Started
          </Link>
        </div>
      </nav>

      {/* ── HERO SECTION: Live Case Chain Showcase ───────────────── */}
      <section className="relative z-10 max-w-7xl mx-auto px-6 pt-10 pb-20 md:pt-14 md:pb-28">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-10 lg:gap-12 items-center">
          {/* Left Text */}
          <div className="lg:col-span-5 animate-fade-in">
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)] mb-3 flex items-center gap-1.5">
              <Sparkles size={14} />
              GST Litigation Document Management System
            </p>
            <h1 className="text-4xl md:text-5xl lg:text-5xl font-extrabold tracking-tight leading-[1.15] mb-5 text-[var(--text-primary)]">
              Every GST Case Document.{' '}
              <span className="text-[var(--primary)]">
                One Chain.
              </span>{' '}
              Zero Chaos.
            </h1>
            <p className="text-sm md:text-base text-[var(--text-secondary)] leading-relaxed mb-8">
              In a typical GST litigation office, case documents live across scattered folders, email threads, WhatsApp groups, and physical files. Finding an SCN or tracing its reply takes hours.
              <strong className="text-[var(--text-primary)] font-bold"> CaseChain puts every document in its place</strong> — automatically linked, chronologically ordered, instantly retrievable.
            </p>
            <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
              <Link href="/login" className="flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] px-7 py-3 text-sm font-semibold text-[var(--on-accent)] shadow-sm transition-colors hover:bg-[var(--primary-hover)] group" style={{ background: 'var(--primary-gradient)' }}>
                Get Started
                <ArrowRight size={16} className="group-hover:translate-x-1 transition-transform" />
              </Link>
              <Link href="/contact" className="flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-7 py-3 text-sm font-semibold text-[var(--text-secondary)] shadow-xs transition-colors hover:bg-[var(--surface-hover)]">
                Contact Us
              </Link>
            </div>
          </div>

          {/* Right Live Interactive Demo Widget */}
          <div className="lg:col-span-7 animate-fade-in">
            <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] shadow-xl overflow-hidden">
              {/* Widget Top App Header */}
              <div className="px-5 py-3 border-b border-[var(--border)] bg-[var(--bg)] flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-2.5 h-2.5 rounded-full bg-[var(--danger)]" />
                  <div className="w-2.5 h-2.5 rounded-full bg-[var(--warning)]" />
                  <div className="w-2.5 h-2.5 rounded-full bg-[var(--success)]" />
                  <span className="text-xs font-bold text-[var(--text-primary)] ml-2 flex items-center gap-1.5">
                    <Building2 size={14} className="text-[var(--primary)] shrink-0" />
                    M/s Apex Global Industries
                  </span>
                </div>

                <div className="flex items-center gap-3">
                  <button
                    onClick={() => setIsHeroPlaying(!isHeroPlaying)}
                    className="flex min-h-11 items-center gap-1 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--surface)] px-2 py-0.5 text-[10px] font-semibold text-[var(--text-muted)] transition-colors hover:text-[var(--text-primary)]"
                    title={isHeroPlaying ? 'Pause auto-cycle' : 'Play auto-cycle'}
                  >
                    {isHeroPlaying ? (
                      <>
                        <span className="w-1.5 h-1.5 rounded-full bg-[var(--success)] animate-pulse-dot" />
                        <Pause size={10} />
                        Auto-playing
                      </>
                    ) : (
                      <>
                        <Play size={10} />
                        Paused
                      </>
                    )}
                  </button>
                  <span className="text-[10px] font-mono text-[var(--text-muted)] font-semibold hidden sm:inline">GSTIN: 27AAACA123411Z</span>
                </div>
              </div>

              {/* Widget Body */}
              <div className="p-5 grid grid-cols-1 sm:grid-cols-12 gap-5 bg-[var(--surface)]">
                {/* Left Timeline Nodes Column */}
                <div className="sm:col-span-6 flex flex-col gap-2">
                  <div className="text-[11px] font-extrabold uppercase tracking-wider text-[var(--text-muted)] mb-1 flex items-center justify-between">
                    <span>Litigation Timeline</span>
                    <span className="text-[10px] font-bold text-[var(--primary)] bg-[var(--primary)]/10 px-2 py-0.5 rounded border border-[var(--primary)]/20">
                      4 Linked Docs
                    </span>
                  </div>

                  {MOCK_CHAIN.map((node, index) => {
                    const isSelected = node.id === selectedNodeId
                    const NodeIcon = node.icon
                    return (
                      <div key={node.id} className="relative">
                        {/* Connected Vertical Line */}
                        {index < MOCK_CHAIN.length - 1 && (
                          <div className="absolute left-[22px] top-9 bottom-0 w-[2px] bg-[var(--border-strong)] z-0" />
                        )}

                        <button
                          onClick={() => {
                            setSelectedNodeId(node.id)
                            setIsHeroPlaying(false)
                          }}
                          className={`w-full text-left p-3 rounded-[var(--radius-md)] border transition-all duration-200 relative z-10 flex items-center gap-3 ${
                            isSelected
                              ? 'border-[var(--primary)] bg-[var(--primary)]/10 ring-2 ring-[var(--primary)]/30 shadow-xs'
                              : 'border-[var(--border)] bg-[var(--bg)] hover:border-[var(--border-strong)]'
                          }`}
                        >
                          <div className={`w-8 h-8 rounded-[var(--radius-sm)] flex items-center justify-center shrink-0 border ${
                            isSelected ? 'bg-[var(--surface)] border-[var(--primary)]' : 'bg-[var(--surface)] border-[var(--border)]'
                          }`}>
                            <NodeIcon size={16} className={isSelected ? 'text-[var(--primary)]' : 'text-[var(--text-muted)]'} />
                          </div>

                          <div className="flex flex-col min-w-0 flex-1">
                            <span className="text-xs font-bold text-[var(--text-primary)] truncate">{node.shortTitle}</span>
                            <span className="text-[10px] text-[var(--text-muted)] font-medium truncate">{node.ref} · {node.date}</span>
                          </div>

                          <span className={`text-[9px] font-bold px-1.5 py-0.5 rounded border shrink-0 ${node.directionColor}`}>
                            {node.direction}
                          </span>
                        </button>
                      </div>
                    )
                  })}
                </div>

                {/* Right Document Metadata Inspector */}
                <div className="sm:col-span-6 rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] p-4 flex flex-col justify-between shadow-xs">
                  <div>
                    {/* Inspector Header */}
                    <div className="flex items-center justify-between mb-3 pb-2 border-b border-[var(--border)]">
                      <span className="text-[10px] font-extrabold text-[var(--text-muted)] uppercase tracking-wider">Document Inspector</span>
                      <span className="text-[10px] font-bold text-[var(--primary)] bg-[var(--surface)] border border-[var(--border-strong)] px-2 py-0.5 rounded">
                        {selectedNode.ref}
                      </span>
                    </div>

                    {/* Title */}
                    <h4 className="text-xs font-extrabold text-[var(--text-primary)] mb-0.5 leading-snug">{selectedNode.shortTitle}</h4>
                    <p className="text-[10px] font-mono text-[var(--text-muted)] font-semibold mb-3">{selectedNode.issuer}</p>

                    {/* Spec Attributes */}
                    <div className="space-y-1.5 text-[11px] mb-3 bg-[var(--surface)] border border-[var(--border)] rounded-[var(--radius-sm)] p-2.5">
                      <div className="flex items-center justify-between text-[var(--text-secondary)]">
                        <span className="text-[10px] font-semibold">Doc Direction:</span>
                        <span className={`font-bold text-[9px] px-1.5 py-0.2 rounded border ${selectedNode.directionColor}`}>
                          {selectedNode.direction}
                        </span>
                      </div>
                      <div className="flex items-center justify-between text-[var(--text-secondary)]">
                        <span className="text-[10px] font-semibold">Financial Year:</span>
                        <span className="font-bold text-[var(--text-primary)] text-[10px]">{selectedNode.fy}</span>
                      </div>
                      <div className="flex items-center justify-between text-[var(--text-secondary)]">
                        <span className="text-[10px] font-semibold">Demand Amount:</span>
                        <span className="font-extrabold text-[11px] text-[var(--warning)]">{selectedNode.demand}</span>
                      </div>
                      <div className="flex items-center justify-between text-[var(--text-secondary)] pt-1 border-t border-[var(--border)]">
                        <span className="text-[10px] font-semibold">Statutory Deadline:</span>
                        <span className="font-bold text-[10px] text-[var(--primary)] truncate max-w-[120px]" title={selectedNode.deadline}>
                          {selectedNode.deadline}
                        </span>
                      </div>
                    </div>

                    {/* Summary */}
                    <div className="p-2.5 rounded-[var(--radius-sm)] bg-[var(--surface)] border border-[var(--border)] text-[10px] text-[var(--text-secondary)] leading-relaxed font-medium">
                      <span className="font-bold text-[var(--text-primary)]">Summary: </span>
                      {selectedNode.summary}
                    </div>
                  </div>

                  {/* Chain Relationship */}
                  <div className="mt-3 pt-2.5 border-t border-[var(--border)] flex items-center justify-between text-[10px] text-[var(--text-muted)] font-semibold">
                    <span className="flex items-center gap-1 text-[var(--primary)] font-bold truncate max-w-[180px]">
                      <Network size={12} className="shrink-0" />
                      {selectedNode.linkedTo}
                    </span>
                    <span className="flex items-center gap-1 text-[var(--success)] font-bold shrink-0">
                      <ShieldCheck size={12} />
                      Verified
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── PROBLEM vs SOLUTION: High Contrast & Simple Text ─────── */}
      <section className="relative z-10 py-16 md:py-24 border-t border-[var(--border)]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)] mb-2">
                Why Traditional Folders Fail
              </p>
              <h2 className="text-3xl md:text-4xl font-extrabold tracking-tight text-[var(--text-primary)]">
                The Problem We Solve
              </h2>
            </div>

            {/* Auto-play toggle */}
            <button
              onClick={() => setIsComparePlaying(!isComparePlaying)}
              className="flex min-h-11 items-center gap-1.5 text-xs font-bold text-[var(--text-secondary)] bg-[var(--surface)] border border-[var(--border-strong)] px-3 py-1.5 rounded-[var(--radius-sm)] shadow-xs hover:border-[var(--primary)] transition-colors shrink-0"
            >
              {isComparePlaying ? (
                <>
                  <span className="w-2 h-2 rounded-full bg-[var(--success)] animate-pulse-dot" />
                  <Pause size={12} />
                  Auto-spotlight On
                </>
              ) : (
                <>
                  <Play size={12} />
                  Auto-spotlight Paused
                </>
              )}
            </button>
          </div>

          {/* Clean 4 Point Navigation Tabs */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-8">
            {COMPARISON_ITEMS.map((item, idx) => {
              const isActive = idx === activeCompareIdx
              return (
                <button
                  key={idx}
                  onClick={() => {
                    setActiveCompareIdx(idx)
                    setIsComparePlaying(false)
                  }}
                  className={`p-4 rounded-[var(--radius-md)] border text-left transition-all duration-200 flex flex-col justify-between ${
                    isActive
                      ? 'border-[var(--primary)] bg-[var(--surface)] shadow-md ring-2 ring-[var(--primary)]/20'
                      : 'border-[var(--border-strong)] bg-[var(--surface)] text-[var(--text-muted)] hover:text-[var(--text-primary)]'
                  }`}
                >
                  <span className={`text-[10px] font-mono font-bold block mb-1 ${isActive ? 'text-[var(--primary)]' : 'text-[var(--text-muted)]'}`}>
                    {item.tabLabel}
                  </span>
                  <h4 className={`text-xs font-bold leading-snug ${isActive ? 'text-[var(--text-primary)]' : 'text-[var(--text-secondary)]'}`}>
                    {item.title}
                  </h4>
                </button>
              )
            })}
          </div>

          {/* High-Contrast Side-by-Side Comparison Cards */}
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            {/* Left Card: The Reality Today */}
            <div className="lg:col-span-6 rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--danger)_20%,transparent)] bg-[var(--surface)] p-7 md:p-8 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-3 mb-5 pb-4 border-b border-[var(--border)]">
                  <div className="w-8 h-8 rounded-[var(--radius-md)] bg-[var(--danger-muted)] border border-[color-mix(in_srgb,var(--danger)_20%,transparent)] text-[var(--danger)] flex items-center justify-center font-extrabold text-sm">
                    ✗
                  </div>
                  <div>
                    <h3 className="text-base font-extrabold text-[var(--danger)]">The Reality Today</h3>
                    <span className="text-xs font-medium text-[var(--text-muted)]">Traditional File Management</span>
                  </div>
                </div>

                <h4 className="text-lg font-extrabold text-[var(--text-primary)] mb-3">
                  {activeCompare.title}
                </h4>
                <p className="text-sm text-[var(--text-secondary)] leading-relaxed font-medium mb-6">
                  {activeCompare.painDesc}
                </p>

                <div className="space-y-3 pt-4 border-t border-[var(--border)]">
                  {activeCompare.painPoints.map((pt, pIdx) => (
                    <div key={pIdx} className="flex items-start gap-2.5 text-xs text-[var(--text-primary)] font-semibold">
                      <XCircle size={16} className="text-[var(--danger)] shrink-0 mt-0.5" />
                      <span>{pt}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Right Card: With CaseChain */}
            <div className="lg:col-span-6 rounded-[var(--radius-md)] border border-[color-mix(in_srgb,var(--success)_20%,transparent)] bg-[var(--surface)] p-7 md:p-8 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-3 mb-5 pb-4 border-b border-[var(--border)]">
                  <div className="w-8 h-8 rounded-[var(--radius-sm)] bg-[var(--success-muted)] border border-[color-mix(in_srgb,var(--success)_20%,transparent)] text-[var(--success)] flex items-center justify-center font-extrabold text-sm">
                    ✓
                  </div>
                  <div>
                    <h3 className="text-base font-extrabold text-[var(--success)]">With CaseChain</h3>
                    <span className="text-xs font-medium text-[var(--text-muted)]">Organized Litigation Workspace</span>
                  </div>
                </div>

                <h4 className="text-lg font-extrabold text-[var(--text-primary)] mb-3">
                  How CaseChain Solves It
                </h4>
                <p className="text-sm text-[var(--text-secondary)] leading-relaxed font-semibold mb-6">
                  {activeCompare.solutionDesc}
                </p>

                <div className="space-y-3 pt-4 border-t border-[var(--border)]">
                  {activeCompare.solutionPoints.map((pt, sIdx) => (
                    <div key={sIdx} className="flex items-start gap-2.5 text-xs text-[var(--text-primary)] font-bold">
                      <CheckCircle2 size={16} className="text-[var(--success)] shrink-0 mt-0.5" />
                      <span>{pt}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── FEATURES BENTO GRID: Auto-Animated Field Parsing & Dynamic Interactive Graph ──── */}
      <section id="features" className="relative z-10 py-16 md:py-24 border-t border-[var(--border)]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center mb-12">
            <h2 className="text-3xl md:text-4xl font-extrabold tracking-tight mb-3 text-[var(--text-primary)]">
              Built for GST Litigation Workflows
            </h2>
            <p className="text-sm font-medium text-[var(--text-secondary)] max-w-2xl mx-auto">
              Designed specifically around how GST litigation practitioners manage notices, replies, and tribunal appeals.
            </p>
          </div>

          {/* Large feature cards with interactive highlights */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            {/* Card 1 — Auto Field Parsing Demo */}
            <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-7 hover:border-[var(--primary)]/50 transition-all">
              <div className="w-9 h-9 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--bg)] flex items-center justify-center mb-4">
                <FileSearch size={18} className="text-[var(--primary)]" />
              </div>
              <h3 className="text-xl font-bold text-[var(--text-primary)] mb-2">{FEATURES_LARGE[0].title}</h3>
              <p className="text-xs text-[var(--text-secondary)] mb-5 leading-relaxed font-medium">{FEATURES_LARGE[0].detail}</p>

              {/* Dynamic Auto-highlighting parsed fields preview */}
              <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] p-4 space-y-2">
                <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-2 flex items-center justify-between">
                  <span>Auto-Extracted Data Spec</span>
                  <span className="text-[var(--primary)] font-bold">Live Parsing Engine</span>
                </div>
                {FEATURES_LARGE[0].parseFields?.map((field, fIdx) => {
                  const isHighlighted = fIdx === activeParseFieldIdx
                  return (
                    <div
                      key={fIdx}
                      className={`flex items-center justify-between p-2 rounded-[var(--radius-sm)] text-xs transition-all duration-500 ${
                        isHighlighted
                          ? 'bg-[color-mix(in_srgb,var(--primary)_10%,transparent)] border border-[color-mix(in_srgb,var(--primary)_20%,transparent)] text-[var(--primary)] font-extrabold translate-x-1'
                          : 'bg-[var(--surface)] border border-[var(--border)] text-[var(--text-secondary)] font-medium'
                      }`}
                    >
                      <span className="text-[11px] font-semibold">{field.label}</span>
                      <span className="font-mono text-[11px] font-bold">{field.value}</span>
                    </div>
                  )}
                )}
              </div>
            </div>

            {/* Card 2 — DYNAMIC AUTO-PLAYING GRAPH CANVAS (Requested feature!) */}
            <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-7 hover:border-[var(--primary)]/50 transition-all flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="w-9 h-9 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--bg)] flex items-center justify-center">
                    <Network size={18} className="text-[var(--primary)]" />
                  </div>
                  <button
                    onClick={() => setIsGraphPlaying(!isGraphPlaying)}
                    className="flex min-h-11 items-center gap-1 rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--bg)] px-2 py-1 text-[10px] font-semibold text-[var(--text-muted)]"
                  >
                    {isGraphPlaying ? (
                      <>
                        <span className="w-1.5 h-1.5 rounded-full bg-[var(--primary)] animate-pulse-dot" />
                        <Pause size={10} />
                        Auto-linking
                      </>
                    ) : (
                      <>
                        <Play size={10} />
                        Paused
                      </>
                    )}
                  </button>
                </div>
                <h3 className="text-xl font-bold text-[var(--text-primary)] mb-2">{FEATURES_LARGE[1].title}</h3>
                <p className="text-xs text-[var(--text-secondary)] mb-4 leading-relaxed font-medium">{FEATURES_LARGE[1].detail}</p>
              </div>

              {/* Dynamic Interactive SVG Graph Canvas */}
              <div className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--bg)] p-4 relative overflow-hidden">
                <div className="text-[10px] font-bold uppercase tracking-wider text-[var(--text-muted)] mb-3 flex items-center justify-between">
                  <span>Interactive Litigation Graph</span>
                  <span className="text-[var(--primary)] font-bold text-[9px] font-mono">
                    {GRAPH_STATUS_MESSAGES[activeGraphStep]}
                  </span>
                </div>

                {/* SVG Graph Canvas with Animated Links */}
                <div className="relative h-44 border border-[var(--border)] rounded-[var(--radius-sm)] bg-[var(--surface)] p-3">
                  <svg className="absolute inset-0 w-full h-full pointer-events-none z-0">
                    {/* SVG Connector Lines between graph nodes */}
                    {/* Link 1: SCN -> Reply */}
                    <line
                      x1="30%" y1="28%" x2="70%" y2="28%"
                      stroke={activeGraphStep >= 1 ? 'var(--primary)' : 'var(--border-strong)'}
                      strokeWidth={activeGraphStep >= 1 ? '2.5' : '1.5'}
                      strokeDasharray={activeGraphStep >= 1 ? 'none' : '4 4'}
                      className="transition-all duration-500"
                    />
                    {/* Link 2: Reply -> Order */}
                    <line
                      x1="70%" y1="28%" x2="70%" y2="72%"
                      stroke={activeGraphStep >= 2 ? 'var(--warning)' : 'var(--border-strong)'}
                      strokeWidth={activeGraphStep >= 2 ? '2.5' : '1.5'}
                      strokeDasharray={activeGraphStep >= 2 ? 'none' : '4 4'}
                      className="transition-all duration-500"
                    />
                    {/* Link 3: Order -> Appeal */}
                    <line
                      x1="70%" y1="72%" x2="30%" y2="72%"
                      stroke={activeGraphStep >= 3 ? 'var(--primary)' : 'var(--border-strong)'}
                      strokeWidth={activeGraphStep >= 3 ? '2.5' : '1.5'}
                      strokeDasharray={activeGraphStep >= 3 ? 'none' : '4 4'}
                      className="transition-all duration-500"
                    />
                  </svg>

                  {/* Graph Nodes positioned in Canvas */}
                  {GRAPH_NODES.map((node, nIdx) => {
                    const isNodeActive = activeGraphStep >= nIdx
                    return (
                      <button
                        key={node.id}
                        onClick={() => {
                          setActiveGraphStep(nIdx)
                          setIsGraphPlaying(false)
                        }}
                        className={`absolute min-h-11 -translate-x-1/2 -translate-y-1/2 p-2 rounded-[var(--radius-md)] border text-center transition-all duration-500 z-10 flex flex-col items-center shadow-xs cursor-pointer ${
                          isNodeActive
                            ? `${node.color} ring-2 ring-[color-mix(in_srgb,var(--primary)_20%,transparent)] scale-105`
                            : 'border-[var(--border)] bg-[var(--bg)] text-[var(--text-muted)] scale-95 opacity-60'
                        }`}
                        style={{ left: `${node.x}%`, top: `${node.y}%` }}
                      >
                        <span className="text-[8px] font-mono font-bold uppercase tracking-wider block">
                          {node.type}
                        </span>
                        <span className="text-[10px] font-bold whitespace-nowrap block">
                          {node.label}
                        </span>
                      </button>
                    )
                  })}
                </div>

                <div className="mt-2 text-center text-[10px] text-[var(--text-muted)] font-medium">
                  Click any node or watch auto-linking animation in real time
                </div>
              </div>
            </div>
          </div>

          {/* Small feature cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
            {FEATURES_SMALL.map(f => (
              <SmallFeatureCard key={f.title} {...f} />
            ))}
          </div>
        </div>
      </section>

      {/* ── HOW IT WORKS: Auto-Playing 3-Step Pipeline Showcase ── */}
      <section className="relative z-10 py-16 md:py-24 border-t border-[var(--border)] bg-[var(--surface)]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="flex flex-col md:flex-row md:items-end justify-between mb-10 gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)] mb-2">
                Automated Processing Flow
              </p>
              <h2 className="text-3xl md:text-4xl font-extrabold tracking-tight text-[var(--text-primary)]">
                How It Works
              </h2>
            </div>

            <button
              onClick={() => setIsPipelinePlaying(!isPipelinePlaying)}
              className="flex min-h-11 items-center gap-1.5 text-xs font-bold text-[var(--text-secondary)] bg-[var(--bg)] border border-[var(--border-strong)] px-3 py-1.5 rounded-[var(--radius-sm)] shadow-xs hover:border-[var(--primary)] transition-colors shrink-0"
            >
              {isPipelinePlaying ? (
                <>
                  <span className="w-2 h-2 rounded-full bg-[var(--success)] animate-pulse-dot" />
                  <Pause size={12} />
                  Auto-tour On
                </>
              ) : (
                <>
                  <Play size={12} />
                  Auto-tour Paused
                </>
              )}
            </button>
          </div>

          {/* Pipeline 3-step cards with active step highlighting */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {HOW_IT_WORKS.map((step, idx) => {
              const StepIcon = step.icon
              const isActive = idx === activeStepIdx
              return (
                <div
                  key={step.step}
                  onClick={() => {
                    setActiveStepIdx(idx)
                    setIsPipelinePlaying(false)
                  }}
                  className={`rounded-[var(--radius-md)] border p-6 flex flex-col justify-between relative cursor-pointer transition-all duration-300 ${
                    isActive
                      ? 'border-[var(--primary)] bg-[var(--primary)]/10 ring-2 ring-[var(--primary)]/30 shadow-md scale-[1.02]'
                      : 'border-[var(--border)] bg-[var(--bg)] hover:border-[var(--border-strong)]'
                  }`}
                >
                  <div>
                    <div className="flex items-center justify-between mb-4">
                      <div className={`w-10 h-10 rounded-[var(--radius-md)] border flex items-center justify-center ${
                        isActive ? 'bg-[var(--surface)] border-[var(--primary)]' : 'bg-[var(--surface)] border-[var(--border-strong)]'
                      }`}>
                        <StepIcon size={20} className={isActive ? 'text-[var(--primary)]' : 'text-[var(--text-muted)]'} />
                      </div>
                      <span className={`text-xs font-mono font-bold px-2 py-0.5 rounded border ${
                        isActive ? 'bg-[var(--primary)] text-[var(--on-accent)] border-[var(--primary)]' : 'bg-[var(--surface)] text-[var(--text-muted)] border-[var(--border)]'
                      }`}>
                        Step {step.step}
                      </span>
                    </div>

                    <h3 className="text-base font-bold text-[var(--text-primary)] mb-2">{step.title}</h3>
                    <p className="text-xs text-[var(--text-secondary)] leading-relaxed mb-4 font-medium">{step.desc}</p>
                  </div>

                  {/* Active Action Preview Badge */}
                  <div className={`p-2.5 rounded-[var(--radius-sm)] border text-[11px] font-mono font-bold transition-all ${
                    isActive
                      ? 'bg-[var(--surface)] border-[var(--primary)] text-[var(--primary)] shadow-xs'
                      : 'bg-[var(--surface)] border-[var(--border)] text-[var(--text-muted)]'
                  }`}>
                    ⚡ {step.demoAction}
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* ── CTA SECTION ───────────────────────────────────────────── */}
      <section className="relative z-10 py-20 border-t border-[var(--border)]">
        <div className="max-w-3xl mx-auto px-6">
          <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-10 md:p-14 text-center shadow-xl relative overflow-hidden">
            <h2 className="text-3xl md:text-4xl font-extrabold tracking-tight mb-4 text-[var(--text-primary)]">
              Stop searching. Start finding.
            </h2>
            <p className="text-sm font-medium text-[var(--text-secondary)] mb-8 max-w-md mx-auto">
              Get your litigation documents organized into an automated case chain in minutes.
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-3">
              <Link href="/login" className="flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] px-8 py-3.5 text-sm font-semibold text-[var(--on-accent)] shadow-sm transition-colors hover:bg-[var(--primary-hover)] group" style={{ background: 'var(--primary-gradient)' }}>
                Get Started
                <ArrowRight size={16} className="group-hover:translate-x-1 transition-transform" />
              </Link>
              <Link href="/contact" className="flex min-h-11 items-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-8 py-3.5 text-sm font-semibold text-[var(--text-secondary)] shadow-xs transition-colors hover:bg-[var(--surface-hover)]">
                Contact Us
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── FOOTER ────────────────────────────────────────────────── */}
      <footer className="relative z-10 border-t border-[var(--border)] py-8">
        <div className="max-w-7xl mx-auto px-6 flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex flex-col items-center md:items-start gap-1">
            <span className="text-sm font-bold text-[var(--text-primary)]">CaseChain</span>
            <span className="text-xs text-[var(--text-muted)] font-medium">GST Litigation Document Management System</span>
          </div>
          <div className="flex items-center gap-6 text-xs font-medium text-[var(--text-muted)]">
            <Link href="/login" className="inline-flex min-h-11 items-center transition-colors hover:text-[var(--text-primary)]">Login</Link>
            <Link href="/signup" className="inline-flex min-h-11 items-center transition-colors hover:text-[var(--text-primary)]">Sign Up</Link>
            <Link href="/contact" className="inline-flex min-h-11 items-center transition-colors hover:text-[var(--text-primary)]">Contact</Link>
          </div>
          <p className="text-xs text-[var(--text-muted)] font-medium">© 2026 Project CaseChain. All rights reserved.</p>
        </div>
      </footer>
    </div>
  )
}

/* ─── Sub-components ────────────────────────────────────────────── */

function SmallFeatureCard({
  icon: Icon,
  color,
  title,
  summary,
}: {
  icon: React.ElementType
  color: string
  title: string
  summary: string
}) {
  return (
    <div className="rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] p-6 hover:shadow-md hover:border-[var(--primary)]/50 transition-all duration-300 group">
      <div className="w-9 h-9 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--bg)] flex items-center justify-center mb-4 group-hover:scale-105 transition-transform">
        <Icon size={18} className={color} />
      </div>
      <h3 className="text-base font-bold text-[var(--text-primary)] mb-1.5">{title}</h3>
      <p className="text-xs text-[var(--text-secondary)] font-medium leading-relaxed">{summary}</p>
    </div>
  )
}
