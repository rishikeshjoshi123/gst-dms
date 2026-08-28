// Public-reader summaries. These are intentionally separate from docs/plans,
// which remain the canonical, technical decision record.
export const plainLanguagePlans = {
  'docs/plans/platform/2026-08-24-product-architecture-portfolio.md': {
    overview: 'This is the master map for CaseChain. It explains how the parts of the product fit together so we can build them in a sensible order.',
    why: 'People should be able to trust where a fact came from, who made a decision, and what still needs attention.',
    outcomes: ['One shared foundation for documents, evidence, people, and work.', 'Clear product areas such as Today, Review, Search, and Matter Workspace.', 'A safe order for building features without creating duplicate systems.'],
    steps: ['Create trusted records', 'Add helpful workspaces', 'Connect them into one product'],
  },
  'docs/plans/design-system/2026-08-20-casechain-design-system-overhaul.md': {
    overview: 'We are giving CaseChain a calmer, clearer visual language that works equally well on a desktop or phone.',
    why: 'Legal work is detailed. The interface should make important information easy to scan, not compete for attention.',
    outcomes: ['A consistent look and feel across the product.', 'Accessible colours, readable type, and clear controls.', 'Layouts that adapt the task for smaller screens instead of just shrinking.'],
    steps: ['Set shared design rules', 'Update common building blocks', 'Apply and check across screens'],
  },
  'docs/plans/platform/2026-08-26-organisation-administration.md': {
    overview: 'This plan makes team membership, roles, invitations, company settings, and personal settings straightforward and safe.',
    why: 'Everyone should know what access they have, while account history stays intact when people join, change roles, or leave.',
    outcomes: ['A clear Team area for people and invitations.', 'Simple organisation and personal settings.', 'Carefully recorded changes to access and ownership.'],
    steps: ['Define roles and access', 'Build team and settings pages', 'Record changes safely'],
  },
  'docs/plans/platform/2026-08-24-document-record-and-file-lifecycle.md': {
    overview: 'A case document and its PDF will be treated as related but separate things, so a file can be updated without losing the case history around it.',
    why: 'A document may be known before its PDF arrives, and later versions must not break notes, links, or the timeline.',
    outcomes: ['Every PDF is stored once, privately and safely.', 'File versions keep their history and evidence links.', 'All uploads follow the same dependable path.'],
    steps: ['Receive a file', 'Check and analyse it', 'Place it in the right case'],
  },
  'docs/plans/platform/2026-08-24-resource-trash-retention-and-purge.md': {
    overview: 'CaseChain will have a proper Trash where deleted clients, matters, and documents can be reviewed and restored before anything is permanently removed.',
    why: 'Accidental deletion should be recoverable, and permanent removal needs a clear, controlled process.',
    outcomes: ['Deleted items stay grouped as they were in the case.', 'Teams can restore an entire deletion safely.', 'Only authorised people can permanently remove data after a clear warning.'],
    steps: ['Move a group to Trash', 'Review the impact', 'Restore or permanently remove'],
  },
  'docs/plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md': {
    overview: 'AI can help read documents, but every suggestion must point back to the page and words it came from, and people always make the final call.',
    why: 'AI output must be useful without quietly changing legal records or hiding uncertainty.',
    outcomes: ['Suggestions include their original document evidence.', 'Human corrections stay in charge, even after a re-check.', 'AI models can improve over time without damaging existing information.'],
    steps: ['Read the source', 'Show evidence-backed suggestions', 'Confirm with human review'],
  },
  'docs/plans/features/2026-08-25-work-review-activity-notifications.md': {
    overview: 'This creates one clear home for work: tasks to do, decisions that need review, updates that happened, and alerts that genuinely need attention.',
    why: 'People should not have to hunt across dashboards and messages to know what to do next.',
    outcomes: ['A focused Today page for urgent and assigned work.', 'Separate spaces for tasks, reviews, history, and notifications.', 'Alerts based on responsibility and real risk rather than noise.'],
    steps: ['Collect work signals', 'Sort by urgency', 'Help the right person act'],
  },
  'docs/plans/features/2026-08-25-document-hub-ingestion-and-workbench.md': {
    overview: 'Document Hub will guide every file from upload to a well-understood, evidence-backed place in a matter, with a single reader workspace throughout.',
    why: 'Filing a document in the wrong case can cause real confusion, so automatic suggestions must be cautious and easy to review.',
    outcomes: ['One reliable path for every kind of upload.', 'Clear suggestions rather than hidden automatic filing.', 'A shared workspace to read PDFs, evidence, details, and decisions.'],
    steps: ['Upload once', 'Check the evidence', 'Confirm the right home'],
  },
  'docs/plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md': {
    overview: 'The Matter page will become the central place to understand a case: its key documents, important dates, notes, financial position, and next actions.',
    why: 'A case should tell a coherent story, instead of making people jump between unrelated tabs.',
    outcomes: ['A stable case header and clear sections.', 'A timeline that shows meaningful procedural connections.', 'A useful evidence library that works on desktop and mobile.'],
    steps: ['Keep the case context visible', 'Show the procedural story', 'Open the supporting evidence'],
  },
  'docs/plans/features/2026-08-25-notes-and-case-brief.md': {
    overview: 'Teams will have a professional place to discuss a matter, plus a short Case Brief that explains the current situation with links to supporting evidence.',
    why: 'Conversation and a formal case summary serve different jobs, so each needs a clear home.',
    outcomes: ['Threaded notes with people, document quotes, and tasks.', 'A concise, evidence-linked Case Brief.', 'Human edits are protected while useful updates are highlighted for review.'],
    steps: ['Discuss the matter', 'Capture key context', 'Review evidence-backed changes'],
  },
  'docs/plans/features/2026-08-26-deadlines-and-financials.md': {
    overview: 'Important legal dates and financial developments will be tracked with their source evidence, responsible person, and review status.',
    why: 'Deadlines and money figures need to be clear, traceable, and never guessed by the system.',
    outcomes: ['Verified deadlines alongside normal work due dates.', 'A history of financial positions as a case changes.', 'Fast links back to the exact source document.'],
    steps: ['Find a date or figure', 'Verify its source', 'Track what changes next'],
  },
  'docs/plans/features/2026-08-24-universal-search-and-evidence-retrieval.md': {
    overview: 'Search will help people find a case, document, legal reference, or supporting fact across their organisation, with a clear explanation of each result.',
    why: 'A search result is only helpful when people can see why it was found and where the evidence lives.',
    outcomes: ['One search entry point across the app.', 'Results for exact terms, structured facts, and related evidence.', 'Direct links to the document and page behind each result.'],
    steps: ['Ask a question', 'Find likely evidence', 'Open the exact source'],
  },
  'docs/plans/platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md': {
    overview: 'CaseChain will show important live updates when they help people work together, while being honest if a connection is out of date.',
    why: 'Instant updates are helpful for active work, but they must never replace the dependable saved record.',
    outcomes: ['Live updates only for the places that benefit from them.', 'Clear signals when information may need refreshing.', 'Personal unread markers for notes and mentions.'],
    steps: ['Save the trusted record', 'Send a helpful update', 'Refresh safely when needed'],
  },
  'docs/plans/platform/2026-08-27-platform-operations.md': {
    overview: 'This sets up a tightly controlled operations area for running the service safely without exposing customer legal content.',
    why: 'Supporting the platform needs strong safeguards, clear audit trails, cost controls, and proven recovery procedures.',
    outcomes: ['Separate, protected access for platform operators.', 'Clear health, cost, quota, and alert information.', 'A tested backup-and-restore process before wider rollout.'],
    steps: ['Protect operational access', 'Monitor safely', 'Prove recovery works'],
  },
  'docs/plans/operations/2026-08-27-project-portal-and-github-pages.md': {
    overview: 'This public portal makes the project plan easy for friends and reviewers to follow without changing the live CaseChain product.',
    why: 'People deserve a clear view of what is planned, what is underway, and what has not shipped yet.',
    outcomes: ['A fast, public site built from the plan archive.', 'Clear status labels that do not overstate progress.', 'A separate deployment path from the main application.'],
    steps: ['Read the plan archive', 'Create the public pages', 'Publish the review site'],
  },
};
