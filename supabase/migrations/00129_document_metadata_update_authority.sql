-- Retire the legacy mutable document metadata surface. Human corrections are
-- owned by the existing immutable field-decision and inspector commands.

REVOKE UPDATE (
  ai_prompt_version, confidence_scores, doc_date, doc_type, financial_year,
  raw_metadata, reference_number
) ON public.documents FROM PUBLIC, anon, authenticated, service_role;
