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
  const firstBrace = rawText.indexOf('{')
  const lastBrace = rawText.lastIndexOf('}')
  const jsonText = firstBrace !== -1 && lastBrace > firstBrace
    ? rawText.slice(firstBrace, lastBrace + 1)
    : rawText
  return JSON.parse(jsonText)
}

// ── Document analysis ───────────────────────────────────────────────────────

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

    try {
      const validation = aiDocumentPayloadSchema.safeParse(extractJsonObject(rawText))
      if (!validation.success) {
        console.error(
          '[Vertex AI] Document response failed validation:',
          validation.error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.message })),
        )
        return null
      }

      return {
        ...validation.data,
        prompt_version: PROMPT_VERSION,
        usage: usageFromResponse(response.response.usageMetadata),
      }
    } catch (err) {
      console.error('[Vertex AI] analyzeDocument failed parsing JSON:', err)
      return null
    }
  } catch (err) {
    console.error('[Vertex AI] analyzeDocument failed:', err)
    return null
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
    const validation = aiWikiPayloadSchema.safeParse(extractJsonObject(rawText))
    if (!validation.success) {
      console.error(
        '[Vertex AI] Case Brief response failed validation:',
        validation.error.issues.map((issue) => ({ path: issue.path.join('.'), message: issue.message })),
      )
      return null
    }

    return {
      ...validation.data,
      usage: usageFromResponse(response.response.usageMetadata),
    }
  } catch (err) {
    console.error('[Vertex AI] generateWikiSummary failed:', err)
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

    if (!res.ok) {
      const err = await res.text()
      console.error('[Vertex AI] Embedding request failed:', err)
      return null
    }

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
    if (!embedding || embedding.length !== VERTEX_EMBEDDING_DIMENSIONS) {
      console.error('[Vertex AI] Embedding response had an unexpected dimension count')
      return null
    }

    return {
      embedding,
      inputTokens: prediction.statistics?.token_count ?? 0,
      truncated: prediction.statistics?.truncated ?? false,
      model: VERTEX_EMBEDDING_MODEL,
      version: VERTEX_EMBEDDING_VERSION,
      taskType,
    }
  } catch (err) {
    console.error('[Vertex AI] generateEmbedding failed:', err)
    return null
  }
}
