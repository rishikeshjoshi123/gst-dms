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
  document_class: 'proceeding' | 'supporting'
  document_category: string | null
  reference_number: string | null
  gstin: string | null
  client_identifiers: string[] | null
  client_name: string | null
  doc_date: string | null
  financial_years: string[]
  tax_period: string | null
  direction: 'incoming' | 'outgoing' | null
  issued_by: string | null
  summary: string
  chaining_attributes: {
    references_documents: string[]
    gstin: string | null
    financial_years: string[]
    matter_ref: string | null
    link_type: 'responds_to' | 'arises_from' | 'challenges' | 'summarizes' | null
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
  usage?: {
    promptTokens: number
    candidateTokens: number
    totalTokens: number
  }
}

export const VERTEX_DOCUMENT_MODEL = 'gemini-2.5-flash'
export const VERTEX_EMBEDDING_MODEL = 'text-embedding-004'

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
      model: VERTEX_DOCUMENT_MODEL,
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

    let rawText = ''
    try {
      rawText = candidate.content.parts[0].text.trim()
    } catch (e) {
      console.error('[Vertex AI] Failed to extract text from parts:', e)
      return null
    }

    let jsonText = rawText
    const firstBrace = rawText.indexOf('{')
    const lastBrace = rawText.lastIndexOf('}')
    if (firstBrace !== -1 && lastBrace !== -1) {
      jsonText = rawText.slice(firstBrace, lastBrace + 1)
    }

    try {
      const parsed = JSON.parse(jsonText) as Omit<AIDocumentResult, 'prompt_version'>
      const usage = response.response.usageMetadata
      return {
        ...parsed,
        prompt_version: PROMPT_VERSION,
        usage: usage ? {
          promptTokens: usage.promptTokenCount ?? 0,
          candidateTokens: usage.candidatesTokenCount ?? 0,
          totalTokens: usage.totalTokenCount ?? 0
        } : undefined
      }
    } catch (err) {
      console.error('[Vertex AI] analyzeDocument failed parsing JSON:', err)
      console.error('[Vertex AI] Raw text was:', rawText)
      return null
    }
  } catch (err) {
    console.error('[Vertex AI] analyzeDocument failed:', err)
    return null
  }
}

export interface AIWikiResult {
  executive_summary: string
  key_arguments: string
  outstanding_tasks: string
  usage?: {
    promptTokens: number
    candidateTokens: number
    totalTokens: number
  }
}

export async function generateWikiSummary(
  matterContext: string
): Promise<AIWikiResult | null> {
  try {
    const vertex = getVertexAI()
    const model = vertex.preview.getGenerativeModel({
      model: VERTEX_DOCUMENT_MODEL,
      generationConfig: {
        responseMimeType: 'application/json',
        temperature: 0.2,
      },
    })

    const prompt = `
    You are an expert Indian GST (Goods and Services Tax) litigation assistant.
    Below is a compilation of all documents and their metadata/summaries for a specific legal matter.
    
    Your task is to synthesize this information and generate three comprehensive markdown-formatted sections for a Case Wiki:
    1. executive_summary: A high-level overview of the entire matter, what the core dispute is about, and the current status.
    2. key_arguments: A breakdown of the primary arguments from both the Tax Department and the Client.
    3. outstanding_tasks: A list of next steps, open questions, or pending compliance actions.
    
    Output JSON exactly in this format:
    {
      "executive_summary": "# Executive Summary\\n...",
      "key_arguments": "# Key Arguments\\n...",
      "outstanding_tasks": "# Outstanding Tasks\\n..."
    }
    
    Document Context:
    ${matterContext}
    `

    const response = await model.generateContent(prompt)
    const candidate = response.response.candidates?.[0]
    if (!candidate?.content?.parts?.[0]?.text) {
      console.warn('[Vertex AI] Empty response from model for wiki')
      return null
    }

    const rawText = candidate.content.parts[0].text.trim()
    let jsonText = rawText
    const firstBrace = rawText.indexOf('{')
    const lastBrace = rawText.lastIndexOf('}')
    if (firstBrace !== -1 && lastBrace !== -1) {
      jsonText = rawText.slice(firstBrace, lastBrace + 1)
    }

    const parsed = JSON.parse(jsonText) as AIWikiResult
    const usage = response.response.usageMetadata
    if (usage) {
      parsed.usage = {
        promptTokens: usage.promptTokenCount ?? 0,
        candidateTokens: usage.candidatesTokenCount ?? 0,
        totalTokens: usage.totalTokenCount ?? 0
      }
    }
    return parsed
  } catch (err) {
    console.error('[Vertex AI] generateWikiSummary failed:', err)
    return null
  }
}

// ── Embeddings ───────────────────────────────────────────────────────────────

/**
 * Generate a 768-dimensional embedding for semantic search using text-embedding-004.
 * Returns null on failure.
 */
export async function generateEmbedding(text: string): Promise<{ embedding: number[], charCount: number } | null> {
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

    const endpoint = `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/${VERTEX_EMBEDDING_MODEL}:predict`

    const slicedText = text.slice(0, 8000) // model max input

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instances: [
          {
            content: slicedText, 
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

    const embedding = data.predictions[0]?.embeddings?.values ?? null
    if (!embedding) return null
    return { embedding, charCount: slicedText.length }
  } catch (err) {
    console.error('[Vertex AI] generateEmbedding failed:', err)
    return null
  }
}
