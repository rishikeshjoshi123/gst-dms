import 'server-only'

import { z } from 'zod'
import { createServiceClient } from '@/lib/supabase/server'

const evidence = z.object({
  kind: z.enum([
    'matter_code_exact',
    'external_proceeding_id_exact',
    'referenced_document_exact',
    'verified_client_identifier',
    'tax_period_overlap',
    'procedure_compatible',
  ]),
  source_page_number: z.number().int().positive().nullable(),
}).strict()

const trustedPlacementEvaluation = z.object({
  intakeId: z.string().uuid(),
  sourceRevision: z.string().regex(/^[a-z][a-z0-9_.:-]{0,127}$/),
  candidates: z.array(z.object({
    matter_id: z.string().uuid(),
    evidence: z.array(evidence).min(1).max(20),
  }).strict()).min(2).max(20),
}).strict().superRefine((value, context) => {
  if (new Set(value.candidates.map((candidate) => candidate.matter_id)).size !== value.candidates.length) {
    context.addIssue({ code: z.ZodIssueCode.custom, message: 'Matter candidates must be distinct.', path: ['candidates'] })
  }
})

export type TrustedPlacementEvaluation = z.input<typeof trustedPlacementEvaluation>

/**
 * Service-only handoff for a trusted, provider-independent placement result.
 * This boundary does not infer candidates and never accepts provider payloads;
 * the RPC re-derives every tenant, source, Matter, and Client fact.
 */
export async function produceAmbiguousIntakePlacementReview(input: TrustedPlacementEvaluation) {
  const parsed = trustedPlacementEvaluation.parse(input)
  const { data, error } = await createServiceClient().rpc('produce_ambiguous_intake_placement_review', {
    p_intake_id: parsed.intakeId,
    p_source_revision: parsed.sourceRevision,
    p_candidates: parsed.candidates,
  })
  if (error) throw new Error('Trusted Intake placement handoff failed')
  return data?.[0] ?? null
}
