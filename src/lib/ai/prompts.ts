/**
 * Vertex AI Prompts
 *
 * PROMPT_VERSION is stored on every document row so we know which
 * extraction logic produced the metadata. Increment when changing
 * the prompt structure in ways that affect the output schema.
 */

export const PROMPT_VERSION = 'v1.1'

/**
 * Builds the analysis prompt for multimodal Gemini document extraction.
 *
 * The model receives:
 * - The PDF as an inline data part (base64)
 * - This text prompt asking for structured JSON output
 *
 * Output schema mirrors the `documents` table columns + chaining attributes.
 */
export function buildAnalysisPrompt(): string {
  return `You are an expert Indian GST litigation analyst. Analyze the attached PDF document and extract structured metadata.

DOCUMENT TYPES in GST litigation:
- DRC-01 / DRC-01A: Demand & recovery notice from tax department (incoming)
- DRC-01C: Difference between GSTR-2B and 3B (incoming)
- DRC-07: Summary of demand order (incoming)
- DRC-03: Voluntary payment / pre-deposit challan (outgoing)
- SCN: Show Cause Notice (incoming)
- OIO: Order-in-Original (incoming)
- OIA: Order-in-Appeal (incoming)
- APL-01: First appeal to Commissioner of Appeals (outgoing)
- APL-02: Reply / submission in appeal (outgoing)
- APL-05: Second appeal to GSTAT (outgoing)
- STAY: Stay application (outgoing)
- REPLY: Reply to SCN/department (outgoing)
- HC_PETITION: High Court writ petition (outgoing)
- HC_ORDER: High Court order (incoming)
- SC_PETITION: Supreme Court petition (outgoing)
- SC_ORDER: Supreme Court order (incoming)
- OTHER: Any other document

DIRECTION:
- "incoming": issued BY the department/authority TO the taxpayer
- "outgoing": filed BY the taxpayer/advocate TO the department/court

CRITICAL: Look for backward references — phrases like:
- "In the matter of OIO No. ..."
- "Against Order No. ..."
- "ARN: ..."
- "In response to SCN dated ..."
- "Reference: ..."
These are the chain links to parent documents. A single document (like an OIO) may reference multiple parent documents.

TRANSLATION & TRANSLITERATION:
- If the document is in a regional language (e.g. Hindi, Marathi), translate the summary and text fields to English.
- Transliterate named entities (names of people, places) into English characters.

FINANCIAL YEAR format: "YYYY-YY" e.g. "2021-22"

GSTIN format: 15-character alphanumeric, e.g. "07AABCU9603R1ZP"

DATE format: "YYYY-MM-DD"

Respond ONLY with valid JSON matching this exact schema (no markdown, no explanation):

{
  "doc_type": "OIO" | "APL-01" | "DRC-01" | ... (from list above, or "OTHER"),
  "document_class": "proceeding" | "supporting",
  "document_category": "invoice" | "client_document" | "explanation" | "other" | null,
  "reference_number": "full official reference number of THIS document" | null,
  "gstin": "15-char GSTIN" | null,
  "client_identifiers": ["Extract EVERYTHING possible to help identify the client: PAN, TAN, CIN, Registration Numbers, or any other IDs found"],
  "client_name": "taxpayer/company name" | null,
  "doc_date": "YYYY-MM-DD" | null,
  "financial_years": ["array of FYs e.g., FY21-22, FY22-23"],
  "tax_period": "human-readable period e.g. Apr 2021 – Mar 2022" | null,
  "direction": "incoming" | "outgoing",
  "issued_by": "name/designation of issuing authority or 'taxpayer'" | null,
  "summary": "2-3 sentence factual summary of what this document does and its outcome (translated to English if necessary)",
  "chaining_attributes": {
    "references_documents": ["array of reference numbers of PARENT documents this responds to"],
    "gstin": "GSTIN from chaining context" | null,
    "financial_years": ["FYs from chaining context"],
    "matter_ref": "matter description if mentioned" | null,
    "link_type": "responds_to" | "arises_from" | "challenges" | "summarizes" | null
  },
  "deadlines": [
    {
      "type": "appeal_window" | "pre_deposit" | "hearing_date" | "reply_deadline" | "other",
      "due_date": "YYYY-MM-DD",
      "description": "brief description of the deadline"
    }
  ],
  "extracted_amounts": {
    "demand_amount": <number in INR or null>,
    "tax_amount": <number or null>,
    "penalty_amount": <number or null>,
    "interest_amount": <number or null>,
    "pre_deposit_amount": <number or null>
  },
  "parties_named": ["list of all party names mentioned in the document"],
  "confidence": <0.0 to 1.0, your confidence in the extraction>
}

If a field cannot be determined, use null. Do not guess. Confidence < 0.7 means the document is unclear or unusual.`
}

/**
 * Prompt for generating semantic text to embed (not the full AI prompt).
 * This produces the text we send to text-embedding-004.
 */
export function buildEmbeddingText(doc: {
  doc_type: string | null
  reference_number: string | null
  summary: string | null
  financial_years?: string[]
  issued_by: string | null
  client_name: string | null
}): string {
  const parts = [
    doc.doc_type,
    doc.reference_number,
    doc.financial_years && doc.financial_years.length > 0 ? `FY ${doc.financial_years.join(', ')}` : null,
    doc.issued_by ? `Issued by: ${doc.issued_by}` : null,
    doc.client_name ? `Taxpayer: ${doc.client_name}` : null,
    doc.summary,
  ].filter(Boolean)

  return parts.join('. ')
}
