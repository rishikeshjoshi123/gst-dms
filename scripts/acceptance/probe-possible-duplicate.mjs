import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { requireNode24 } from './runtime.mjs'
import { reviewDetail,reviewQueueItem } from '../../src/lib/review/model.ts'

const node=requireNode24()
const workdir=process.env.REVIEW_ACCEPTANCE_WORKDIR
if(!workdir||!readFileSync(join(workdir,'supabase/config.toml'),'utf8').includes('project_id = "dms-review-153"'))
  throw new Error('Requires owned disposable Review stack.')
const status=spawnSync(node,['node_modules/supabase/dist/supabase.js','status','--workdir',workdir,'-o','json'],{encoding:'utf8'})
if(status.status!==0)throw new Error('Disposable status unavailable.')
const local=JSON.parse(status.stdout)
if(local.API_URL!=='http://127.0.0.1:55321'||new URL(local.DB_URL).port!=='55322')throw new Error('Unexpected destination.')
const client=createClient(local.API_URL,local.ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const login=await client.auth.signInWithPassword({email:'reference-viewer@example.test',password:'PlacementFixture167!'})
if(login.error)throw new Error(`Viewer login failed: ${login.error.message}`)
const queue=await client.rpc('read_review_queue',{p_status:'needs_review',p_type:'possible_duplicate',p_priority:'all',p_search:'',p_page:1,p_page_size:25})
console.log('Viewer queue RPC:',queue.error?.message??'ok',queue.data?.[0]?.total_count??null)
if(queue.data?.[0]?.items?.[0])console.log('Viewer queue shape:',reviewQueueItem.safeParse(queue.data[0].items[0]).success)
const itemId=queue.data?.[0]?.items?.[0]?.id
if(itemId){const detail=await client.rpc('read_review_detail',{p_review_item_id:itemId});console.log('Viewer detail RPC:',detail.error?.message??'ok',detail.data?.type??null)
  const parsed=reviewDetail.safeParse(detail.data)
  console.log('Viewer detail shape:',parsed.success,parsed.success?'':parsed.error.issues.map(issue=>`${issue.path.join('.')}:${issue.code}`).join(','))}
