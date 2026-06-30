import { generateEmbedding } from './vertex'

async function run() {
  console.log('Testing Vertex AI...')
  console.log('GOOGLE_CLOUD_PROJECT:', process.env.GOOGLE_CLOUD_PROJECT)
  
  try {
    const text = 'Testing the embedding generation from vertex AI.'
    console.log(`Generating embedding for text: "${text}"`)
    const embedding = await generateEmbedding(text)
    
    if (embedding) {
      console.log('✅ Embedding generated successfully!')
      console.log(`Embedding dimensions: ${embedding.length}`)
      console.log(`First 5 values: ${embedding.slice(0, 5).join(', ')}`)
    } else {
      console.error('❌ Failed to generate embedding (returned null).')
    }
  } catch (err) {
    console.error('❌ Exception during Vertex AI test:', err)
  }
}

run()
