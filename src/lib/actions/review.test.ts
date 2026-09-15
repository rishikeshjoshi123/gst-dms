import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

test('successful legal-date Review invalidates dashboard attention but unsuccessful RPC does not',()=>{
  const source=readFileSync(new URL('./review.ts',import.meta.url),'utf8')
  const resolver=source.split('export async function resolveExtractionConflict')[0]
  assert.match(resolver,/if\(error \|\| !data\?\.\[0\]\) return[\s\S]*if\(row\.code==='ok'\)\{[\s\S]*revalidatePath\('\/review'\)[\s\S]*revalidatePath\('\/dashboard'\)/)
  assert.equal(resolver.slice(0,resolver.indexOf("if(row.code==='ok')")).includes("revalidatePath('/dashboard')"),false)
})
