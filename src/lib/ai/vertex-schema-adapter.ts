import { Type, type Schema } from '@google/genai'
import { z } from 'zod'

type ZodNode = z.ZodTypeAny & { _def: Record<string, unknown> }

function checksFor(node: ZodNode) {
  return (node._def.checks ?? []) as Array<{ kind: string; value?: number; regex?: RegExp }>
}

function adapt(node: ZodNode): Schema {
  const typeName = node._def.typeName as string
  if (typeName === z.ZodFirstPartyTypeKind.ZodEffects) return adapt(node._def.schema as ZodNode)
  if (typeName === z.ZodFirstPartyTypeKind.ZodNullable) return { ...adapt(node._def.innerType as ZodNode), nullable: true }
  if (typeName === z.ZodFirstPartyTypeKind.ZodString) {
    const schema: Schema = { type: Type.STRING }
    for (const check of checksFor(node)) {
      if (check.kind === 'min' && check.value !== undefined) schema.minLength = String(check.value)
      if (check.kind === 'max' && check.value !== undefined) schema.maxLength = String(check.value)
      if (check.kind === 'regex' && check.regex) schema.pattern = check.regex.source
    }
    return schema
  }
  if (typeName === z.ZodFirstPartyTypeKind.ZodNumber) {
    const checks = checksFor(node)
    const schema: Schema = { type: checks.some((check) => check.kind === 'int') ? Type.INTEGER : Type.NUMBER }
    for (const check of checks) {
      if (check.kind === 'min' && check.value !== undefined) schema.minimum = check.value
      if (check.kind === 'max' && check.value !== undefined) schema.maximum = check.value
    }
    return schema
  }
  if (typeName === z.ZodFirstPartyTypeKind.ZodBoolean) return { type: Type.BOOLEAN }
  if (typeName === z.ZodFirstPartyTypeKind.ZodEnum) {
    return { type: Type.STRING, format: 'enum', enum: [...(node._def.values as string[])] }
  }
  if (typeName === z.ZodFirstPartyTypeKind.ZodArray) {
    const schema: Schema = { type: Type.ARRAY, items: adapt(node._def.type as ZodNode) }
    const minLength = node._def.minLength as { value: number } | null
    const maxLength = node._def.maxLength as { value: number } | null
    if (minLength) schema.minItems = String(minLength.value)
    if (maxLength) schema.maxItems = String(maxLength.value)
    return schema
  }
  if (typeName === z.ZodFirstPartyTypeKind.ZodObject) {
    const shape = (node._def.shape as () => Record<string, ZodNode>)()
    return {
      type: Type.OBJECT,
      properties: Object.fromEntries(Object.entries(shape).map(([key, value]) => [key, adapt(value)])),
      propertyOrdering: Object.keys(shape),
      required: Object.keys(shape),
    }
  }
  throw new Error(`Unsupported canonical Zod node for Vertex structured output: ${typeName}`)
}

/** Provider guidance only; the same Zod contract strictly parses the response. */
export function vertexSchemaFromZod(schema: z.ZodTypeAny): Schema {
  return adapt(schema as ZodNode)
}
