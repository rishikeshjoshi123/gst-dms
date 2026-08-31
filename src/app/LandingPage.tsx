import Link from 'next/link'
import {
  ArrowDown,
  ArrowRight,
  BookOpenText,
  CalendarClock,
  Check,
  FileStack,
  Link2,
  Quote,
  Search,
  ShieldCheck,
} from 'lucide-react'
import { ThemeToggle } from '@/components/nav/ThemeToggle'
import { Badge } from '@/components/ui/badge'
import { LandingParallaxImage } from './LandingParallaxImage'

const MATTER_STEPS = [
  {
    date: '14 Jul 2023',
    kind: 'Notice',
    title: 'Show Cause Notice · DRC-01',
    detail: 'Demand raised · Reply window opened',
  },
  {
    date: '12 Aug 2023',
    kind: 'Reply',
    title: 'Taxpayer submission · DRC-06',
    detail: 'Filed with reconciliation evidence',
  },
  {
    date: '20 Oct 2023',
    kind: 'Order',
    title: 'Order-in-Original · DRC-07',
    detail: 'Partial demand confirmed',
  },
  {
    date: '18 Dec 2023',
    kind: 'Appeal',
    title: 'Appeal filed · APL-01',
    detail: 'Current proceeding · Hearing awaited',
  },
]

const PRACTICE_PRINCIPLES = [
  {
    icon: Quote,
    title: 'Keep the source beside the conclusion.',
    body: 'When a summary names an amount, date, allegation, or conclusion, the underlying document remains close enough for the team to inspect, challenge, and cite.',
  },
  {
    icon: ShieldCheck,
    title: 'Keep judgement human.',
    body: 'CaseChain organises the record, reveals relationships, and surfaces what needs attention. Legal interpretation and the decision to act remain explicit work for your team.',
  },
  {
    icon: BookOpenText,
    title: 'Keep knowledge with the practice.',
    body: 'A matter records not only what was filed, but why the current position exists—so ownership can change without forcing the next person to rediscover the case.',
  },
]

function BrandWordmark({ inverted = false }: { inverted?: boolean }) {
  return (
    <span
      className={`inline-flex items-center text-[15px] font-semibold tracking-[-0.02em] ${
        inverted ? 'text-[var(--on-sidebar)]' : 'text-[var(--text-primary)]'
      }`}
    >
      CaseChain
    </span>
  )
}

export function LandingPage() {
  return (
    <main className="overflow-x-clip bg-[var(--bg)] text-[var(--text-primary)]">
      <section className="relative isolate min-h-[800px] overflow-hidden bg-[var(--surface)] sm:min-h-[760px] lg:min-h-[100svh]">
        <LandingParallaxImage
          src="/images/brand/casechain-hero-office-v2.webp"
          alt=""
          preload
          unoptimized
          sizes="100vw"
          speed={0.032}
          className="object-[64%_center] sm:object-center"
        />

        <div className="relative z-10 mx-auto flex min-h-[800px] w-full max-w-[1440px] items-end sm:min-h-[760px] sm:items-center sm:px-8 lg:min-h-[100svh] lg:px-10">
          <div className="landing-hero-copy w-full border-t border-[var(--border-strong)] bg-[color-mix(in_srgb,var(--surface)_70%,transparent)] px-5 pb-10 pt-8 text-[var(--text-primary)] sm:max-w-[640px] sm:rounded-[var(--radius-md)] sm:border sm:p-8 lg:p-10">
            <BrandWordmark />
            <p className="mb-4 mt-8 text-xs font-semibold uppercase tracking-[0.12em] text-[var(--text-muted)] sm:mt-10">
              GST litigation, in one connected record
            </p>
            <h1 className="max-w-2xl text-[clamp(2.75rem,4.8vw,4.25rem)] font-semibold leading-[0.98] tracking-[-0.045em] text-balance">
              Follow the matter. Not the folders.
            </h1>
            <div className="mt-7 max-w-xl border-t border-[var(--border)] pt-5">
              <p className="text-base leading-7 text-[var(--text-secondary)]">
                CaseChain keeps every notice, reply, order, deadline, and source in its place—so your team can see the proceeding and move with confidence.
              </p>
              <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
                <Link
                  href="/signup"
                  className="inline-flex min-h-11 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--primary)] bg-[var(--primary)] px-5 text-sm font-medium text-[var(--on-accent)] transition-colors hover:bg-[var(--primary-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--surface)]"
                >
                  Create workspace
                  <ArrowRight aria-hidden="true" className="size-4" />
                </Link>
                <Link
                  href="#the-matter"
                  className="inline-flex min-h-11 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-5 text-sm font-medium text-[var(--text-primary)] transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--surface)]"
                >
                  Explore the record
                  <ArrowDown aria-hidden="true" className="size-4" />
                </Link>
              </div>
              <p className="mt-4 text-sm text-[var(--text-secondary)]">
                Already using CaseChain?{' '}
                <Link href="/login" className="inline-flex min-h-11 items-center font-medium text-[var(--primary)] underline-offset-4 hover:underline">
                  Sign in
                </Link>
              </p>
            </div>
          </div>
        </div>

      </section>

      <section id="the-matter" className="scroll-mt-8 px-5 py-20 sm:px-8 sm:py-24 lg:px-10 lg:py-28">
        <div className="mx-auto grid max-w-7xl gap-8 lg:grid-cols-[0.34fr_1fr] lg:gap-12">
          <div>
            <p className="font-mono text-xs font-medium uppercase tracking-[0.1em] text-[var(--text-muted)]">
              01 · The connected matter
            </p>
            <p className="mt-5 max-w-xs text-sm leading-6 text-[var(--text-muted)]">
              Files can be perfectly organised and still leave the proceeding impossible to understand.
            </p>
          </div>
          <div>
            <h2 className="max-w-4xl text-[clamp(2.25rem,4vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
              A folder tells you where a file is. It does not tell you what happened.
            </h2>
            <div className="mt-8 grid gap-6 border-t border-[var(--border)] pt-6 sm:grid-cols-2 sm:gap-8">
              <p className="text-base leading-7 text-[var(--text-secondary)]">
                A tax dispute is an argument unfolding across years—through notices, submissions, orders, evidence, and appeal windows.
              </p>
              <p className="text-base leading-7 text-[var(--text-secondary)]">
                CaseChain preserves that sequence as a living matter, not a pile of isolated PDFs. The record becomes easier to read, hand over, and act on.
              </p>
            </div>

            <div className="mt-10 grid items-stretch gap-4 lg:grid-cols-[1fr_auto_1fr]">
              <article className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-5 sm:p-6">
                <div className="flex items-start gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--bg-overlay)] text-[var(--text-muted)]">
                    <FileStack aria-hidden="true" className="size-4" />
                  </span>
                  <div>
                    <p className="text-xs font-medium text-[var(--text-muted)]">A folder view</p>
                    <h3 className="mt-1 text-base font-semibold">The documents are present.</h3>
                  </div>
                </div>
                <div className="mt-6 space-y-2" aria-label="Disconnected document examples">
                  {['DRC-01-notice.pdf', 'reply-final-v3.pdf', 'order-scan.pdf'].map((file, index) => (
                    <div
                      key={file}
                      className="flex min-h-11 items-center justify-between gap-4 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] px-3"
                    >
                      <span className="min-w-0 truncate font-mono text-xs text-[var(--text-secondary)]">{file}</span>
                      <span className="font-mono text-[11px] text-[var(--text-disabled)]">0{index + 1}</span>
                    </div>
                  ))}
                </div>
                <p className="mt-5 border-t border-[var(--border)] pt-4 text-sm leading-6 text-[var(--text-muted)]">
                  But the relationship between them still lives in someone&apos;s memory.
                </p>
              </article>

              <div className="flex items-center justify-center text-[var(--text-muted)]" aria-hidden="true">
                <ArrowRight className="size-5 rotate-90 lg:rotate-0" />
              </div>

              <article className="rounded-[var(--radius-md)] border border-[var(--sidebar-border)] bg-[var(--sidebar-bg)] p-5 text-[var(--on-sidebar)] sm:p-6">
                <div className="flex items-start gap-3">
                  <span className="flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--sidebar-active)] text-[var(--on-sidebar)]">
                    <Link2 aria-hidden="true" className="size-4" />
                  </span>
                  <div>
                    <p className="text-xs font-medium text-[var(--sidebar-text)]">A matter view</p>
                    <h3 className="mt-1 text-base font-semibold">The proceeding becomes legible.</h3>
                  </div>
                </div>
                <ol className="mt-6 space-y-2" aria-label="Connected proceeding examples">
                  {[
                    ['14 Jul 2023', 'Notice received'],
                    ['12 Aug 2023', 'Reply filed with evidence'],
                    ['20 Oct 2023', 'Order creates appeal window'],
                  ].map(([date, event], index) => (
                    <li
                      key={event}
                      className="grid min-h-11 grid-cols-[24px_1fr] items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--sidebar-border)] bg-[var(--sidebar-hover)] px-3"
                    >
                      <span className="font-mono text-[11px] text-[var(--sidebar-accent)]">0{index + 1}</span>
                      <span className="text-xs text-[var(--sidebar-text)]">
                        <time className="font-mono">{date}</time> · {event}
                      </span>
                    </li>
                  ))}
                </ol>
                <p className="mt-5 border-t border-[var(--sidebar-border)] pt-4 text-sm leading-6 text-[var(--sidebar-text)]">
                  Every event carries its source, consequence, and next question with it.
                </p>
              </article>
            </div>
          </div>
        </div>
      </section>

      <section className="border-y border-[var(--border)] bg-[var(--surface)] px-5 py-20 sm:px-8 sm:py-24 lg:px-10">
        <div className="mx-auto grid max-w-7xl overflow-hidden rounded-[var(--radius-lg)] border border-[var(--border-strong)] bg-[var(--bg)] lg:grid-cols-[0.96fr_1.04fr]">
          <div className="relative min-h-[420px] overflow-hidden border-b border-[var(--border)] sm:min-h-[520px] lg:min-h-[600px] lg:border-b-0 lg:border-r">
            <LandingParallaxImage
              src="/images/brand/casechain-matter-clarity.webp"
              alt="Two advocates arranging connected case papers into a clear chronological line"
              loading="eager"
              unoptimized
              speed={0.052}
              sizes="(min-width: 1024px) 54vw, 100vw"
            />
          </div>

          <div className="flex items-center bg-[var(--surface)] px-5 py-14 sm:px-8 sm:py-16 lg:px-10 xl:px-12">
            <div className="max-w-2xl">
              <p className="font-mono text-xs font-medium uppercase tracking-[0.1em] text-[var(--text-muted)]">
                02 · From notice to present position
              </p>
              <h2 className="mt-4 text-[clamp(2.25rem,3.6vw,3.25rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
                Make the chain visible.
              </h2>
              <p className="mt-5 text-base leading-7 text-[var(--text-secondary)]">
                GST litigation rarely arrives in a clean order. Notices refer to earlier proceedings, annexures arrive separately, replies are revised, and an order can open a deadline months after the first document entered the office.
              </p>
              <p className="mt-4 text-base leading-7 text-[var(--text-secondary)]">
                CaseChain does not flatten that history into a generic summary. It keeps each event in sequence and lets the team move from a position back to the source document that supports it.
              </p>
              <div className="mt-8 border-t border-[var(--border)] pt-6">
                <p className="text-xs font-medium text-[var(--text-muted)]">What becomes visible</p>
              </div>
              <ul className="mt-4 space-y-4" aria-label="CaseChain matter capabilities">
                {[
                  ['Sequence', 'See which notice prompted which reply, and which order changed the direction of the matter.'],
                  ['Source', 'Move from a date, amount, or conclusion directly back to the document the team can inspect.'],
                  ['Consequence', 'Keep hearing dates, appeal windows, open questions, and the present position in the same view.'],
                ].map(([label, detail]) => (
                  <li key={label} className="flex gap-3 text-sm leading-6 text-[var(--text-secondary)]">
                    <span className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border)] bg-[var(--accent-muted)] text-[var(--accent)]">
                      <Check aria-hidden="true" className="size-3.5" />
                    </span>
                    <span>
                      <strong className="font-semibold text-[var(--text-primary)]">{label}.</strong> {detail}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section id="product" className="px-5 py-20 sm:px-8 sm:py-24 lg:px-10 lg:py-28">
        <div className="mx-auto max-w-7xl">
          <div className="grid gap-6 lg:grid-cols-[0.9fr_1.1fr] lg:items-end lg:gap-12">
            <div>
              <p className="font-mono text-xs font-medium uppercase tracking-[0.1em] text-[var(--text-muted)]">
                03 · One living record
              </p>
              <h2 className="mt-4 text-[clamp(2.25rem,4vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
                The whole proceeding, without the archaeology.
              </h2>
            </div>
            <div className="max-w-2xl space-y-4 text-base leading-7 text-[var(--text-secondary)] lg:justify-self-end">
              <p>
                An incoming document becomes useful only when the team knows the client, matter, proceeding stage, dates, amounts, and source context it belongs to.
              </p>
              <p>
                CaseChain carries that structure from intake into the chronology and the working record, so a colleague can continue the matter without reconstructing it from filenames and private notes.
              </p>
            </div>
          </div>

          <div className="mt-12 grid overflow-hidden rounded-[var(--radius-md)] border border-[var(--border-strong)] bg-[var(--surface)] shadow-[var(--shadow-xs)] lg:grid-cols-[0.78fr_1.22fr]">
            <div className="border-b border-[var(--border)] p-5 sm:p-7 lg:border-b-0 lg:border-r lg:p-8">
              <div className="flex items-center justify-between gap-4 border-b border-[var(--border)] pb-5">
                <div>
                  <p className="text-xs font-medium text-[var(--text-muted)]">
                    Illustrative matter
                  </p>
                  <h3 className="mt-1 text-lg font-semibold tracking-[-0.02em]">Input tax credit dispute</h3>
                </div>
                <Badge variant="warning" fixedWidth="lg" className="shrink-0">
                  Appeal active
                </Badge>
              </div>

              <dl className="grid grid-cols-2 gap-x-6 gap-y-7 py-7">
                <div>
                  <dt className="text-xs text-[var(--text-muted)]">Financial year</dt>
                  <dd className="mt-1 font-mono text-sm font-medium">2021–22</dd>
                </div>
                <div>
                  <dt className="text-xs text-[var(--text-muted)]">Current exposure</dt>
                  <dd className="mt-1 font-mono text-sm font-medium">₹14,20,000</dd>
                </div>
                <div>
                  <dt className="text-xs text-[var(--text-muted)]">Documents</dt>
                  <dd className="mt-1 font-mono text-sm font-medium">18 connected</dd>
                </div>
                <div>
                  <dt className="text-xs text-[var(--text-muted)]">Next milestone</dt>
                  <dd className="mt-1 text-sm font-medium">Hearing awaited</dd>
                </div>
              </dl>

              <div className="grid gap-2 border-t border-[var(--border)] pt-5 sm:grid-cols-3 lg:grid-cols-1 xl:grid-cols-3">
                {[
                  { icon: FileStack, label: 'Review documents' },
                  { icon: Search, label: 'Search the record' },
                  { icon: CalendarClock, label: 'Check deadlines' },
                ].map(({ icon: Icon, label }) => (
                  <div
                    key={label}
                    className="flex min-h-16 items-center gap-3 rounded-[var(--radius-sm)] border border-[var(--border-subtle)] bg-[var(--bg)] px-4 py-3"
                  >
                    <Icon aria-hidden="true" className="size-4 shrink-0 text-[var(--accent)]" />
                    <span className="text-xs font-medium leading-5">{label}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="p-5 sm:p-7 lg:p-8">
              <div className="mb-6 flex items-center gap-3">
                <Link2 aria-hidden="true" className="size-4 text-[var(--accent)]" />
                <h3 className="text-sm font-semibold">Proceeding chronology</h3>
              </div>
              <ol className="relative">
                {MATTER_STEPS.map((step, index) => (
                  <li key={step.title} className="relative grid grid-cols-[32px_1fr] gap-4 pb-7 last:pb-0">
                    {index < MATTER_STEPS.length - 1 && (
                      <span
                        aria-hidden="true"
                        className="absolute left-[15px] top-8 h-[calc(100%-20px)] w-px bg-[var(--border-strong)]"
                      />
                    )}
                    <span className="relative z-10 flex size-8 items-center justify-center rounded-[var(--radius-full)] border border-[var(--border-strong)] bg-[var(--surface)] font-mono text-[11px] font-semibold text-[var(--text-muted)]">
                      {String(index + 1).padStart(2, '0')}
                    </span>
                    <article className="rounded-[var(--radius-md)] border border-[var(--border-subtle)] bg-[var(--bg)] p-4 sm:flex sm:items-center sm:justify-between sm:gap-6">
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                          <span className="text-xs font-semibold uppercase tracking-[0.1em] text-[var(--accent)]">
                            {step.kind}
                          </span>
                          <time className="font-mono text-xs text-[var(--text-muted)]">{step.date}</time>
                        </div>
                        <h4 className="mt-2 text-sm font-semibold sm:text-base">{step.title}</h4>
                        <p className="mt-1 text-xs leading-5 text-[var(--text-muted)] sm:text-sm">{step.detail}</p>
                      </div>
                      {index === MATTER_STEPS.length - 1 && (
                        <Badge variant="default" className="mt-3 w-fit sm:mt-0">
                          Current
                        </Badge>
                      )}
                    </article>
                  </li>
                ))}
              </ol>
            </div>
          </div>
        </div>
      </section>

      <section className="border-y border-[var(--border)] bg-[var(--surface)] px-5 py-20 sm:px-8 sm:py-24 lg:px-10">
        <div className="mx-auto grid max-w-7xl overflow-hidden rounded-[var(--radius-lg)] border border-[var(--border-strong)] lg:grid-cols-[1.08fr_0.92fr]">
          <div className="relative min-h-[400px] border-b border-[var(--sidebar-border)] sm:min-h-[500px] lg:min-h-[560px] lg:border-b-0 lg:border-r">
            <LandingParallaxImage
              src="/images/brand/casechain-record-continuity.png"
              alt="An illuminated open case record in a quiet archive after rain"
              loading="eager"
              unoptimized
              speed={0.045}
              sizes="(min-width: 1024px) 54vw, 100vw"
              className="object-[62%_center] sm:object-center"
            />
          </div>
          <div className="flex items-center bg-[var(--sidebar-bg)] px-5 py-14 text-[var(--on-sidebar)] sm:px-8 sm:py-16 lg:px-10 xl:px-12">
            <div className="max-w-xl">
              <p className="font-mono text-xs font-medium uppercase tracking-[0.1em] text-[var(--sidebar-text)]">
                04 · Continuity is a feature
              </p>
              <h2 className="mt-4 text-[clamp(2.25rem,3.8vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
                Built for work that outlasts an inbox.
              </h2>
              <div className="mt-6 space-y-4 border-l border-[var(--sidebar-accent)] pl-5 text-base leading-7 text-[var(--sidebar-text)]">
                <p>
                  Files change hands. Teams grow. Hearings return months later. The knowledge of the matter should still be there—ordered, sourced, and ready to continue.
                </p>
                <p>
                  A useful handover should reveal the present position, the evidence relied on, the questions still open, and the next procedural risk—not merely provide access to the same folders.
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="px-5 py-20 sm:px-8 sm:py-24 lg:px-10 lg:py-28">
        <div className="mx-auto max-w-7xl">
          <div className="max-w-4xl">
            <p className="font-mono text-xs font-medium uppercase tracking-[0.1em] text-[var(--text-muted)]">
              05 · Designed around legal judgement
            </p>
            <h2 className="mt-4 text-[clamp(2.25rem,4vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
              Less noise between the record and the decision.
            </h2>
          </div>
          <div className="mt-10 grid gap-4 md:grid-cols-3">
            {PRACTICE_PRINCIPLES.map(({ icon: Icon, title, body }) => (
              <article
                key={title}
                className="rounded-[var(--radius-md)] border border-[var(--border)] bg-[var(--surface)] p-6 sm:p-7"
              >
                <span className="flex size-9 items-center justify-center rounded-[var(--radius-sm)] bg-[var(--accent-muted)] text-[var(--accent)]">
                  <Icon aria-hidden="true" className="size-4" />
                </span>
                <h3 className="mt-6 max-w-xs text-lg font-semibold leading-6 tracking-[-0.02em]">{title}</h3>
                <p className="mt-3 max-w-sm text-sm leading-6 text-[var(--text-secondary)]">
                  {body}
                </p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="border-t border-[var(--border)] bg-[var(--surface)] px-5 py-20 sm:px-8 sm:py-24 lg:px-10">
        <div className="mx-auto max-w-7xl rounded-[var(--radius-lg)] border border-[var(--border-strong)] bg-[var(--bg)] p-6 sm:p-8 lg:p-10">
          <div className="grid gap-8 lg:grid-cols-[1fr_auto] lg:items-end">
            <div className="max-w-4xl">
              <p className="text-xs font-medium text-[var(--text-muted)]">
                Your next matter can begin here
              </p>
              <h2 className="mt-3 text-[clamp(2.25rem,4vw,3.5rem)] font-semibold leading-[1.06] tracking-[-0.04em] text-balance">
                Begin with the matter in front of you.
              </h2>
            </div>
            <div className="flex flex-col gap-3 sm:flex-row lg:flex-col xl:flex-row">
              <Link
                href="/signup"
                className="inline-flex min-h-11 items-center justify-center gap-2 rounded-[var(--radius-sm)] border border-[var(--primary)] bg-[var(--primary)] px-5 text-sm font-medium text-[var(--on-accent)] transition-colors hover:bg-[var(--primary-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--bg)]"
              >
                Create your workspace
                <ArrowRight aria-hidden="true" className="size-4" />
              </Link>
              <Link
                href="/login"
                className="inline-flex min-h-11 items-center justify-center rounded-[var(--radius-sm)] border border-[var(--border-strong)] bg-[var(--surface)] px-5 text-sm font-medium transition-colors hover:bg-[var(--surface-hover)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--bg)]"
              >
                Return to CaseChain
              </Link>
            </div>
          </div>
        </div>
      </section>

      <footer className="border-t border-[var(--border)] bg-[var(--surface)] px-5 py-8 sm:px-8 lg:px-12">
        <div className="mx-auto flex max-w-7xl flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
          <BrandWordmark />
          <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
            <nav aria-label="Footer navigation" className="flex flex-wrap items-center gap-x-6 gap-y-3 text-sm text-[var(--text-muted)]">
              <Link href="/contact" className="min-h-11 content-center transition-colors hover:text-[var(--text-primary)]">
                Contact
              </Link>
              <Link href="/login" className="min-h-11 content-center transition-colors hover:text-[var(--text-primary)]">
                Sign in
              </Link>
              <span>© 2026 CaseChain</span>
            </nav>
            <ThemeToggle />
          </div>
        </div>
      </footer>
    </main>
  )
}
