import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node=requireNode24(),root=process.cwd(),workdir=mkdtempSync(join(tmpdir(),'dms-member-suspension-acceptance.'))
const cli=join(root,'node_modules/supabase/dist/supabase.js'),container='supabase_db_dms-member-suspension-161'
let created=false
function run(command,args,options={}){const result=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:24*1024*1024,...options});if(result.error||result.status!==0)throw new Error(`${command} failed: ${result.error?.message??`${result.stderr}\n${result.stdout}`}`);return result.stdout}
try{
  if(run('docker',['ps','-a','--format','{{.Names}}']).split('\n').some(name=>name.endsWith('_dms-member-suspension-161')))throw new Error('The isolated member-suspension acceptance project is already owned by another run.')
  cpSync(join(root,'supabase/migrations'),join(workdir,'supabase/migrations'),{recursive:true})
  writeFileSync(join(workdir,'supabase/config.toml'),`project_id = "dms-member-suspension-161"
[api]
port = 56121
schemas = ["public", "graphql_public"]
[db]
port = 56122
shadow_port = 56120
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 56123
[inbucket]
enabled = false
[analytics]
enabled = false
port = 56127
[auth]
site_url = "http://127.0.0.1:3261"
[auth.email]
enable_confirmations = false
`)
  created=true
  console.log('Replaying migrations through 00161 in isolated dms-member-suspension-161.')
  run(node,[cli,'start','--workdir',workdir])
  const lint=run(node,[cli,'db','lint','--local','--workdir',workdir,'--level','error'])
  if(JSON.parse(lint).results?.length){console.error(lint);throw new Error('Disposable database lint found errors.')}
  console.log('Database lint passed.')
  run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'scripts/acceptance/seed.sql'),'utf8')})
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/governed_standard_member_suspension.sql'),'utf8')}))
  run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'supabase/tests/governed_standard_member_suspension_concurrency_setup.sql'),'utf8')})
  console.log(run('bash',['supabase/tests/governed_standard_member_suspension_concurrency.sh'],{env:{...process.env,SUPABASE_DB_CONTAINER:container}}))
  if(process.argv.includes('--types')){
    const env={...process.env,PATH:`${join(root,'node_modules/.bin')}:/opt/homebrew/bin:${process.env.PATH}`}
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env})
    const once=readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')
    run(node,['scripts/generate-supabase-types.mjs','--local','--workdir',workdir],{env})
    if(readFileSync(join(root,'src/lib/supabase/database.types.ts'),'utf8')!==once)throw new Error('Database type generation was not deterministic.')
    console.log('Generated/refined database types twice with exact parity.')
  }
  if(process.argv.includes('--browser')){
    run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:readFileSync(join(root,'scripts/acceptance/seed-member-suspension-browser.sql'),'utf8')})
    console.log(run(node,['node_modules/@playwright/test/cli.js','test','--config','playwright.member-suspension.config.ts'],{env:{...process.env,MEMBER_SUSPENSION_SUPABASE_WORKDIR:workdir}}))
  }
}finally{
  if(created){const stopped=spawnSync(node,[cli,'stop','--no-backup','--workdir',workdir],{encoding:'utf8'});if(stopped.status!==0)console.error('Disposable member-suspension stack cleanup failed.');else console.log('Removed the disposable member-suspension stack and data.')}
  rmSync(workdir,{recursive:true,force:true})
}
