// Human-edited public articles. The canonical technical contracts continue to
// live in docs/plans; this layer explains their intent to a broader audience.
export const planArticles = {
  'docs/plans/platform/2026-08-24-product-architecture-portfolio.md': {
    deck: 'CaseChain is becoming one connected workspace for GST litigation, rather than a collection of useful but separate screens.',
    intro: 'This portfolio is the map for that change. It explains which parts of the product own documents, evidence, decisions and day-to-day work, so every new feature strengthens the same system.',
    flowCaption: 'How the product comes together',
    flow: ['Build trusted records', 'Create focused workspaces', 'Connect the whole case journey'],
    sections: [
      { heading: 'Why the product needs a shared map', paragraphs: [
        'Legal work rarely stays inside one screen. A document arrives, facts are extracted, a person checks them, a deadline is created and the matter timeline changes. If each page invents its own version of those facts, the product becomes difficult to trust and even harder to improve.',
        'The portfolio gives each kind of information a clear home. Files remain immutable evidence. AI produces suggestions, not unquestioned facts. Human decisions are recorded separately. Pages such as Today, Review, Search and the Matter Workspace then present the right view of that shared information.',
      ]},
      { heading: 'What CaseChain will feel like', paragraphs: [
        'A user will be able to begin with the question in front of them instead of thinking about the underlying database. Today will answer “what needs my attention?”, Search will answer “where is the evidence?”, and the Matter Workspace will answer “what is happening in this case?”.',
        'Behind those simple entry points are common services for documents, tasks, activity, permissions and evidence. That boundary matters: a deadline shown in Today is the same deadline shown inside its matter, not a copied reminder that can quietly drift out of date.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'The result is a product that can grow without fragmenting. Teams get a consistent vocabulary, engineers get clear ownership boundaries, and reviewers can trace a visible fact back through the human decision or source document that produced it.',
        'It also gives the implementation a sensible order. Foundations such as organisation access and document lifecycle come first; evidence, collaboration and workspaces build on top; operations and rollout controls make the system safe to expand.',
      ]},
    ],
  },
  'docs/plans/design-system/2026-08-20-casechain-design-system-overhaul.md': {
    deck: 'A dense legal workspace can still feel calm. The design-system plan gives CaseChain one visual language built for careful, everyday work.',
    intro: 'The goal is not a cosmetic refresh. It is to make important context easier to hold onto, actions easier to understand and the same work genuinely usable on a phone.',
    flowCaption: 'From design rules to dependable screens',
    flow: ['Define the visual language', 'Rebuild shared components', 'Apply and test every workflow'],
    sections: [
      { heading: 'Designing for concentration', paragraphs: [
        'GST matters contain long names, identifiers, dates, statuses and evidence. A loud interface makes that density tiring; an overly sparse one hides useful context. Civic Ink takes a middle path: warm neutral surfaces, deep ink navigation, restrained colour and compact layouts with clear hierarchy.',
        'Colour has a job rather than a decorative role. Green confirms success, amber asks for attention and red warns about failure or a destructive action. Text and icons carry the same meaning so the interface remains understandable without relying on colour alone.',
      ]},
      { heading: 'Keeping context while the work moves', paragraphs: [
        'Long documents and case histories need stable workspace chrome. The matter name, current state and primary actions stay available while the content beneath them scrolls. Split panes may move independently on desktop, but their headers remain anchored to the content they explain.',
        'On mobile, the task changes shape instead of losing features. Tables become focused lists, graphs become chronological views and secondary panels become drawers or drill-down pages. Touch targets remain large enough to use, even when the visual treatment stays compact.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Shared tokens and components make every screen feel related and reduce one-off design decisions. More importantly, they turn accessibility, responsive behaviour, loading states and error states into part of the component contract rather than cleanup work at the end.',
        'The finished system should feel authoritative without feeling severe: information-rich, predictable and quiet enough that the legal work remains the centre of attention.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-26-organisation-administration.md': {
    deck: 'People need a clear answer to three questions: who belongs to the organisation, what can they do, and what happens when their access changes.',
    intro: 'This plan separates team administration, organisation policy and personal preferences, while giving every important access change a durable history.',
    flowCaption: 'A safe membership lifecycle',
    flow: ['Invite or add a person', 'Grant the right capabilities', 'Change or remove access safely'],
    sections: [
      { heading: 'Untangling settings and access', paragraphs: [
        'The current Settings area mixes unrelated concerns. The new structure gives Team its own workspace for members and invitations, Organisation its own home for firm-wide policy, and My settings a straightforward page for profile, password, appearance and notifications.',
        'That separation makes the product easier to navigate, but it also clarifies authority. The organisation owner is an explicit role that can be transferred. Admins and members receive named capabilities, and matter-specific access can be granted without pretending every role is the same everywhere.',
      ]},
      { heading: 'What happens when someone joins or leaves', paragraphs: [
        'Invitations are time-limited, securely accepted and tied to the intended organisation. Role changes, suspension and removal are handled as complete transactions so the interface cannot show half-applied access. Removing a member preserves their historical activity rather than erasing their contribution from the record.',
        'For the controlled pilot, an ordinary user belongs to one active organisation. The misleading organisation switcher disappears until the product has a proper multi-organisation design.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Teams gain a directory they can understand and administrators gain controls they can use confidently. Every sensitive change is authorised on the server, recorded in the audit history and reflected consistently across invitations, matter access and personal settings.',
        'The result is a foundation that supports a small pilot today without blocking a more flexible organisation model later.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-24-document-record-and-file-lifecycle.md': {
    deck: 'A legal document is more than the PDF currently attached to it. CaseChain needs to preserve its identity even when the file arrives later or is replaced.',
    intro: 'This plan separates the lasting document record from each physical file version, then gives every upload one dependable path from intake to processing.',
    flowCaption: 'The life of a document',
    flow: ['Create or receive the document', 'Attach an immutable file version', 'Process and place it safely'],
    sections: [
      { heading: 'One document, several moments in time', paragraphs: [
        'A team may know about an order before it has the PDF. Later, a cleaner scan or corrected copy may replace the file. If CaseChain treats the file itself as the document, every replacement risks breaking notes, citations, timeline links and audit history.',
        'The new model gives the legal document a stable identity and stores each PDF as an immutable version. Notes and relationships can continue pointing to the document, while page-level evidence points to the exact version that was actually reviewed.',
      ]},
      { heading: 'A durable intake pipeline', paragraphs: [
        'Uploads from the global Inbox and from inside a matter will follow the same process. The file is validated, deduplicated within the organisation, stored privately and handed to durable background work. Assigning it to a matter changes a relationship in the database; it does not copy the file into another folder.',
        'Processing uses recorded work items that can be retried safely. A temporary failure no longer depends on a user pressing a vague Sync button, and repeating a stage does not create duplicate documents or duplicate analysis.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Users gain reliable uploads, honest processing states and safe file replacement. The rest of CaseChain gains stable evidence locators that Search, Notes, Case Brief, deadlines and financials can trust.',
        'It is a quiet architectural change with a large practical effect: the history of a case survives changes to its files.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-24-resource-trash-retention-and-purge.md': {
    deck: 'Deleting a matter should not behave like deleting a loose file. Its documents, history and relationships need to move together and remain recoverable.',
    intro: 'This plan introduces an organisation Trash that respects the Client → Matter → Document hierarchy and makes permanent removal a deliberate administrative act.',
    flowCaption: 'From removal to final decision',
    flow: ['Move a resource group to Trash', 'Review or restore it', 'Purge only with explicit authority'],
    sections: [
      { heading: 'Why ordinary delete is not enough', paragraphs: [
        'A matter sits inside a client and owns many dependent records. Deleting only the visible row would leave files, links and audit history in an uncertain state. Deleting everything immediately would make a simple mistake irreversible.',
        'CaseChain therefore treats one delete action as a grouped trash operation. If a client is moved to Trash, its active matters and documents move with it, but the Trash list shows the operation as one understandable event rather than hundreds of unrelated descendants.',
      ]},
      { heading: 'Restoration, retention and permanent removal', paragraphs: [
        'Items in Trash keep their familiar routes and nested navigation in a clearly read-only state. Restoring the operation brings back only the resources that action removed; it does not accidentally revive something that had already been deleted for another reason.',
        'Permanent purge is restricted to authorised administrators. Before it begins, CaseChain shows the impact and requires explicit confirmation. Cleanup follows dependency order, can resume after failure and respects retention settings and legal holds.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Ordinary users gain a forgiving recovery path, while organisations retain a controlled way to meet storage and retention responsibilities. The hierarchy remains understandable at every stage.',
        'Most importantly, storage pressure can never silently become a reason to destroy legal material. Permanent removal remains visible, authorised and auditable.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md': {
    deck: 'AI can accelerate document review, but only if every useful answer carries its evidence and every consequential decision remains under human control.',
    intro: 'This plan turns extraction from a one-off model response into a versioned, testable process that can improve without rewriting the legal record.',
    flowCaption: 'From PDF to trusted information',
    flow: ['Analyse the exact source file', 'Store evidence-backed candidates', 'Let rules and people decide what becomes effective'],
    sections: [
      { heading: 'The difference between a suggestion and a fact', paragraphs: [
        'When Gemini reads a notice or order, it may identify a reference number, financial year, amount or date. CaseChain will store each of those as a candidate with the page and quotation that support it. The model is helping the reviewer find information; it is not silently editing the matter.',
        'Deterministic validation checks formats, page bounds, dates and financial values before a candidate can be used. Routine, well-supported metadata may appear automatically. Ambiguous placement, deadline reminders and verified financial consequences always require a more deliberate decision.',
      ]},
      { heading: 'Keeping history when the model changes', paragraphs: [
        'Every extraction run records the source file, model, prompt, schema and catalogue versions that produced it. Re-running analysis creates a new comparison set instead of overwriting the old one. A human correction stays authoritative until another human intentionally changes it.',
        'Search embeddings follow the same discipline. Vectors from different models or dimensions are never mixed. A new index is built beside the working one, measured for coverage and relevance, and switched on organisation by organisation only after it is ready.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Reviewers get faster access to useful facts without losing provenance. Engineers can upgrade prompts and models against a frozen GST evaluation set, measure critical regressions and roll back safely.',
        'The lasting outcome is not “more AI”. It is a system where automation remains replaceable, evidence remains inspectable and a person remains the final authority over legal data.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-25-work-review-activity-notifications.md': {
    deck: 'CaseChain should help a person decide what to do next without turning every event into another notification.',
    intro: 'This plan separates work, review, history and interruption into distinct concepts, then brings the relevant pieces together in a focused Today page.',
    flowCaption: 'Turning activity into action',
    flow: ['Record what happened', 'Identify responsibility or risk', 'Show the right work to the right person'],
    sections: [
      { heading: 'Five ideas that should not be confused', paragraphs: [
        'Activity is the permanent history of what happened. A Task is owned work with a lifecycle. Review is a specific decision the system cannot make safely. A Notification is a personal interruption caused by direct responsibility or urgent risk. My Work and Today are views over those sources, not new copies of them.',
        'Keeping those meanings separate prevents a common failure in workflow products: the same event appearing as a dashboard card, a notification, a pending review and a note action item, each with a slightly different status.',
      ]},
      { heading: 'A Today page built around judgement', paragraphs: [
        'Today groups work using visible rules such as overdue, due soon, assigned review and failed processing. It does not invent an opaque AI priority score or fill the top of the page with vanity statistics.',
        'Dedicated workspaces still exist for organisation-wide Review, Activity and Notifications. Filters and counts come from secured server-side views, and every item links back to the exact matter, document, task or evidence that explains it.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'People gain a dependable command centre and quieter notifications. Managers can see work and review queues without confusing them with the historical audit trail.',
        'Because every surface reads from the same source state, completing a task or resolving a review updates the product consistently instead of leaving stale copies behind.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-25-document-hub-ingestion-and-workbench.md': {
    deck: 'Every document should have one understandable journey: arrive once, be checked carefully, and become useful evidence in the right matter.',
    intro: 'Document Hub brings uploads, processing, placement and document review into one operating model instead of scattering them across unrelated screens.',
    flowCaption: 'A document’s path through CaseChain',
    flow: ['Upload and validate', 'Analyse and suggest', 'Confirm placement and relationships'],
    sections: [
      { heading: 'One front door for every file', paragraphs: [
        'A file may arrive from the global Inbox, from inside a matter, as a replacement version or eventually from an external source. All of those routes will create the same upload session, immutable asset and processing record.',
        'The PDF is extracted once and never copied merely because its assignment changes. If a processing stage fails, CaseChain can resume that stage safely while the interface explains what is happening.',
      ]},
      { heading: 'Cautious placement and meaningful links', paragraphs: [
        'The system may confidently place a document when the user already chose the matter or the document contains one unique, high-authority anchor with no conflicting evidence. Names, filenames and semantic similarity can help rank suggestions, but they cannot quietly file the document on their own.',
        'The same caution applies to relationships. A citation inside a document is recorded as a source mention; it becomes a procedural timeline link only when the relationship is explicit and reliable. Ambiguous candidates go to Review, and rejected suggestions do not keep returning.',
      ]},
      { heading: 'The shared Document Workbench', paragraphs: [
        'Wherever a document is opened—from Intake, a matter, Search, Activity, Review or Trash—the same Workbench provides a continuous PDF reader, structured details, page-accurate quotations and decision tools. Desktop uses stable split panes; mobile preserves the same work through focused document, details, notes and decision views.',
        'The result is faster intake with fewer filing mistakes, a consistent reading experience and evidence that remains connected to every later decision.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-25-matter-workspace-and-procedural-timeline.md': {
    deck: 'A matter should read like a case, not a row of unrelated tabs.',
    intro: 'This plan turns the Matter page into the main evidence workspace: a stable place to understand identity, procedure, documents, notes, deadlines, money and recent activity.',
    flowCaption: 'How a matter tells its story',
    flow: ['Keep the case identity visible', 'Map the procedural sequence', 'Open the evidence behind each event'],
    sections: [
      { heading: 'A workspace that keeps its bearings', paragraphs: [
        'The matter name, status, scoped search, freshness and primary action stay in compact stable chrome while each section owns one clear content region. Deep links preserve the selected section and record, so returning to a case feels deliberate rather than reset.',
        'Timeline, Files, Case Brief, Notes, Deadlines, Financials, Activity and Details remain distinct tools, but they share the same matter identity and evidence contracts.',
      ]},
      { heading: 'A timeline about procedure, not decoration', paragraphs: [
        'The main timeline is a left-to-right map of proceeding documents and the evidence-backed relationships between them. It is not a generic file browser, a raw web of every citation or a chat feed. A chronology table provides an equally authoritative dense reading mode.',
        'On phones, the graph becomes a compact chronological list instead of shrinking into an unreadable canvas. Selecting an event opens a useful document inspector and then the shared Workbench when deeper reading is needed.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'A lawyer or reviewer can enter a matter and quickly understand where the case stands, how it moved from one procedural event to the next and which document supports each step.',
        'Supporting evidence remains available in Files without being mistaken for a procedural event, while notes, deadlines and financials add context without recreating the matter header in every section.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-25-notes-and-case-brief.md': {
    deck: 'A conversation about a case and the current understanding of that case are related, but they are not the same thing.',
    intro: 'This plan gives human collaboration a professional Notes workspace and replaces the old CaseWiki with a concise, cited Case Brief.',
    flowCaption: 'From discussion to shared understanding',
    flow: ['Discuss and cite evidence', 'Capture durable case context', 'Review meaningful brief changes'],
    sections: [
      { heading: 'Notes for the work in progress', paragraphs: [
        'Matter Notes support threads, chronological messages, mentions, exact document quotations and links to first-class tasks. They record how the team collaborates: a question, a hand-off, a comment on evidence or a decision that still needs work.',
        'A quotation is not pasted text with no origin. It carries a locator to the exact document version and page, so another person can open the evidence in context.',
      ]},
      { heading: 'A brief for the current position', paragraphs: [
        'The Case Brief is the curated reading layer for the matter. It explains the parties, current posture, important issues and verified developments in blocks that can be cited and reviewed. It does not pretend to be a chat transcript or an automatically written final opinion.',
        'Human writing remains protected. When source evidence changes, CaseChain updates unaffected material quietly and asks for review only where a meaningful conflict or change affects the brief.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'New team members can orient themselves without reading every note, while the people actively working on the case retain a rich discussion history. Search, permissions, activity and realtime delivery are shared, but the two experiences keep their distinct purpose.',
        'The outcome is a matter that can explain both how the team worked and what the team currently believes to be true.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-26-deadlines-and-financials.md': {
    deck: 'Dates and amounts carry legal consequences. CaseChain should show where they came from, what they mean and whether someone has verified them.',
    intro: 'This plan creates two evidence-centred areas: Deadlines for consequential dates and Financials for the changing monetary position of a proceeding.',
    flowCaption: 'From extracted value to trusted case context',
    flow: ['Find a date or amount', 'Open and verify its source', 'Track responsibility and later changes'],
    sections: [
      { heading: 'Deadlines are not ordinary task dates', paragraphs: [
        'A legal deadline may come from an order, notice or procedural rule. It needs a source, a responsible person, a verification state, completion history and reminders. An internal drafting target remains a Task due date even when both appear in the same agenda.',
        'Extraction may surface an explicit calendar date as a candidate, but the system will not invent a statutory limitation date from uncertain language. Consequential reminders begin only after the evidence and meaning are verified.',
      ]},
      { heading: 'Financials should show movement, not a magic total', paragraphs: [
        'GST proceedings contain proposals, taxpayer positions, findings, payments, pre-deposits, relief, refunds and adjustments. The plan stores those as versioned statements and typed line items, preserving their role and source instead of flattening every number into one raw metadata object.',
        'CaseChain then presents the financial evolution deterministically. It does not ask AI to draw an unexplained exposure graph or collapse legally different figures into a universal net amount.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Teams gain an agenda they can act on and a financial history they can defend. Each important value opens the exact evidence behind it and feeds Review, My Work, Today and Activity using the same verified state.',
        'The practical promise is simple: no important date or amount should appear without enough context to understand and challenge it.',
      ]},
    ],
  },
  'docs/plans/features/2026-08-24-universal-search-and-evidence-retrieval.md': {
    deck: 'Search should do more than find a filename. It should help a person locate the exact case fact or legal evidence they remember.',
    intro: 'This plan replaces the broken dashboard lookup with organisation-wide search that combines exact identifiers, structured filters, full text and semantic evidence retrieval.',
    flowCaption: 'From question to evidence',
    flow: ['Understand the search and its scope', 'Find exact and related results', 'Open the supporting page'],
    sections: [
      { heading: 'Different questions need different kinds of search', paragraphs: [
        'A GSTIN, reference number or exact amount should use precise matching. A request such as “orders discussing limitation after delayed service” needs full-text and semantic retrieval. A query limited to one matter or financial year needs structured filters that are validated rather than guessed.',
        'The search service combines those methods instead of forcing every query into one similarity score. Results explain why they matched and clearly identify the organisation, matter, document and page they belong to.',
      ]},
      { heading: 'A workspace for investigation', paragraphs: [
        'Search is available from the authenticated application shell, so it is never owned by one dashboard. The quick entry point can answer a direct lookup, while a dedicated workspace supports filters, result comparison and deeper evidence review.',
        'Opening a result goes to the shared Document Workbench at the relevant page. Exact and structured search continue to work if semantic embedding services are temporarily unavailable.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Users can move from a memory or legal question to inspectable evidence without hunting through matters one by one. The system remains honest about content that has not been indexed or cannot be read.',
        'The outcome is explainable retrieval: CaseChain helps find the evidence, but the reader can always see the source and decide whether it supports the point.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-25-realtime-delivery-freshness-and-unread-state.md': {
    deck: 'Live updates are valuable when two people are working on the same matter. They are dangerous when the interface starts treating a temporary connection as the source of truth.',
    intro: 'This plan uses realtime delivery selectively, keeps durable records authoritative and tells the user honestly when the screen may be out of date.',
    flowCaption: 'A safe live-update cycle',
    flow: ['Save the authoritative change', 'Broadcast a small update', 'Fetch fresh state when needed'],
    sections: [
      { heading: 'Realtime as a delivery hint', paragraphs: [
        'CaseChain first saves a change to its normal durable state. A compact private broadcast then tells the relevant user, matter or queue that something changed. The receiving screen can update in place or refetch the trusted record.',
        'If a message is missed, nothing is lost. Realtime is not a job queue, an audit log or a replacement for a normal server fetch. That distinction lets the product recover naturally after sleep, reconnect or a dropped network.',
      ]},
      { heading: 'Where immediacy is worth the cost', paragraphs: [
        'The initial live surfaces are places where delay causes confusion: active document processing, shared notes, review queues and selected matter context. Broad database subscriptions are replaced with scoped topics so users receive only the signals they are allowed to see.',
        'The interface shows whether the connection is live, reconnecting or stale. Unread notes and mentions use explicit per-user cursors, so “New” means the user has not read the item rather than merely that it arrived recently.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Collaboration feels responsive without making correctness depend on a websocket. Privacy boundaries remain clear, resource use stays controlled and a reconnect cannot silently erase unread state.',
        'Users gain the convenience of live work and the confidence that refreshing the page will always return to the authoritative truth.',
      ]},
    ],
  },
  'docs/plans/platform/2026-08-27-platform-operations.md': {
    deck: 'Running CaseChain safely requires operational visibility, but that visibility must not become a back door into a client’s legal material.',
    intro: 'This plan creates a separate trust domain for platform operators, with strong identity, privacy boundaries, cost controls and a tested recovery gate.',
    flowCaption: 'Operating the service safely',
    flow: ['Protect operator access', 'Observe metadata and health', 'Control changes and prove recovery'],
    sections: [
      { heading: 'Operations is not tenant administration', paragraphs: [
        'An organisation admin manages their own members and policy. A platform operator keeps the service healthy across organisations. Those roles need different identities, routes and permissions, and the platform role does not automatically grant access to legal content.',
        'Operational views expose safe projections: job state, storage counts, usage, provider cost, configuration versions, alerts and audit history. Sensitive support access, when ever justified, must be explicit, time-bound and recorded rather than implied by a service-role shortcut.',
      ]},
      { heading: 'Controls for a service that can grow', paragraphs: [
        'Quotas and model configuration are versioned and enforced at the service boundary. Provider usage is recorded in real units and tied to the price effective when the work ran. Operators can pause risky processing or place an organisation in a safe mode without editing tenant data by hand.',
        'Jobs, health signals and alerts use stable identifiers and privacy-safe metadata. Backup and restore are treated as a working capability, not a checkbox: the platform must complete a restore drill before rollout moves beyond the controlled pilot.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'CaseChain gains the tools to diagnose failures, control cost and recover from serious incidents without weakening tenant isolation. Every consequential operational action leaves an immutable audit trail.',
        'The wider rollout therefore depends on evidence that the service can be operated and restored safely, not only that the application features work.',
      ]},
    ],
  },
  'docs/plans/operations/2026-08-27-project-portal-and-github-pages.md': {
    deck: 'Reviewers need a welcoming way to understand the project without entering the CaseChain application or reading engineering files in the repository.',
    intro: 'This plan publishes a static Project Portal from the canonical plan archive while keeping its deployment completely separate from the live product.',
    flowCaption: 'From repository plan to public article',
    flow: ['Read canonical plan metadata', 'Build the public reading edition', 'Publish through GitHub Pages'],
    sections: [
      { heading: 'A public window into the work', paragraphs: [
        'The portal is for friends, reviewers and collaborators who want to understand what CaseChain is building and why. It shows plan status, a recommended reading order and a dedicated page for every archived plan.',
        'Status describes planning maturity, not delivery. An approved plan may still be unimplemented, and the portal must never turn that distinction into a misleading progress claim.',
      ]},
      { heading: 'A small site with a clear boundary', paragraphs: [
        'A dependency-free Node.js script reads the plan archive and produces static HTML, CSS and JavaScript. GitHub Actions builds that artifact from the active source branch and deploys it to GitHub Pages. The process does not build the Next.js application or change the Vercel deployment.',
        'The canonical plan remains the decision record. The portal can add a human-edited reading edition and curated explanatory visuals, but it links back to the source rather than quietly replacing it.',
      ]},
      { heading: 'What this plan achieves', paragraphs: [
        'Readers get a fast, responsive and accessible site that explains the project in ordinary language while preserving access to technical detail. Maintainers get a repeatable build that fails when a new archived plan has not been added to the reading order.',
        'The portal becomes the public story of the project; the repository remains the place where exact decisions are maintained.',
      ]},
    ],
  },
};
