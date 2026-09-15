import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { requireNode24 } from './runtime.mjs'

const node=requireNode24(), root=process.cwd(), workdir=mkdtempSync(join(tmpdir(),'dms-explicit-due-'))
const cli=join(root,'node_modules/supabase/dist/supabase.js')
const container='supabase_db_dms-explicit-due-165'
let created=false
function run(command,args,options={}) {
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',maxBuffer:20*1024*1024,...options})
  if(result.error||result.status!==0) throw new Error(`${command} failed: ${result.error?.message??`${result.stderr}\n${result.stdout}`}`)
  return result.stdout
}
try {
  if(run('docker',['ps','-a','--format','{{.Names}}']).split('\n').some(name=>name.endsWith('_dms-explicit-due-165')))
    throw new Error('The isolated due-date acceptance project is already owned by another run.')
  cpSync(join(root,'supabase/migrations'),join(workdir,'supabase/migrations'),{recursive:true})
  writeFileSync(join(workdir,'supabase/config.toml'),`project_id = "dms-explicit-due-165"
[api]
port = 56521
schemas = ["public", "graphql_public"]
[db]
port = 56522
shadow_port = 56520
major_version = 17
[db.seed]
enabled = false
[studio]
enabled = false
port = 56523
[local_smtp]
enabled = true
port = 56524
[auth]
site_url = "http://127.0.0.1:3115"
[auth.email]
enable_confirmations = false
[analytics]
enabled = false
port = 56527
`)
  created=true
  console.log('Replaying all migrations in isolated dms-explicit-due-165.')
  run(node,[cli,'start','--workdir',workdir])
  const lint=run(node,[cli,'db','lint','--local','--workdir',workdir,'--level','error'])
  if(JSON.parse(lint).results?.length) throw new Error('Disposable database lint found errors.')
  console.log('Error-level database lint passed.')
  for(const fixture of ['extraction_conflict_review_setup.sql','explicit_due_date_review.sql']){
    console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{
      input:readFileSync(join(root,'supabase/tests',fixture),'utf8')
    }))
  }
  console.log(run('docker',['exec','-i',container,'psql','-X','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{
    input:readFileSync(join(root,'supabase/tests/explicit_due_date_browser_setup.sql'),'utf8')
  }))
  console.log(run('bash',['supabase/tests/explicit_due_date_concurrency.sh'],{
    env:{...process.env,SUPABASE_DB_CONTAINER:container}
  }))
} finally {
  if(created){
    const stopped=spawnSync(node,[cli,'stop','--no-backup','--workdir',workdir],{encoding:'utf8'})
    if(stopped.status!==0) console.error('Disposable due-date stack cleanup failed.')
    else console.log('Removed disposable due-date stack and data.')
  }
  rmSync(workdir,{recursive:true,force:true})
}
