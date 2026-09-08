-- Keep legacy destructive reclassification disabled until the governed impact
-- preview, archival, reason, and reevaluation command is implemented.

REVOKE UPDATE (document_class, document_category)
ON public.documents FROM PUBLIC, anon, authenticated, service_role;
