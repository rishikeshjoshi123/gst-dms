/**
 * Document Assignment Engine
 *
 * Implements the "Reference-First Reverse Lookup" algorithm:
 *
 * Phase A1: Scan documents table for references this doc mentions
 * Phase A2: Scan document_links for pending links waiting for THIS doc's reference
 * Phase B:  Fall back to client-identifier matching (GSTIN → PAN → name)
 * Phase C:  Propose client + matter creation when deterministic IDs (GSTIN/PAN) + FY are available
 *
 * Retained for canonical document-assignment consumers.
 */

import type { SupabaseClient } from '@supabase/supabase-js'
import { isDocumentActive, isMatterActive } from '@/lib/utils/resource-checks'
import type { AIDocumentResult } from '@/lib/ai/vertex'

// ── FY Normalization ──────────────────────────────────────────────────────────

/**
 * Canonicalizes all known FY string variants to "YYYY-YY" format.
 *
 * Examples:
 *   "FY22-23"    → "2022-23"
 *   "FY 2022-23" → "2022-23"
 *   "2022-2023"  → "2022-23"
 *   "22-23"      → "2022-23"
 *   "2022-23"    → "2022-23" (unchanged)
 *   "Unknown FY" → "Unknown FY" (sentinel preserved)
 */
export function normalizeFY(raw: string | null | undefined): string {
  if (!raw || raw.trim() === '' || raw.trim() === 'Unknown FY') return 'Unknown FY'

  let s = raw.trim()

  // Strip "FY" or "FY " prefix (case-insensitive)
  s = s.replace(/^FY\s*/i, '')

  // "2022-2023" → "2022-23"
  const longMatch = s.match(/^(\d{4})-(\d{4})$/)
  if (longMatch) return `${longMatch[1]}-${longMatch[2].slice(2)}`

  // "22-23" → "2022-23"
  const shortMatch = s.match(/^(\d{2})-(\d{2})$/)
  if (shortMatch) return `20${shortMatch[1]}-${shortMatch[2]}`

  // Already "YYYY-YY"
  if (/^\d{4}-\d{2}$/.test(s)) return s

  // Couldn't parse — return original so caller can decide
  return raw.trim()
}

// ── GSTIN Normalization ───────────────────────────────────────────────────────

/**
 * Normalizes a GSTIN string:
 *  - Uppercase, strip non-alphanumeric chars
 *  - Fix common OCR error: 'O' → '0' in the 2-digit state code prefix
 * Returns null if the result is not 15 characters (invalid).
 */
export function normalizeGSTIN(raw: string | null | undefined): string | null {
  if (!raw) return null
  let s = raw.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
  if (s.length !== 15) return null
  // Fix OCR-common 'O'→'0' in state code (first 2 chars should be digits)
  const stateCode = s.substring(0, 2).replace(/O/g, '0')
  return stateCode + s.substring(2)
}

export function normalizePAN(raw: string | null | undefined): string | null {
  if (!raw) return null
  const pan = raw.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
  return /^[A-Z]{5}[0-9]{4}[A-Z]$/.test(pan) ? pan : null
}

// ── Types ─────────────────────────────────────────────────────────────────────

export interface ResolvedClient {
  id: string
  name: string
  gstin: string | null
  pan: string | null
  confidence: number
  method: 'gstin' | 'pan' | 'name'
}

export interface MatterAssignment {
  matterId: string
  clientId: string
  /** 0–1 confidence of the match */
  confidence: number
  /** How this assignment was determined */
  method: 'reference_match' | 'pending_link_match' | 'client_fy_match' | 'auto_created'
  /**
   * null = couldn't verify (client_identifiers missing) — assign but mark review_status = 'unreviewed'
   * true = verified — assign confidently
   * false = mismatch — do NOT auto-assign
   */
  crossVerified: boolean | null
}

export interface AssignmentSuggestion {
  matterId?: string
  clientId?: string
  reason: string
}

export type AssignmentResult =
  | { type: 'auto_assign'; assignments: MatterAssignment[] }
  | { type: 'ready_to_assign'; reason: string; suggestions: AssignmentSuggestion[] }

// ── Client Resolution (shared helper) ────────────────────────────────────────

/**
 * Resolves a client from AI-extracted identifiers.
 * Used by both the auto pipeline (jobs.ts) and the manual UI (inbox.ts).
 *
 * Resolution priority (deterministic first):
 *  1. GSTIN exact match
 *  2. PAN or GSTIN found inside client_identifiers array
 *  3. Name ILIKE — only accepted when exactly ONE result (ambiguous = skip)
 */
export async function resolveClientFromIdentifiers(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: SupabaseClient<any>,
  orgId: string,
  aiResult: Pick<AIDocumentResult, 'gstin' | 'client_identifiers' | 'client_name'>
): Promise<ResolvedClient | null> {
  // 1. GSTIN exact match
  const normalizedGSTIN = normalizeGSTIN(aiResult.gstin)
  if (normalizedGSTIN) {
    const { data } = await supabase
      .from('clients')
      .select('id, name, gstin, pan')
      .eq('org_id', orgId)
      .eq('gstin', normalizedGSTIN)
      .is('deleted_at', null)
      .maybeSingle()
    if (data) return { ...data, confidence: 1.0, method: 'gstin' as const }
  }

  // 2. PAN / GSTIN found inside client_identifiers
  if (aiResult.client_identifiers && aiResult.client_identifiers.length > 0) {
    const { data: allClients } = await supabase
      .from('clients')
      .select('id, name, gstin, pan')
      .eq('org_id', orgId)
      .is('deleted_at', null)

    if (allClients) {
      for (const client of allClients) {
        for (const idStr of aiResult.client_identifiers) {
          if (client.pan && normalizePAN(idStr) === client.pan) {
            return { ...client, confidence: 0.9, method: 'pan' as const }
          }
          if (client.gstin && normalizeGSTIN(idStr) === client.gstin) {
            return { ...client, confidence: 0.95, method: 'gstin' as const }
          }
        }
      }
    }
  }

  // 3. Name ILIKE — single unambiguous result only
  if (aiResult.client_name) {
    const { data: nameMatches } = await supabase
      .from('clients')
      .select('id, name, gstin, pan')
      .eq('org_id', orgId)
      .ilike('name', `%${aiResult.client_name}%`)
      .is('deleted_at', null)

    if (nameMatches && nameMatches.length === 1) {
      return { ...nameMatches[0], confidence: 0.6, method: 'name' as const }
    }
    // 0 results = no match. >1 results = ambiguous, skip.
  }

  return null
}

// ── Cross-Verification ────────────────────────────────────────────────────────

/**
 * Checks if a matter's client matches the document's extracted identifiers.
 *
 * Returns:
 *  true  = verified match (safe to auto-assign)
 *  false = clear mismatch (block auto-assign, flag cross-matter issue)
 *  null  = cannot determine (client_identifiers not extracted — assign with unreviewed flag)
 */
function crossVerifyClient(
  client: { gstin: string | null; pan: string | null },
  aiResult: Pick<AIDocumentResult, 'gstin' | 'client_identifiers'>
): boolean | null {
  const normalizedGSTIN = normalizeGSTIN(aiResult.gstin)
  const hasVerifiableIds =
    !!normalizedGSTIN ||
    (aiResult.client_identifiers && aiResult.client_identifiers.length > 0)

  if (!hasVerifiableIds) return null // Can't verify — allow with unreviewed flag

  if (normalizedGSTIN && client.gstin) {
    return normalizeGSTIN(client.gstin) === normalizedGSTIN
  }

  if (aiResult.client_identifiers && client.pan) {
    return aiResult.client_identifiers.some(id => normalizePAN(id) === client.pan)
  }

  // Has verifiable IDs but client has no GSTIN/PAN stored — can't confirm or deny
  return null
}

// ── Main Assignment Engine ────────────────────────────────────────────────────

/**
 * Determines which matter(s) a document should be assigned to.
 *
 * Returns either:
 *  - auto_assign: list of MatterAssignment objects (1 per FY for multi-FY docs)
 *  - ready_to_assign: reason + suggestions for the manual UI
 */
export async function resolveDocumentAssignment(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  supabase: SupabaseClient<any>,
  orgId: string,
  aiResult: AIDocumentResult
): Promise<AssignmentResult> {
  const suggestions: AssignmentSuggestion[] = []

  const fys = [...new Set(
    (aiResult.financial_years ?? [])
      .map(normalizeFY)
      .filter(fy => fy !== 'Unknown FY' && /^\d{4}-\d{2}$/.test(fy))
  )]

  if (fys.length > 1) {
    return {
      type: 'ready_to_assign',
      reason: `Document spans multiple financial years (${fys.join(', ')}). Please assign manually.`,
      suggestions: [],
    }
  }

  // ── Phase A: Reference-Based Matter Discovery ──────────────────────────────

  const refs: string[] = [
    ...(aiResult.chaining_attributes?.references_documents ?? []),
    // Legacy support: single-reference field from older prompt versions
    ...((aiResult.chaining_attributes as any)?.references_document
      ? [(aiResult.chaining_attributes as any).references_document]
      : []),
  ].filter(Boolean)

  // Map: matterId → candidate info
  const matterCandidates = new Map<
    string,
    { matterId: string; clientId: string; confidence: number; method: 'reference_match' | 'pending_link_match' }
  >()

  // Phase A1: Scan documents table for reference matches (org-wide)
  for (const ref of refs) {
    if (!ref) continue

    // a) Exact reference number match
    const { data: exactDocs } = await supabase
      .from('documents')
      .select('id, matter_id, matters!inner(id, client_id, deleted_at, clients!inner(deleted_at))')
      .eq('org_id', orgId)
      .eq('reference_number', ref)
      .is('deleted_at', null)

    if (exactDocs && exactDocs.length > 0) {
      const activeDocs = exactDocs.filter(d => isDocumentActive(d as any))
      for (const doc of activeDocs) {
        const matter = doc.matters as any
        if (!matterCandidates.has(matter.id)) {
          matterCandidates.set(matter.id, {
            matterId: matter.id,
            clientId: matter.client_id,
            confidence: 1.0,
            method: 'reference_match',
          })
        }
      }
      continue // Exact match found — skip fuzzy for this ref
    }

    // b) Org-wide fuzzy match (RPC added in migration 00020)
    const { data: fuzzyDocs, error: fuzzyErr } = await supabase.rpc(
      'org_wide_fuzzy_match_reference',
      { p_org_id: orgId, p_reference_number: ref }
    )

    if (!fuzzyErr && fuzzyDocs && (fuzzyDocs as any[]).length > 0) {
      for (const match of (fuzzyDocs as any[])) {
        if (!matterCandidates.has(match.matter_id)) {
          const { data: matterRow } = await supabase
            .from('matters')
            .select('id, client_id, deleted_at, clients!inner(deleted_at)')
            .eq('id', match.matter_id)
            .maybeSingle()
          if (matterRow && isMatterActive(matterRow as any)) {
            matterCandidates.set(matterRow.id, {
              matterId: matterRow.id,
              clientId: matterRow.client_id,
              confidence: Math.min((match.sim_score as number) ?? 0.5, 0.75),
              method: 'reference_match',
            })
          }
        }
      }
    }
  }

  // Phase A2: Scan document_links for pending links waiting for THIS doc's reference number
  // Handles the reverse-order case: child uploaded first (creates pending link), parent uploaded later
  if (aiResult.reference_number) {
    const { data: pendingLinks } = await supabase
      .from('document_links')
      .select(
        'id, from_doc_id, documents!document_links_from_doc_id_fkey(id, matter_id, org_id, deleted_at, matters!inner(id, client_id, deleted_at, clients!inner(deleted_at)))'
      )
      .eq('status', 'pending')
      .eq('pending_ref_number', aiResult.reference_number)

    if (pendingLinks && pendingLinks.length > 0) {
      const validLinks = pendingLinks.filter(link => {
        const fromDoc = link.documents as any
        return fromDoc && isDocumentActive(fromDoc as any)
      })
      for (const link of validLinks) {
        const fromDoc = link.documents as any
        // Ensure pending link belongs to this org
        if (!fromDoc || fromDoc.org_id !== orgId) continue

        const mId = fromDoc.matter_id
        const clientId = fromDoc.matters?.client_id ?? ''

        if (!matterCandidates.has(mId)) {
          matterCandidates.set(mId, {
            matterId: mId,
            clientId,
            confidence: 0.9, // High — a doc in this matter was explicitly waiting for us
            method: 'pending_link_match',
          })
        } else {
          // Converging evidence — boost confidence
          const existing = matterCandidates.get(mId)!
          existing.confidence = Math.min(1.0, existing.confidence + 0.1)
        }
      }
    }
  }

  // ── Process Phase A results ────────────────────────────────────────────────

  if (matterCandidates.size > 0) {
    const confirmedAssignments: MatterAssignment[] = []
    const blockedSuggestions: AssignmentSuggestion[] = []

    for (const candidate of matterCandidates.values()) {
      const { data: clientRow } = await supabase
        .from('clients')
        .select('id, gstin, pan, name')
        .eq('id', candidate.clientId)
        .maybeSingle()

      if (!clientRow) continue

      const verifiedFlag = crossVerifyClient(clientRow, aiResult)

      if (verifiedFlag === false || candidate.confidence < 0.9) {
        // Never auto-file from a fuzzy reference or a confirmed client
        // mismatch. A null verification means the document did not contain a
        // usable GSTIN/PAN; an exact reference remains valid evidence and is
        // filed as unreviewed for a human to inspect.
        blockedSuggestions.push({
          matterId: candidate.matterId,
          clientId: candidate.clientId,
          reason: verifiedFlag === false
            ? `Reference matched but GSTIN/PAN mismatch with client "${clientRow.name}" — possible misfiling. Please verify.`
            : `Reference matched for client "${clientRow.name}", but the client identity or match confidence could not be verified. Please review.`,
        })
        continue
      }

      confirmedAssignments.push({
        matterId: candidate.matterId,
        clientId: candidate.clientId,
        confidence: candidate.confidence,
        method: candidate.method,
        crossVerified: verifiedFlag, // true or null (null = couldn't verify but no mismatch)
      })
    }

    if (confirmedAssignments.length === 1) {
      return { type: 'auto_assign', assignments: confirmedAssignments }
    }

    if (confirmedAssignments.length > 1) {
      return {
        type: 'ready_to_assign',
        reason: 'Multiple matters are plausible matches. Please choose the destination manually.',
        suggestions: confirmedAssignments.map(assignment => ({
          matterId: assignment.matterId,
          clientId: assignment.clientId,
          reason: `Candidate from ${assignment.method}.`,
        })),
      }
    }

    // All Phase A candidates were blocked by mismatch
    return {
      type: 'ready_to_assign',
      reason:
        blockedSuggestions[0]?.reason ??
        'Referenced document(s) found but client identifiers do not match. Possible misfiling — please verify before assigning.',
      suggestions: blockedSuggestions,
    }
  }

  // ── Phase B: Client-Identifier Lookup ─────────────────────────────────────

  const resolvedClient = await resolveClientFromIdentifiers(supabase, orgId, aiResult)

  if (resolvedClient) {
    if (fys.length === 0) {
      return {
        type: 'ready_to_assign',
        reason: `Client matched (${resolvedClient.name}) but financial year could not be determined. Please select a matter manually.`,
        suggestions: [{ clientId: resolvedClient.id, reason: `Matched client: ${resolvedClient.name}` }],
      }
    }

    if (resolvedClient.method === 'name') {
      return {
        type: 'ready_to_assign',
        reason: `Client name matched (${resolvedClient.name}), but name-only matching is not sufficient for auto-assignment.`,
        suggestions: [{ clientId: resolvedClient.id, reason: `Possible client: ${resolvedClient.name}` }],
      }
    }

    const matchedAssignments: MatterAssignment[] = []

    for (const fy of fys) {
      const { data: matter } = await supabase
        .from('matters')
        .select('id, client_id')
        .eq('org_id', orgId)
        .eq('client_id', resolvedClient.id)
        .eq('financial_year', fy)
        .is('deleted_at', null)
        .maybeSingle()

      if (matter) {
        matchedAssignments.push({
          matterId: matter.id,
          clientId: resolvedClient.id,
          confidence: resolvedClient.confidence,
          method: 'client_fy_match',
          crossVerified: true,
        })
      } else {
        suggestions.push({
          clientId: resolvedClient.id,
          reason: `Client matched (${resolvedClient.name}) but no matter found for FY ${fy}. Please create a matter first.`,
        })
      }
    }

    if (matchedAssignments.length > 0) {
      return { type: 'auto_assign', assignments: matchedAssignments }
    }

    return {
      type: 'ready_to_assign',
      reason:
        suggestions[0]?.reason ??
        `No matter found for client ${resolvedClient.name} in the extracted financial year(s).`,
      suggestions,
    }
  }

  // ── Phase C: Propose Client + Matter Creation ─────────────────────────────
  // AI output must never create business records in the background. The Inbox
  // presents its explicit Auto-Create action when this deterministic evidence
  // is available, where the user can confirm the resulting client/matter.

  const normalizedGSTIN = normalizeGSTIN(aiResult.gstin)
  const extractedPAN = aiResult.client_identifiers
    ?.map(normalizePAN)
    .find((pan): pan is string => pan !== null) ?? null
  const hasDeterministicId = !!normalizedGSTIN || !!extractedPAN

  if (hasDeterministicId && fys.length > 0 && aiResult.client_name) {
    return {
      type: 'ready_to_assign',
      reason: `No existing client matched. Review and confirm creation for ${aiResult.client_name} (${fys.join(', ')}).`,
      suggestions: [],
    }
  }

  // All phases exhausted
  return {
    type: 'ready_to_assign',
    reason: 'Could not automatically determine client or matter. Please assign manually.',
    suggestions: [],
  }
}
