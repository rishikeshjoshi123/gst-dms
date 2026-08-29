/**
 * Vertex AI client — Gemini multimodal document analysis and search embeddings.
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
import {
  PROMPT_VERSION,
  buildAnalysisPrompt,
  buildWikiPrompt,
} from './prompts'
import {
  aiDocumentPayloadSchema,
  aiWikiPayloadSchema,
  documentResponseSchema,
  wikiResponseSchema,
  type AIDocumentResult,
  type AIUsage,
  type AIWikiResult,
} from './schemas'

export type { AIDocumentResult, AIWikiResult } from './schemas'

export type DocumentAnalysisOutcome =
  | { kind: 'validated'; result: AIDocumentResult }
  | { kind: 'invalid_model_output' }
  | { kind: 'provider_failed' }

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

export const VERTEX_DOCUMENT_MODEL = 'gemini-2.5-flash'
export const VERTEX_EMBEDDING_MODEL = 'gemini-embedding-001'
export const VERTEX_EMBEDDING_DIMENSIONS = 768
export const VERTEX_EMBEDDING_VERSION = 'gemini-embedding-001-768-v1'

function usageFromResponse(usage: {
  promptTokenCount?: number
  candidatesTokenCount?: number
  totalTokenCount?: number
} | undefined): AIUsage | undefined {
  if (!usage) return undefined
  return {
    promptTokens: usage.promptTokenCount ?? 0,
    candidateTokens: usage.candidatesTokenCount ?? 0,
    totalTokens: usage.totalTokenCount ?? 0,
  }
}

function extractJsonObject(rawText: string): unknown {
  // Structured generation is a contract, not a best-effort text format.
  // Do not recover a JSON-looking substring from prose, markdown, or a
  // truncated provider response: that would silently accept an unbounded
  // response outside the requested schema.
  return JSON.parse(rawText)
}

function logVertexDiagnostic(code: 'document_response_invalid' | 'document_response_unreadable' | 'document_request_failed' | 'wiki_response_invalid' | 'wiki_request_failed') {
  // Provider exceptions, model output, and validation details can carry
  // tenant data. Keep this boundary deliberately fixed and content-free.
  console.warn(`[Vertex AI] ${code}`)
}

// ── Document analysis ───────────────────────────────────────────────────────

/**
 * Send a PDF buffer to Gemini Flash for structured metadata extraction.
 * Returns null on failure (graceful degradation).
 */
export async function analyzeDocumentWithOutcome(
  pdfBuffer: Buffer
): Promise<DocumentAnalysisOutcome> {
  try {
    const vertex = getVertexAI()
    const model = vertex.preview.getGenerativeModel({
      model: VERTEX_DOCUMENT_MODEL,
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: documentResponseSchema,
        temperature: 0,
        maxOutputTokens: 8192,
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
      logVertexDiagnostic('document_response_invalid')
      return { kind: 'invalid_model_output' }
    }

    const rawText = candidate.content.parts[0].text.trim()

    try {
      const validation = aiDocumentPayloadSchema.safeParse(extractJsonObject(rawText))
      if (!validation.success) {
        logVertexDiagnostic('document_response_invalid')
        return { kind: 'invalid_model_output' }
      }

      return {
        kind: 'validated',
        result: {
          ...validation.data,
          prompt_version: PROMPT_VERSION,
          usage: usageFromResponse(response.response.usageMetadata),
        },
      }
    } catch {
      logVertexDiagnostic('document_response_unreadable')
      return { kind: 'invalid_model_output' }
    }
  } catch {
    logVertexDiagnostic('document_request_failed')
    return { kind: 'provider_failed' }
  }
}

/**
 * Transitional compatibility wrapper. New durable processing callers use the
 * discriminated outcome so invalid model output cannot be confused with a
 * transient provider failure.
 */
export async function analyzeDocument(pdfBuffer: Buffer): Promise<AIDocumentResult | null> {
  const outcome = await analyzeDocumentWithOutcome(pdfBuffer)
  return outcome.kind === 'validated' ? outcome.result : null
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
        responseSchema: wikiResponseSchema,
        temperature: 0.1,
        maxOutputTokens: 6144,
      },
    })

    const response = await model.generateContent(buildWikiPrompt(matterContext))
    const candidate = response.response.candidates?.[0]
    if (!candidate?.content?.parts?.[0]?.text) {
      console.warn('[Vertex AI] Empty response from model for wiki')
      return null
    }

    const rawText = candidate.content.parts[0].text.trim()
    let parsed: unknown
    try {
      parsed = extractJsonObject(rawText)
    } catch {
      logVertexDiagnostic('wiki_response_invalid')
      return null
    }
    const validation = aiWikiPayloadSchema.safeParse(parsed)
    if (!validation.success) {
      logVertexDiagnostic('wiki_response_invalid')
      return null
    }

    return {
      ...validation.data,
      usage: usageFromResponse(response.response.usageMetadata),
    }
  } catch {
    logVertexDiagnostic('wiki_request_failed')
    return null
  }
}

// ── Embeddings ───────────────────────────────────────────────────────────────

/**
 * Generate a versioned 768-dimensional embedding for retrieval.
 * Returns null on failure.
 */
export type EmbeddingTaskType = 'RETRIEVAL_DOCUMENT' | 'RETRIEVAL_QUERY'

export type EmbeddingResult = {
  embedding: number[]
  inputTokens: number
  truncated: boolean
  model: string
  version: string
  taskType: EmbeddingTaskType
}

export async function generateEmbedding(
  text: string,
  taskType: EmbeddingTaskType = 'RETRIEVAL_DOCUMENT',
): Promise<EmbeddingResult | null> {
  try {
    const normalizedText = text.trim()
    if (!normalizedText) return null

    const credentialsJson = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
    if (!credentialsJson) throw new Error('GOOGLE_APPLICATION_CREDENTIALS_JSON not set')

    const credentials = JSON.parse(credentialsJson)
    const project = process.env.GOOGLE_CLOUD_PROJECT ?? credentials.project_id
    const location = process.env.GOOGLE_CLOUD_REGION ?? 'us-central1'

    const auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/cloud-platform'],
    })
    const client = await auth.getClient()
    const token = await client.getAccessToken()

    const endpoint = `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/${VERTEX_EMBEDDING_MODEL}:predict`

    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token.token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instances: [
          {
            content: normalizedText,
            task_type: taskType,
          },
        ],
        parameters: {
          outputDimensionality: VERTEX_EMBEDDING_DIMENSIONS,
          autoTruncate: false,
        },
      }),
    })

    if (!res.ok) return null

    const data = await res.json() as {
      predictions: Array<{
        embeddings: {
          values: number[]
          statistics?: {
            token_count?: number
            truncated?: boolean
          }
        }
      }>
    }

    const prediction = data.predictions[0]?.embeddings
    const embedding = prediction?.values ?? null
    const inputTokens = prediction?.statistics?.token_count
    const truncated = prediction?.statistics?.truncated
    if (!embedding || embedding.length !== VERTEX_EMBEDDING_DIMENSIONS
      || typeof inputTokens !== 'number' || !Number.isInteger(inputTokens) || inputTokens < 0
      || typeof truncated !== 'boolean') return null

    return {
      embedding,
      inputTokens,
      truncated,
      model: VERTEX_EMBEDDING_MODEL,
      version: VERTEX_EMBEDDING_VERSION,
      taskType,
    }
  } catch {
    return null
  }
}
