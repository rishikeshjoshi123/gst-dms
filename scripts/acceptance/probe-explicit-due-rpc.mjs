import { spawnSync } from 'node:child_process'
import { createClient } from '@supabase/supabase-js'
import { requireNode24 } from './runtime.mjs'
const node=requireNode24(),workdir=process.env.REVIEW_ACCEPTANCE_WORKDIR
if(!workdir) throw new Error('Requires disposable Review profile.')
const status=spawnSync(node,['node_modules/supabase/dist/supabase.js','status','--workdir',workdir,'-o','json'],{encoding:'utf8'})
if(status.status!==0)throw new Error('Isolated Review status unavailable.')
const local=JSON.parse(status.stdout)
if(local.API_URL!=='http://127.0.0.1:55321'||new URL(local.DB_URL).port!=='55322')
  throw new Error('Unexpected RPC destination.')
const client=createClient(local.API_URL,local.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const signed=await client.auth.signInWithPassword({email:'review-1@example.test',password:'ReviewFixture153!'})
if(signed.error)throw new Error(`Fixture sign-in failed: ${signed.error.code}`)
const queue=await client.rpc('read_review_queue',{p_type:'deadline_verification'})
if(queue.error)throw new Error(`Fixture queue failed: ${queue.error.code}`)
const item=queue.data?.[0]?.items?.[0]
if(!item?.id)throw new Error('No exact due-date item was projected.')
const decided=await client.rpc('resolve_explicit_due_date_review',{
  p_review_item_id:item.id,p_expected_revision:item.revision,
  p_action:'correct',p_corrected_due_date:'2026-10-17',
  p_reason:'Written corrected date verified against cited source',
  p_idempotency_key:crypto.randomUUID(),
})
console.log(JSON.stringify({code:decided.data?.[0]?.code??null,error:decided.error
  ?{code:decided.error.code,message:decided.error.message,details:decided.error.details}:null}))
if(decided.error||decided.data?.[0]?.code!=='ok')process.exitCode=1
