import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

async function run() {
  await supabase.from('model_pricing').upsert({
    model_name: 'gemini-2.5-flash',
    input_price_per_1m: 0.30,
    output_price_per_1m: 2.50,
    updated_at: new Date().toISOString()
  }, { onConflict: 'model_name' })
  console.log("Updated gemini-2.5-flash pricing")
}

run()
