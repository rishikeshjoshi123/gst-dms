import { realpathSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { sep } from 'node:path'
import { spawn,spawnSync } from 'node:child_process'
import { acceptanceProjectPath,nodeModuleLaunch,requireNode24 } from './runtime.mjs'

const node=requireNode24(),workdir=process.env.MEMBER_SUSPENSION_SUPABASE_WORKDIR
if(!workdir)throw new Error('The isolated member-suspension Supabase workdir is required.')
const resolved=realpathSync(workdir),temporary=realpathSync(tmpdir())
if(!resolved.startsWith(`${temporary}${sep}`))throw new Error('Refusing a member-suspension Supabase workdir outside the temporary directory.')
const cli=acceptanceProjectPath('node_modules/supabase/dist/supabase.js')
const status=spawnSync(node,[cli,'status','-o','env'],{cwd:resolved,encoding:'utf8'})
if(status.status!==0)throw new Error(status.stderr||'Isolated Supabase status failed.')
const local=Object.fromEntries(status.stdout.trim().split('\n').map(line=>{const index=line.indexOf('=');return[line.slice(0,index),line.slice(index+1).replace(/^"|"$/g,'')] }))
for(const key of ['API_URL','ANON_KEY','SERVICE_ROLE_KEY'])if(!local[key])throw new Error(`Isolated Supabase did not report ${key}.`)
if(!['127.0.0.1','localhost'].includes(new URL(local.API_URL).hostname))throw new Error('Refusing a non-loopback API URL.')
const env={...process.env,NEXT_PUBLIC_APP_URL:'http://127.0.0.1:3261',NEXT_PUBLIC_SUPABASE_URL:local.API_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY:local.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:local.SERVICE_ROLE_KEY,TRIGGER_SECRET_KEY:'',TRIGGER_API_URL:'http://127.0.0.1:9',RESEND_API_KEY:'',GOOGLE_APPLICATION_CREDENTIALS:'',GOOGLE_APPLICATION_CREDENTIALS_JSON:'',GOOGLE_CLOUD_PROJECT:'',DOCUMENT_AI_LOCATION:'',DOCUMENT_AI_OCR_PROCESSOR_ID:'',DOCUMENT_AI_OCR_PROCESSOR_VERSION:''}
const next=nodeModuleLaunch(acceptanceProjectPath('node_modules/next/dist/bin/next'),['dev','--hostname','127.0.0.1','--port','3261'])
const child=spawn(next.command,next.args,{cwd:acceptanceProjectPath('.'),env,stdio:'inherit'})
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal))
child.on('exit',(code,signal)=>{if(signal)process.kill(process.pid,signal);else process.exit(code??1)})
