import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { amendManualDeadlineSchema, createManualDeadlineSchema, deadlineOutcomeSchema } from './manual'

const base={matterId:'d0010000-0000-0000-0000-000000000001',title:'File reply',obligation:'File the signed written reply',legalType:'reply_due',dueDate:'2028-02-29',manualBasis:'Direction recorded in order',idempotencyKey:'f1590000-0000-0000-0000-000000000001'}
test('manual creation accepts exact leap-day dates and rejects impossible or non-date values',()=>{
  assert.equal(createManualDeadlineSchema.safeParse(base).success,true)
  for(const dueDate of ['2027-02-29','2026-04-31','2026-13-01','2026-00-01','01-01-2026','2026-1-1']) assert.equal(createManualDeadlineSchema.safeParse({...base,dueDate}).success,false,dueDate)
})
test('amendment and cancellation require append-only decision reasons',()=>{
  assert.equal(amendManualDeadlineSchema.safeParse({...base,deadlineId:'e1590000-0000-0000-0000-000000000001',expectedRevision:1,reason:'Registry corrected the direction'}).success,true)
  assert.equal(amendManualDeadlineSchema.safeParse({...base,deadlineId:'e1590000-0000-0000-0000-000000000001',expectedRevision:1,reason:' '}).success,false)
  assert.equal(deadlineOutcomeSchema.safeParse({matterId:base.matterId,deadlineId:'e1590000-0000-0000-0000-000000000001',expectedRevision:2,outcome:'cancelled',reason:'',idempotencyKey:base.idempotencyKey}).success,false)
  assert.equal(deadlineOutcomeSchema.safeParse({matterId:base.matterId,deadlineId:'e1590000-0000-0000-0000-000000000001',expectedRevision:2,outcome:'satisfied',reason:'',idempotencyKey:base.idempotencyKey}).success,true)
})
test('authority source retains fixed search paths, explicit role mutation policy, actor-bound replay, CAS, direct-write closure and no reminder claim',()=>{
  const migration=readFileSync(new URL('../../../supabase/migrations/00159_governed_manual_legal_deadlines.sql',import.meta.url),'utf8')
  const ui=readFileSync(new URL('../../components/matters/MatterDeadlineAgenda.tsx',import.meta.url),'utf8')
  for(const token of ['SECURITY DEFINER SET search_path=pg_catalog,public','current_active_tenant_membership','organisation_member_capabilities','stale_revision','idempotency_conflict','deadlines_canonical_writes','deadline_versions_append_only','deadline_outcomes_append_only']) assert.match(migration,new RegExp(token))
  assert.match(migration,/coalesce\(owner,false\) OR member\.role IN \('admin','associate'\)/)
  assert.doesNotMatch(migration,/document\.intake\.create/)
  assert.match(migration,/m\.record_state='active'[\s\S]*m\.deleted_at IS NULL[\s\S]*m\.work_state='active'[\s\S]*c\.record_state='active'[\s\S]*c\.deleted_at IS NULL/)
  assert.match(migration,/d\.due_date<today THEN 'missed'[\s\S]*d\.due_date=today THEN 'due_today'[\s\S]*d\.due_date<=today\+7 THEN 'due_soon'/)
  assert.doesNotMatch(ui,/Alerts active|reminders? (enabled|active|scheduled)/i)
  assert.match(ui,/defaultValue=\{mode === 'amend' \? item\?\.manual_basis : ''\}/)
  assert.match(ui,/entry\.actor_label/)
  assert.doesNotMatch(ui,/actor_user_id|value\.slice/)
  assert.match(ui,/Legal deadline/); assert.match(ui,/Manual origin/); assert.match(ui,/Verified/)
})
