import { realpathSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { sep } from 'node:path'
import { spawn,spawnSync } from 'node:child_process'
import { acceptanceProjectPath,nodeModuleLaunch,requireNode24 } from './runtime.mjs'

const node=requireNode24(),workdir=process.env.TEAM_INVITATIONS_SUPABASE_WORKDIR
if(!workdir)throw new Error('The isolated invitation Supabase workdir is required.')
const resolved=realpathSync(workdir),temporary=realpathSync(tmpdir())
if(!resolved.startsWith(`${temporary}${sep}`))throw new Error('Refusing an invitation Supabase workdir outside the temporary directory.')
const cli=acceptanceProjectPath('node_modules/supabase/dist/supabase.js')
const status=spawnSync(node,[cli,'status','-o','env'],{cwd:resolved,encoding:'utf8'})
if(status.status!==0)throw new Error(status.stderr||'Isolated Supabase status failed.')
const local=Object.fromEntries(status.stdout.trim().split('\n').map(line=>{const index=line.indexOf('=');return[line.slice(0,index),line.slice(index+1).replace(/^"|"$/g,'')]}))
for(const key of ['API_URL','DB_URL','ANON_KEY','SERVICE_ROLE_KEY'])if(!local[key])throw new Error(`Isolated Supabase did not report ${key}.`)
for(const key of ['API_URL','DB_URL'])if(!['127.0.0.1','localhost'].includes(new URL(local[key]).hostname))throw new Error(`Refusing non-loopback ${key}.`)
const appUrl='http://127.0.0.1:3260'
const capturePort=3261,capturedMessages=[]
const captureServer=createServer((request,response)=>{
 const remote=request.socket.remoteAddress
 if(!['127.0.0.1','::1','::ffff:127.0.0.1'].includes(remote??'')){response.writeHead(403).end();return}
 if(request.method==='GET'&&request.url==='/messages'){response.writeHead(200,{'content-type':'application/json'}).end(JSON.stringify(capturedMessages));return}
 if(request.method!=='POST'||request.url!=='/capture'){response.writeHead(404).end();return}
 let body='',oversized=false
 request.setEncoding('utf8')
 request.on('data',chunk=>{if(body.length+chunk.length>262_144){oversized=true;return}body+=chunk})
 request.on('end',()=>{
  if(oversized){response.writeHead(413).end();return}
  try{
   const message=JSON.parse(body)
   if(!message||typeof message.to!=='string'||typeof message.subject!=='string'||typeof message.html!=='string')throw new Error('Invalid captured message.')
   capturedMessages.push(message)
   response.writeHead(202,{'content-type':'application/json'}).end('{"captured":true}')
  }catch{response.writeHead(400).end()}
 })
})
await new Promise((resolve,reject)=>{captureServer.once('error',reject);captureServer.listen(capturePort,'127.0.0.1',resolve)})
const env={...process.env,NEXT_PUBLIC_APP_URL:appUrl,NEXT_PUBLIC_SUPABASE_URL:local.API_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY:local.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:local.SERVICE_ROLE_KEY,TRIGGER_SECRET_KEY:'',TRIGGER_API_URL:'http://127.0.0.1:9',RESEND_API_KEY:'',CASECHAIN_EMAIL_CAPTURE_URL:`http://127.0.0.1:${capturePort}/capture`,GOOGLE_APPLICATION_CREDENTIALS:'',GOOGLE_APPLICATION_CREDENTIALS_JSON:'',GOOGLE_CLOUD_PROJECT:'',DOCUMENT_AI_LOCATION:'',DOCUMENT_AI_OCR_PROCESSOR_ID:'',DOCUMENT_AI_OCR_PROCESSOR_VERSION:''}
const next=nodeModuleLaunch(acceptanceProjectPath('node_modules/next/dist/bin/next'),['dev','--hostname','127.0.0.1','--port','3260'])
const child=spawn(next.command,next.args,{cwd:acceptanceProjectPath('.'),env,stdio:'inherit'})
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{captureServer.close();child.kill(signal)})
child.on('exit',(code,signal)=>captureServer.close(()=>{if(signal)process.kill(process.pid,signal);else process.exit(code??1)}))
