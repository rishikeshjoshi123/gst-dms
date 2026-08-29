export const editableFieldTypes = {
  'document.client_name': 'text',
  'document.gstin': 'code',
  'document.reference_number': 'text',
  'document.type': 'code',
  'document.date': 'date',
  'document.financial_year': 'code',
  'financial.tax': 'decimal',
  'financial.interest': 'decimal',
  'financial.penalty': 'decimal',
  'financial.total_demand': 'decimal',
} as const

export type EditableFieldPath = keyof typeof editableFieldTypes

export function replacementValue(fieldPath: EditableFieldPath, value: string): string | null {
  const normalized = value.trim()
  if (!normalized) return null
  if (editableFieldTypes[fieldPath] === 'date') return /^\d{4}-\d{2}-\d{2}$/.test(normalized) ? normalized : null
  if (editableFieldTypes[fieldPath] === 'decimal') return /^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$/.test(normalized) ? normalized : null
  return normalized.length <= 500 ? normalized : null
}
