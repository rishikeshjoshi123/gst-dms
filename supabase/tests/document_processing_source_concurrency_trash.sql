\timing on
UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now()
  WHERE id='16610000-0000-4000-8000-000000000005';
SELECT code,object_key FROM public.grant_current_document_processing_source(
  '16610000-0000-4000-8000-000000000008','16610000-0000-4000-8000-000000000009'
);
