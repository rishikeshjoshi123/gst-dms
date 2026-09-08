-- Public signup may proceed only for the email bound to a live, opaque
-- invitation-accept intent. The nonce is stored and compared only as a hash.

CREATE FUNCTION public.validate_organisation_invitation_signup(
  p_nonce_hash text,
  p_email text
) RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT CASE WHEN EXISTS (
    SELECT 1
    FROM public.organisation_invitation_accept_intents AS intent
    JOIN public.organisation_invites AS invitation ON invitation.id=intent.invite_id
    WHERE intent.nonce_hash=p_nonce_hash
      AND intent.consumed_at IS NULL
      AND intent.expires_at>now()
      AND invitation.state='pending'
      AND invitation.expires_at>now()
      AND invitation.normalized_email=lower(btrim(p_email))
  ) THEN 'eligible'::text ELSE 'not_available'::text END
$$;

REVOKE ALL ON FUNCTION public.validate_organisation_invitation_signup(text,text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_organisation_invitation_signup(text,text)
TO anon, authenticated;

COMMENT ON FUNCTION public.validate_organisation_invitation_signup(text,text) IS
  'Non-disclosing signup eligibility check bound to a live hashed invitation-intent nonce and normalized invite email.';
