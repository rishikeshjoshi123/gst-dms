-- Keep legacy multi-step Move/Copy disabled until the atomic, version-aware
-- placement commands are implemented and verified.

REVOKE UPDATE (matter_id, source)
ON public.documents FROM PUBLIC, anon, authenticated, service_role;
