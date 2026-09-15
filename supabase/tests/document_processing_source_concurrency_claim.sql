BEGIN;
SELECT code FROM public.begin_current_document_processing_ai_extraction(
  '16610000-0000-4000-8000-000000000008','16610000-0000-4000-8000-000000000009',
  'vertex-ai','gemini-2.5-flash','fixture-model','fixture-prompt','fixture-schema','fixture-catalogue','fixture-normalizer'
);
SELECT pg_sleep(2);
COMMIT;
