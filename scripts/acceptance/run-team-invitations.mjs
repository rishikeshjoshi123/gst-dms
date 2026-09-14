import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node=requireNode24(),root=process.cwd(),workdir=mkdtempSync(join(tmpdir(),'dms-team-invitations-acceptance.'))
const cli=join(root,'node_modules/supabase/dist/supabase.js'),container='supabase_db_dms-team-invitations-160'
let created=false
function run(command,args,options={}){const result=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:24*1024*1024,...options});if(result.error||result.status!==0)throw new Error(`${command} failed: ${result.error?.message??`${result.stderr}\n${result.stdout}`}`);return result.stdout}
try{
  if(run('docker',['ps','-a','--format','{{.Names}}']).split('\n').some(name=>name.endsWith('_dms-team-invitations-160')))throw new Error('The isolated invitation acceptance project is already owned by another run.')
  cpSync(join(root,'supabase/migrations'),join(workdir,'supabase/migrations'),{recursive:true})
  writeFileSync(join(workdir,'supabase/config.toml'),`project_id = "dms-team-invitations-160"
[api]
port = 56021
schemas = ["public", "graphql_public"]
[db]
port = 56022
shadow_port = 56020
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 56023
[local_smtp]
enabled = true
port = 56024
[auth]
site_url = "http://127.0.0.1:3260"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 56027
`)
  created=true
  console.log('Replaying migrations in isolated dms-team-invitations-160.')
  run(node,[cli,'start','--workdir',workdir])
  const lint=run(node,[cli,'db','lint','--local','--workdir',workdir,'--level','error'])
  if(JSON.parse(lint).results?.length){console.error(lint);throw new Error('Disposable database lint found errors.')}
  console.log('Database lint passed.')
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/governed_team_invitations.sql'),'utf8')}))
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/governed_team_invitation_concurrency_setup.sql'),'utf8')}))
  console.log(run('bash',['supabase/tests/governed_team_invitation_concurrency.sh'],{env:{...process.env,SUPABASE_DB_CONTAINER:container}}))
  if(process.argv.includes('--types')){
    const env={...process.env,PATH:`${join(root,'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}`}
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env})
    const once=readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env})
    if(readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')!==once)throw new Error('Database type generation was not deterministic.')
    console.log('Generated/refined database types twice with exact parity.')
  }
  if(process.argv.includes('--browser')){
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'scripts/acceptance/seed.sql'),'utf8')}))
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:`INSERT INTO public.organisation_invites(org_id,normalized_email,role,state,selector_hash,invited_by_user_id,idempotency_key,expires_at,revoked_at) VALUES
('b0010000-0000-0000-0000-000000000001','pending-colleague-with-a-very-long-address@acceptance.test','associate','pending',repeat('d',64),'a0010000-0000-0000-0000-000000000001',gen_random_uuid(),now()+interval '7 days',NULL),
('b0010000-0000-0000-0000-000000000001','revoked@acceptance.test','viewer','revoked',NULL,'a0010000-0000-0000-0000-000000000001',gen_random_uuid(),now()+interval '7 days',now());`}))
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.team-invitations.config.ts'],{env:{...process.env,TEAM_INVITATIONS_SUPABASE_WORKDIR:workdir}}))
  }
}finally{
  if(created){const stopped=spawnSync(node,[cli,'stop','--no-backup','--workdir',workdir],{encoding:'utf8'});if(stopped.status!==0)console.error('Disposable invitation stack cleanup failed.');else console.log('Removed the disposable invitation stack and data.')}
  rmSync(workdir,{recursive:true,force:true})
}
