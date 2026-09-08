'use client'

import Link from 'next/link'
import {
  Activity,
  CalendarClock,
  Clock3,
  FileKey2,
  Files,
  Info,
  IndianRupee,
  MoreHorizontal,
  StickyNote,
} from 'lucide-react'
import {
  buildMatterSectionHref,
  MATTER_PRIMARY_MOBILE_SECTIONS,
  MATTER_SECONDARY_MOBILE_SECTIONS,
  MATTER_SECTION_IDS,
  MATTER_SECTION_LABELS,
  type MatterSectionId,
} from '@/lib/matters/workspace-route'
import { cn } from '@/lib/utils'
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'

const SECTION_ICONS = {
  timeline: Clock3,
  files: Files,
  'case-brief': FileKey2,
  notes: StickyNote,
  deadlines: CalendarClock,
  financials: IndianRupee,
  activity: Activity,
  details: Info,
} satisfies Record<MatterSectionId, typeof Clock3>

function SectionLink({
  matterId,
  section,
  activeSection,
  entries,
  className,
}: {
  matterId: string
  section: MatterSectionId
  activeSection: MatterSectionId
  entries: Array<[string, string]>
  className?: string
}) {
  const Icon = SECTION_ICONS[section]
  const active = section === activeSection
  return (
    <Link
      href={buildMatterSectionHref(matterId, entries, section)}
      aria-current={active ? 'page' : undefined}
      className={cn(
        'flex min-h-11 min-w-0 items-center justify-center gap-2 rounded-[var(--radius-sm)] px-3 text-sm font-medium',
        'transition-colors duration-[var(--duration-fast)] ease-[var(--ease-smooth)]',
        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',
        active
          ? 'bg-[var(--primary-muted)] text-[var(--primary)]'
          : 'text-[var(--text-secondary)] hover:bg-[var(--surface-hover)] hover:text-[var(--text-primary)]',
        className,
      )}
    >
      <Icon size={16} aria-hidden="true" className="shrink-0" />
      <span className="truncate">{MATTER_SECTION_LABELS[section]}</span>
    </Link>
  )
}

export function MatterSectionNavigation({
  matterId,
  activeSection,
  entries,
}: {
  matterId: string
  activeSection: MatterSectionId
  entries: Array<[string, string]>
}) {
  const activeSecondary = MATTER_SECONDARY_MOBILE_SECTIONS.find((section) => section === activeSection)

  return (
    <>
      <nav
        aria-label="Matter sections"
        className="hidden shrink-0 grid-cols-8 gap-1 border border-[var(--border)] bg-[var(--surface)] p-1 shadow-[var(--shadow-sm)] md:grid"
      >
        {MATTER_SECTION_IDS.map((section) => (
          <SectionLink
            key={section}
            matterId={matterId}
            section={section}
            activeSection={activeSection}
            entries={entries}
          />
        ))}
      </nav>

      <nav
        aria-label="Matter sections"
        className="fixed inset-x-0 bottom-0 z-40 grid h-[68px] grid-cols-5 border-t border-[var(--border-strong)] bg-[var(--surface)] px-1 pb-[env(safe-area-inset-bottom)] shadow-[var(--shadow-lg)] md:hidden"
      >
        {MATTER_PRIMARY_MOBILE_SECTIONS.map((section) => (
          <SectionLink
            key={section}
            matterId={matterId}
            section={section}
            activeSection={activeSection}
            entries={entries}
            className="flex-col gap-0.5 px-1 text-[11px]"
          />
        ))}

        <Dialog>
          <DialogTrigger asChild>
            <button
              type="button"
              aria-current={activeSecondary ? 'page' : undefined}
              aria-label={activeSecondary
                ? `More matter sections, current section ${MATTER_SECTION_LABELS[activeSecondary]}`
                : 'More matter sections'}
              className={cn(
                'flex min-h-11 min-w-0 flex-col items-center justify-center gap-0.5 rounded-[var(--radius-sm)] px-1 text-[11px] font-medium',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent-ring)]',
                activeSecondary ? 'bg-[var(--primary-muted)] text-[var(--primary)]' : 'text-[var(--text-secondary)]',
              )}
            >
              <MoreHorizontal size={17} aria-hidden="true" />
              <span>More</span>
            </button>
          </DialogTrigger>
          <DialogContent
            showClose
            className="top-auto bottom-0 max-w-none translate-y-0 rounded-b-none px-4 pb-[calc(1rem+env(safe-area-inset-bottom))] sm:max-w-none"
          >
            <DialogHeader>
              <DialogTitle>More matter sections</DialogTitle>
              <DialogDescription>
                {activeSecondary
                  ? `${MATTER_SECTION_LABELS[activeSecondary]} is the current section.`
                  : 'Choose another part of this matter.'}
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-1" role="list">
              {MATTER_SECONDARY_MOBILE_SECTIONS.map((section) => (
                <DialogClose asChild key={section}>
                  <SectionLink
                    matterId={matterId}
                    section={section}
                    activeSection={activeSection}
                    entries={entries}
                    className="justify-start"
                  />
                </DialogClose>
              ))}
            </div>
          </DialogContent>
        </Dialog>
      </nav>
    </>
  )
}
