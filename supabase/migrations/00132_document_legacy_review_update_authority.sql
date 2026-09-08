-- Retire overloaded legacy document review/status writes. Typed Review owns
-- consequential review state; processing transitions remain database commands.

REVOKE UPDATE (status, review_status, review_reason, reviewed_at, reviewed_by)
ON public.documents FROM PUBLIC, anon, authenticated, service_role;
