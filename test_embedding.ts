import { generateEmbedding } from './src/lib/ai/vertex.js';

async function run() {
  const res = await generateEmbedding("hello world");
  console.log(res ? res.embedding.length : 'failed');
}
run();
