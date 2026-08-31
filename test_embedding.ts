import { vertexEmbeddingProvider } from './src/lib/ai/vertex.js';

async function run() {
  const res = await vertexEmbeddingProvider.embed({ input: "hello world", purpose: 'corpus' });
  console.log(res ? res.embedding.length : 'failed');
}
run();
