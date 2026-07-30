const fs = require('fs');
const env = fs.readFileSync('.env.local', 'utf8').split('\n').reduce((acc, line) => {
  if (line && !line.startsWith('#') && line.includes('=')) {
    const [key, ...val] = line.split('=');
    acc[key.trim()] = val.join('=').trim().replace(/^['"]|['"]$/g, '');
  }
  return acc;
}, {});
const { createClient } = require('@supabase/supabase-js');
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
supabase.from('staged_documents').select('id, status, suggested_matter_id, suggestion_reason, raw_metadata').then(res => console.log(JSON.stringify(res.data, null, 2)));
