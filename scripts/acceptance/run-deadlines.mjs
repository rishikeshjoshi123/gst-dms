import { appendFileSync, cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node=requireNode24(), root=process.cwd(), workdir=mkdtempSync(join(tmpdir(),'dms-deadlines-acceptance.'))
const cli=join(root,'node_modules/supabase/dist/supabase.js'), container='supabase_db_dms-deadlines-159'
let created=false
function run(command,args,options={}) { const result=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:20*1024*1024,...options}); if(result.error||result.status!==0) throw new Error(`${command} failed: ${result.error?.message??`${result.stderr}\n${result.stdout}`}`); return result.stdout }
try {
  if(run('docker',['ps','-a','--format','{{.Names}}']).split('\n').some(name=>name.endsWith('_dms-deadlines-159'))) throw new Error('The isolated deadline acceptance project is already owned by another run.')
  cpSync(join(root,'supabase/migrations'),join(workdir,'supabase/migrations'),{recursive:true})
  appendFileSync(join(workdir,'supabase/migrations/00158_intake_assignment_matter_lifecycle_gate.sql'),`
INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
('00000000-0000-0000-0000-000000000000','a1580000-0000-0000-0000-000000000001','authenticated','authenticated','legacy-deadline@acceptance.test','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES('b1580000-0000-0000-0000-000000000001','Legacy deadline fixture','a1580000-0000-0000-0000-000000000001');
INSERT INTO public.clients(id,org_id,name) VALUES('c1580000-0000-0000-0000-000000000001','b1580000-0000-0000-0000-000000000001','Legacy client');
INSERT INTO public.matters(id,org_id,client_id,title,status) VALUES('d1580000-0000-0000-0000-000000000001','b1580000-0000-0000-0000-000000000001','c1580000-0000-0000-0000-000000000001','Legacy matter','active');
INSERT INTO public.deadlines(id,matter_id,type,due_date,description) VALUES
('e1580000-0000-0000-0000-000000000001','d1580000-0000-0000-0000-000000000001','other',current_date,NULL),
('e1580000-0000-0000-0000-000000000002','d1580000-0000-0000-0000-000000000001','other',current_date,' '),
('e1580000-0000-0000-0000-000000000003','d1580000-0000-0000-0000-000000000001','other',current_date,E'Court\\norder\\t'),
('e1580000-0000-0000-0000-000000000004','d1580000-0000-0000-0000-000000000001','other',current_date,repeat('x',1205));
`)
  writeFileSync(join(workdir,'supabase/config.toml'),`project_id = "dms-deadlines-159"
[api]
port = 55921
schemas = ["public", "graphql_public"]
[db]
port = 55922
shadow_port = 55920
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 55923
[local_smtp]
enabled = true
port = 55924
[auth]
site_url = "http://127.0.0.1:3109"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 55927
`)
  created=true; console.log('Replaying migrations in isolated dms-deadlines-159.')
  run(node,[cli,'start','--workdir',workdir])
  const lint=run(node,[cli,'db','lint','--local','--workdir',workdir,'--level','error'])
  console.log(lint)
  if(JSON.parse(lint).results?.length) throw new Error('Disposable database lint found errors.')
  if(process.argv.includes('--types')) {
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env:{...process.env,PATH:`${join(root,'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}`}})
    const once=readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env:{...process.env,PATH:`${join(root,'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}`}})
    if(readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')!==once) throw new Error('Database type generation was not deterministic.')
    console.log('Generated/refined database types twice with exact parity.')
  }
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/manual_legal_deadline_legacy_backfill.sql'),'utf8')}))
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/manual_legal_deadlines.sql'),'utf8')}))
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/manual_legal_deadline_concurrency_setup.sql'),'utf8')}))
  console.log(run('sh',['supabase/tests/manual_legal_deadline_concurrency.sh'],{env:{...process.env,SUPABASE_DB_CONTAINER:container}}))
  if(process.argv.includes('--browser')) {
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'scripts/acceptance/seed.sql'),'utf8')}))
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.deadlines.config.ts'],{env:{...process.env,DEADLINE_ACCEPTANCE_WORKDIR:workdir}}))
  }
} finally {
  if(created) { const stopped=spawnSync(node,[cli,'stop','--no-backup','--workdir',workdir],{encoding:'utf8'}); if(stopped.status!==0) console.error('Disposable deadline stack cleanup failed.'); else console.log('Removed the disposable deadline stack and data.') }
  rmSync(workdir,{recursive:true,force:true})
}
