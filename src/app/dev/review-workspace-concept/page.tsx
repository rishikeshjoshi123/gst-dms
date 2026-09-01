import type { Metadata } from 'next'

import { ReviewWorkspaceConcept } from './ReviewWorkspaceConcept'

export const metadata: Metadata = {
  title: 'Review Workspace Concept',
  description: 'Fixture-only visual concept for the CaseChain Review queue and evidence-led decision workspace.',
}

export default function ReviewWorkspaceConceptPage() {
  return <ReviewWorkspaceConcept />
}
