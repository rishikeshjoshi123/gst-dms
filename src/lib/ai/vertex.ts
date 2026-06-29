/**
 * Vertex AI client — Gemini multimodal document analysis + text-embedding-004
 *
 * Uses service account credentials stored in GOOGLE_APPLICATION_CREDENTIALS_JSON.
 * The JSON is stored as a single-line string in the env var.
 *
 * APIs required in GCP project (gst-dms):
 *   - Vertex AI API (aiplatform.googleapis.com)
 *   - Cloud Storage API (storage.googleapis.com) — for PDF access
 */

import { VertexAI, type GenerateContentRequest } from '@google-cloud/vertexai'
import { GoogleAuth } from 'google-auth-library'
import { PROMPT_VERSION, buildAnalysisPrompt } from './prompts'

// ── Lazy-initialized clients ────────────────────────────────────────────────

let _vertexAI: VertexAI | null = null

function getVertexAI(): VertexAI {
  if (_vertexAI) return _vertexAI

  const credentialsJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
  if (!credentialsJson) {
    throw new Error('GOOGLE_APPLICATION_CREDENTIALS_JSON is not set')
  }

  const credentials = JSON.parse(credentialsJson)
  const project = process.env.GOOGLE_CLOUD_PROJECT ?? credentials.project_id
  const location = process.env.GOOGLE_CLOUD_REGION ?? 'us-central1'

  _vertexAI = new VertexAI({
    project,
    location,
    googleAuthOptions: {
      credentials,
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    },
  })

  return _vertexAI
}

// ── Document analysis ───────────────────────────────────────────────────────

export interface AIDocumentResult {
  doc_type: string | null
  reference_number: string | null
  gstin: string | null
  client_name: string | null
  doc_date: string | null
  financial_year: string | null
  tax_period: string | null
  direction: 'incoming' | 'outgoing' | null
  issued_by: string | null
  summary: string
  chaining_attributes: {
    references_document: string | null
    gstin: string | null
    financial_year: string | null
    matter_ref: string | null
  }
  deadlines: Array<{
    type: string
    due_date: string
    description: string
  }>
  extracted_amounts: Record<string, number>
  parties_named: string[]
  confidence: number
  prompt_version: string
}

/**
 * Send a PDF buffer to Gemini Flash for structured metadata extraction.
 * Returns null on failure (graceful degradation).
 */
export async function analyzeDocument(
  pdfBuffer: Buffer
): Promise<AIDocumentResult | null> {
  try {
    const vertex = getVertexAI()
    const model = vertex.preview.getGenerativeModel({
      model: 'gemini-2.0-flash-001',
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 0.1,   // low temperature for structured extraction
        maxOutputTokens: 4096,
      },
    })

    const base64Pdf = pdfBuffer.toString('base64')

    const request: GenerateContentRequest = {
      contents: [
        {
          role: 'user',
          parts: [
            {
              inlineData: {
                mimeType: 'application/pdf',
                data: base64Pdf,
              },
            },
            {
              text: buildAnalysisPrompt(),
            },
          ],
        },
      ],
    }

    const response = await model.generateContent(request)
    const candidate = response.response.candidates?.[0]
    if (!candidate?.content?.parts?.[0]?.text) {
      console.warn('[Vertex AI] Empty response from model')
      return null
    }

    const rawText = candidate.content.parts[0].text.trim()

    // Strip markdown code fences if present
    const jsonText = rawText
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```\s*$/, '')

    const parsed = JSON.parse(jsonText) as Omit<AIDocumentResult, 'prompt_version'>

    return {
      ...parsed,
      prompt_version: PROMPT_VERSION,
    }
  } catch (err) {
    console.error('[Vertex AI] analyzeDocument failed:', err)
    return null
  }
}

// ── Embeddings ───────────────────────────────────────────────────────────────

/**
 * Generate a 768-dimensional embedding for semantic search using text-embedding-004.
 * Returns null on failure.
 */
export async function generateEmbedding(text: string): Promise<number[] | null> {
  try {
    const credentialsJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
    if (!credentialsJson) throw new Error('GOOGLE_APPLICATION_CREDENTIALS_JSON not set')

    const credentials = JSON.parse(credentialsJson)
    const project = process.env.GOOGLE_CLOUD_PROJECT ?? credentials.project_id
    const location = process.env.GOOGLE_CLOUD_REGION ?? 'us-central1'

    // text-embedding-004 uses the REST API endpoint directly
    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    })
    const client = await auth.getClient()
    const token = await client.getAccessToken()

    const endpoint = `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/text-embedding-004:predict`

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instances: [
          {
            content: text.slice(0, 8000), // model max input
            task_type: 'RETRIEVAL_DOCUMENT',
          },
        ],
        parameters: {
          outputDimensionality: 768,
        },
      }),
    })

    if (!res.ok) {
      const err = await res.text()
      console.error('[Vertex AI] Embedding request failed:', err)
      return null
    }

    const data = await res.json() as {
      predictions: Array<{ embeddings: { values: number[] } }>
    }

    return data.predictions[0]?.embeddings?.values ?? null
  } catch (err) {
    console.error('[Vertex AI] generateEmbedding failed:', err)
    return null
  }
}
