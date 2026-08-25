import assert from 'node:assert/strict'
import test from 'node:test'
import { aiDocumentPayloadSchema, aiWikiPayloadSchema } from './schemas'

const validDocumentPayload = {
  doc_type: 'SCN',
  document_title: 'Show Cause Notice',
  document_class: 'proceeding',
  document_category: null,
  reference_number: 'SCN/2024/001',
  gstin: '27ABCDE1234F1Z5',
  client_identifiers: ['ABCDE1234F'],
  client_name: 'Example Private Limited',
  doc_date: '2024-04-01',
  financial_years: ['2023-24'],
  tax_period: 'April 2023 to March 2024',
  direction: 'incoming',
  issued_by: 'Deputy Commissioner',
  summary: 'The department alleges short payment of tax and asks the taxpayer to respond.',
  chaining_attributes: {
    references_documents: [],
    gstin: '27ABCDE1234F1Z5',
    financial_years: ['2023-24'],
    matter_ref: null,
    link_type: null,
  },
  deadlines: [{
    type: 'reply_deadline',
    due_date: '2024-04-30',
    description: 'Reply requested by the stated date.',
    source_page: 2,
    source_quote: 'submit a reply on or before 30 April 2024',
    confidence: 0.98,
  }],
  extracted_amounts: {
    tax: 1_000_000,
    interest: null,
    penalty: null,
    fee: null,
    pre_deposit: null,
    total_demand: 1_000_000,
    amount_in_dispute: 1_000_000,
    amount_relief: null,
  },
  parties_named: ['Example Private Limited'],
  legal_references: [{
    act: 'Central Goods and Services Tax Act, 2017',
    provision_type: 'section',
    provision_number: '73',
    context: 'Invoked as the basis for the proposed demand.',
    page_number: 1,
    confidence: 0.96,
  }],
  evidence: [{
    field: 'reference_number',
    value: 'SCN/2024/001',
    page_number: 1,
    quote: 'SCN/2024/001',
    confidence: 0.99,
  }],
  confidence: 0.94,
}

test('accepts a source-grounded document extraction payload', () => {
  const result = aiDocumentPayloadSchema.safeParse(validDocumentPayload)
  assert.equal(result.success, true)
})

test('rejects unsupported fields and invalid financial years', () => {
  const result = aiDocumentPayloadSchema.safeParse({
    ...validDocumentPayload,
    financial_years: ['2023 to 2024'],
    invented_legal_opinion: 'The appeal will succeed.',
  })

  assert.equal(result.success, false)
})

test('normalizes an invalid GSTIN to null without losing the extraction', () => {
  const result = aiDocumentPayloadSchema.parse({
    ...validDocumentPayload,
    gstin: 'unclear-scan',
  })

  assert.equal(result.gstin, null)
})

test('validates the current Case Brief storage contract', () => {
  const result = aiWikiPayloadSchema.safeParse({
    executive_summary: 'The matter concerns an alleged short payment. [Document: SCN/2024/001]',
    key_arguments: 'The department alleges a mismatch; the taxpayer position is unavailable.',
    outstanding_tasks: 'Obtain the taxpayer reply before updating the position.',
  })

  assert.equal(result.success, true)
})
