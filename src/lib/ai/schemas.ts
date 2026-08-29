import { SchemaType, type ResponseSchema } from '@google-cloud/vertexai'
import { z } from 'zod'

export const DOCUMENT_TYPES = [
  'DRC-01',
  'DRC-01A',
  'DRC-01C',
  'DRC-03',
  'DRC-07',
  'SCN',
  'OIO',
  'OIA',
  'APL-01',
  'APL-02',
  'APL-05',
  'STAY',
  'REPLY',
  'HC_PETITION',
  'HC_ORDER',
  'SC_PETITION',
  'SC_ORDER',
  'OTHER',
] as const

const nullableText = z.string().trim().min(1).nullable()
const nullableDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable()
const financialYear = z.string().regex(/^\d{4}-\d{2}$/)
const nullableGstin = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/)
  .nullable()

const evidenceSchema = z.object({
  field: z.enum([
    'document_type',
    'reference_number',
    'gstin',
    'client_name',
    'document_date',
    'financial_year',
    'direction',
    'issued_by',
    'deadline',
    'amount',
    'document_link',
    'legal_reference',
  ]),
  value: z.string().trim().min(1),
  page_number: z.number().int().positive().nullable(),
  quote: nullableText,
  confidence: z.number().min(0).max(1),
}).strict()

const legalReferenceSchema = z.object({
  act: nullableText,
  provision_type: z.enum(['section', 'rule', 'notification', 'circular', 'instruction', 'other']),
  provision_number: z.string().trim().min(1),
  context: nullableText,
  page_number: z.number().int().positive().nullable(),
  confidence: z.number().min(0).max(1),
}).strict()

const deadlineSchema = z.object({
  type: z.enum([
    'appeal_window',
    'pre_deposit',
    'hearing_date',
    'reply_deadline',
    'stay_application',
    'other',
  ]),
  due_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  description: z.string().trim().min(1),
  source_page: z.number().int().positive().nullable(),
  source_quote: nullableText,
  confidence: z.number().min(0).max(1),
}).strict()

export const aiDocumentPayloadSchema = z.object({
  doc_type: z.enum(DOCUMENT_TYPES).nullable(),
  document_title: nullableText,
  document_class: z.enum(['proceeding', 'supporting']),
  document_category: z.enum(['invoice', 'client_document', 'explanation', 'evidence', 'other']).nullable(),
  reference_number: nullableText,
  gstin: nullableGstin,
  client_identifiers: z.array(z.string().trim().min(1)).max(50).nullable(),
  client_name: nullableText,
  doc_date: nullableDate,
  financial_years: z.array(financialYear).max(30),
  tax_period: nullableText,
  direction: z.enum(['incoming', 'outgoing']).nullable(),
  issued_by: nullableText,
  summary: z.string().trim().min(1).max(6000),
  chaining_attributes: z.object({
    references_documents: z.array(z.string().trim().min(1)).max(100),
    gstin: nullableGstin,
    financial_years: z.array(financialYear).max(30),
    matter_ref: nullableText,
    link_type: z.enum(['responds_to', 'arises_from', 'challenges', 'summarizes']).nullable(),
  }).strict(),
  deadlines: z.array(deadlineSchema).max(50),
  extracted_amounts: z.object({
    tax: z.number().finite().nonnegative().nullable(),
    interest: z.number().finite().nonnegative().nullable(),
    penalty: z.number().finite().nonnegative().nullable(),
    fee: z.number().finite().nonnegative().nullable(),
    pre_deposit: z.number().finite().nonnegative().nullable(),
    total_demand: z.number().finite().nonnegative().nullable(),
    amount_in_dispute: z.number().finite().nonnegative().nullable(),
    amount_relief: z.number().finite().nonnegative().nullable(),
  }).strict(),
  parties_named: z.array(z.string().trim().min(1)).max(100),
  legal_references: z.array(legalReferenceSchema).max(100),
  evidence: z.array(evidenceSchema).max(200),
  confidence: z.number().min(0).max(1),
}).strict()

export type AIDocumentPayload = z.infer<typeof aiDocumentPayloadSchema>

export type AIUsage = {
  promptTokens: number
  candidateTokens: number
  totalTokens: number
}

export type AIDocumentResult = AIDocumentPayload & {
  prompt_version: string
  usage?: AIUsage
}

export const aiWikiPayloadSchema = z.object({
  executive_summary: z.string().trim().min(1).max(12000),
  key_arguments: z.string().trim().min(1).max(16000),
  outstanding_tasks: z.string().trim().min(1).max(12000),
}).strict()

export type AIWikiPayload = z.infer<typeof aiWikiPayloadSchema>
export type AIWikiResult = AIWikiPayload & { usage?: AIUsage }

const nullableStringResponse = (description: string) => ({
  type: SchemaType.STRING,
  nullable: true,
  description,
})

export const documentResponseSchema: ResponseSchema = {
  type: SchemaType.OBJECT,
  required: [
    'doc_type',
    'document_title',
    'document_class',
    'document_category',
    'reference_number',
    'gstin',
    'client_identifiers',
    'client_name',
    'doc_date',
    'financial_years',
    'tax_period',
    'direction',
    'issued_by',
    'summary',
    'chaining_attributes',
    'deadlines',
    'extracted_amounts',
    'parties_named',
    'legal_references',
    'evidence',
    'confidence',
  ],
  properties: {
    doc_type: { type: SchemaType.STRING, enum: [...DOCUMENT_TYPES], nullable: true },
    document_title: nullableStringResponse('Formal title or heading of the document.'),
    document_class: { type: SchemaType.STRING, enum: ['proceeding', 'supporting'] },
    document_category: {
      type: SchemaType.STRING,
      enum: ['invoice', 'client_document', 'explanation', 'evidence', 'other'],
      nullable: true,
    },
    reference_number: nullableStringResponse('Full official reference number of this document.'),
    gstin: nullableStringResponse('Validated 15-character GSTIN.'),
    client_identifiers: {
      type: SchemaType.ARRAY,
      nullable: true,
      items: { type: SchemaType.STRING },
    },
    client_name: nullableStringResponse('Taxpayer or client legal name.'),
    doc_date: nullableStringResponse('Document date in YYYY-MM-DD format.'),
    financial_years: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
    tax_period: nullableStringResponse('Human-readable tax period.'),
    direction: { type: SchemaType.STRING, enum: ['incoming', 'outgoing'], nullable: true },
    issued_by: nullableStringResponse('Issuing authority, court, taxpayer, or advocate.'),
    summary: {
      type: SchemaType.STRING,
      description: 'Neutral factual summary that distinguishes allegations, submissions, and findings.',
    },
    chaining_attributes: {
      type: SchemaType.OBJECT,
      required: ['references_documents', 'gstin', 'financial_years', 'matter_ref', 'link_type'],
      properties: {
        references_documents: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
        gstin: nullableStringResponse('GSTIN appearing in relationship context.'),
        financial_years: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
        matter_ref: nullableStringResponse('Matter or proceeding description used as a backward reference.'),
        link_type: {
          type: SchemaType.STRING,
          enum: ['responds_to', 'arises_from', 'challenges', 'summarizes'],
          nullable: true,
        },
      },
    },
    deadlines: {
      type: SchemaType.ARRAY,
      items: {
        type: SchemaType.OBJECT,
        required: ['type', 'due_date', 'description', 'source_page', 'source_quote', 'confidence'],
        properties: {
          type: {
            type: SchemaType.STRING,
            enum: ['appeal_window', 'pre_deposit', 'hearing_date', 'reply_deadline', 'stay_application', 'other'],
          },
          due_date: { type: SchemaType.STRING },
          description: { type: SchemaType.STRING },
          source_page: { type: SchemaType.INTEGER, nullable: true },
          source_quote: nullableStringResponse('Short supporting quotation.'),
          confidence: { type: SchemaType.NUMBER },
        },
      },
    },
    extracted_amounts: {
      type: SchemaType.OBJECT,
      required: ['tax', 'interest', 'penalty', 'fee', 'pre_deposit', 'total_demand', 'amount_in_dispute', 'amount_relief'],
      properties: Object.fromEntries(
        ['tax', 'interest', 'penalty', 'fee', 'pre_deposit', 'total_demand', 'amount_in_dispute', 'amount_relief']
          .map((key) => [key, { type: SchemaType.NUMBER, nullable: true }]),
      ),
    },
    parties_named: { type: SchemaType.ARRAY, items: { type: SchemaType.STRING } },
    legal_references: {
      type: SchemaType.ARRAY,
      items: {
        type: SchemaType.OBJECT,
        required: ['act', 'provision_type', 'provision_number', 'context', 'page_number', 'confidence'],
        properties: {
          act: nullableStringResponse('Name of the Act or rules.'),
          provision_type: {
            type: SchemaType.STRING,
            enum: ['section', 'rule', 'notification', 'circular', 'instruction', 'other'],
          },
          provision_number: { type: SchemaType.STRING },
          context: nullableStringResponse('How the provision is used in the document.'),
          page_number: { type: SchemaType.INTEGER, nullable: true },
          confidence: { type: SchemaType.NUMBER },
        },
      },
    },
    evidence: {
      type: SchemaType.ARRAY,
      items: {
        type: SchemaType.OBJECT,
        required: ['field', 'value', 'page_number', 'quote', 'confidence'],
        properties: {
          field: {
            type: SchemaType.STRING,
            enum: [
              'document_type',
              'reference_number',
              'gstin',
              'client_name',
              'document_date',
              'financial_year',
              'direction',
              'issued_by',
              'deadline',
              'amount',
              'document_link',
              'legal_reference',
            ],
          },
          value: { type: SchemaType.STRING },
          page_number: { type: SchemaType.INTEGER, nullable: true },
          quote: nullableStringResponse('Short text supporting the extracted value.'),
          confidence: { type: SchemaType.NUMBER },
        },
      },
    },
    confidence: { type: SchemaType.NUMBER },
  },
}

export const wikiResponseSchema: ResponseSchema = {
  type: SchemaType.OBJECT,
  required: ['executive_summary', 'key_arguments', 'outstanding_tasks'],
  properties: {
    executive_summary: { type: SchemaType.STRING },
    key_arguments: { type: SchemaType.STRING },
    outstanding_tasks: { type: SchemaType.STRING },
  },
}
