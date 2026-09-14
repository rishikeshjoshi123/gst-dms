import { cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawn, spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'
const node=requireNode24(), repository=process.cwd(), workdir=process.env.DEADLINE_ACCEPTANCE_WORKDIR
if(!workdir||!readFileSync(join(workdir,'supabase/config.toml'),'utf8').includes('project_id = "dms-deadlines-159"')) throw new Error('Supply the exclusively owned deadline acceptance workdir.')
const status=spawnSync(node,[join(repository,'node_modules/supabase/dist/supabase.js'),'status','--workdir',workdir,'-o','json'],{encoding:'utf8'})
if(status.status!==0) throw new Error('Isolated deadline database is unavailable.')
const local=JSON.parse(status.stdout); if(local.API_URL!=='http://127.0.0.1:55921'||new URL(local.DB_URL).port!=='55922') throw new Error('Unexpected deadline acceptance destination.')
const workspace=mkdtempSync(join(tmpdir(),'dms-deadlines-app-'))
for(const entry of ['src','public','package.json','package-lock.json','tsconfig.json','next.config.ts','postcss.config.mjs']) cpSync(join(repository,entry),join(workspace,entry),{recursive:true})
symlinkSync(resolve(repository,'node_modules'),join(workspace,'node_modules'),'dir')
const fontMock=join(workspace,'font-mock.cjs'); writeFileSync(fontMock,`module.exports = new Proxy({}, { get(_target, url) { const mono = String(url).includes('Geist+Mono'); const family = mono ? 'Geist Mono' : 'Geist'; const file = ${JSON.stringify(join(repository,'node_modules/next/dist/next-devtools/server/font/'))} + (mono ? 'geist-mono-latin.woff2' : 'geist-latin.woff2'); return "/* latin */\\n@font-face { font-family: '" + family + "'; font-style: normal; font-weight: 100 900; src: url(" + file + ") format('woff2'); }"; } });`)
const env={...process.env,NEXT_PUBLIC_APP_URL:'http://127.0.0.1:3109',NEXT_PUBLIC_SUPABASE_URL:local.API_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY:local.ANON_KEY,SUPABASE_SERVICE_ROLE_KEY:local.SERVICE_ROLE_KEY,TRIGGER_SECRET_KEY:'',TRIGGER_API_URL:'http://127.0.0.1:9',RESEND_API_KEY:'re_acceptance_disabled',RESEND_FROM_EMAIL:'acceptance@invalid.example',GOOGLE_APPLICATION_CREDENTIALS:'',GOOGLE_APPLICATION_CREDENTIALS_JSON:'',GOOGLE_CLOUD_PROJECT:'',DOCUMENT_AI_LOCATION:'',DOCUMENT_AI_OCR_PROCESSOR_ID:'',DOCUMENT_AI_OCR_PROCESSOR_VERSION:'',NEXT_FONT_GOOGLE_MOCKED_RESPONSES:fontMock}
const compiled=spawnSync(node,[join(repository,'node_modules/next/dist/bin/next'),'build','--webpack'],{cwd:workspace,env,stdio:'inherit'}); if(compiled.status!==0){rmSync(workspace,{recursive:true,force:true});process.exit(compiled.status??1)}
const child=spawn(node,[join(repository,'node_modules/next/dist/bin/next'),'start','--hostname','127.0.0.1','--port','3109'],{cwd:workspace,env,stdio:'inherit'}); for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>child.kill(signal)); child.on('exit',code=>{rmSync(workspace,{recursive:true,force:true});process.exit(code??1)})
