export type ConceptEntry = {
  href: `/dev/${string}-concept`
  title: string
  description: string
  reviewFocus: string
}

export type ConceptGroup = {
  id: string
  step: string
  title: string
  description: string
  concepts: ConceptEntry[]
}

export const conceptGroups: ConceptGroup[] = [
  {
    id: 'organisation',
    step: '01',
    title: 'Organisation and access',
    description: 'Start with the workspace structure, roles, and people lifecycle that govern every later workflow.',
    concepts: [
      {
        href: '/dev/organisation-admin-concept',
        title: 'Organisation administration',
        description: 'Settings for organisation identity, departments, roles, invitations, and member access.',
        reviewFocus: 'Information architecture, role clarity, and administrative actions.',
      },
      {
        href: '/dev/organisation-departure-team-concept',
        title: 'Organisation departure and Team',
        description: 'Team views and safeguarded departure handling for transferring open responsibilities.',
        reviewFocus: 'Ownership transfer, risk communication, and destructive-action safeguards.',
      },
    ],
  },
  {
    id: 'records',
    step: '02',
    title: 'Documents and matters',
    description: 'Follow a legal record from intake into its working Matter, knowledge, dates, and financial position.',
    concepts: [
      {
        href: '/dev/document-hub-workbench-concept',
        title: 'Document Hub and workbench',
        description: 'Organisation-wide document intake, placement, extraction review, and exact-source viewing.',
        reviewFocus: 'Queue density, split-pane behavior, and PDF workspace transitions.',
      },
      {
        href: '/dev/matter-workspace-concept',
        title: 'Matter workspace',
        description: 'The durable Matter shell for chronology, files, legal context, activity, and related work.',
        reviewFocus: 'Matter identity, navigation, timeline comprehension, and responsive structure.',
      },
      {
        href: '/dev/notes-case-brief-concept',
        title: 'Notes and case brief',
        description: 'Matter conversation and a sourced, living case orientation built from evidence.',
        reviewFocus: 'Authorship, citations, collaboration, and generated-versus-human content.',
      },
      {
        href: '/dev/deadlines-financials-concept',
        title: 'Deadlines and financials',
        description: 'Verified obligations, reminders, procedural milestones, and source-backed case values.',
        reviewFocus: 'Provenance, urgency, accountable ownership, and financial interpretation.',
      },
    ],
  },
  {
    id: 'work',
    step: '03',
    title: 'Work and decisions',
    description: 'Review how responsibilities move through individual work, discussion, and evidence-led resolution.',
    concepts: [
      {
        href: '/dev/tasks-workspace-concept',
        title: 'Tasks workspace',
        description: 'Personal and team task queues with ownership, priority, status, and due-date context.',
        reviewFocus: 'Scanability, filters, task selection, and lifecycle states.',
      },
      {
        href: '/dev/task-comments-concept',
        title: 'Task comments',
        description: 'A task-scoped conversation beside task details, history, and source context.',
        reviewFocus: 'Conversation rhythm, replies, read-only states, and long content.',
      },
      {
        href: '/dev/review-workspace-concept',
        title: 'Review workspace',
        description: 'A queue for human decisions where typed evidence and one resolver determine the outcome.',
        reviewFocus: 'Table density, decision context, and exact-source PDF review.',
      },
    ],
  },
  {
    id: 'retention',
    step: '04',
    title: 'Retention and deletion',
    description: 'Finish with recovery, retention policy, and the deliberately separate permanent-delete boundary.',
    concepts: [
      {
        href: '/dev/trash-workspace-concept',
        title: 'Trash workspace',
        description: 'Grouped deleted resources with inherited membership, impact context, and safe restoration.',
        reviewFocus: 'Hierarchy, recoverability, group selection, and read-only context.',
      },
      {
        href: '/dev/trash-retention-settings-concept',
        title: 'Trash retention settings',
        description: 'Organisation policy for manual-only retention or scheduled purge eligibility.',
        reviewFocus: 'Policy language, permissions, activation, and consequence clarity.',
      },
      {
        href: '/dev/trash-permanent-delete-concept',
        title: 'Trash permanent delete',
        description: 'A high-friction irreversible-delete flow kept separate from ordinary Trash actions.',
        reviewFocus: 'Authority, impact preview, confirmation, and irreversible consequences.',
      },
    ],
  },
]

export const conceptCount = conceptGroups.reduce((total, group) => total + group.concepts.length, 0)
