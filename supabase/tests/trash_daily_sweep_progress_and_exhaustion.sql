-- Disposable rollback fixture. A lost continuation after 100 held roots must
-- not prevent the next daily null wake from reaching a later overdue root.
BEGIN;
DO $test$
DECLARE
  org uuid:='164b0000-0000-0000-0000-000000000001';
  owner uuid:='164a0000-0000-0000-0000-000000000001';
  client_id uuid:='164c0000-0000-0000-0000-000000000001';
  matter_id uuid:='164d0000-0000-0000-0000-000000000001';
  document_id uuid; operation_id uuid; later_operation uuid; release_operation uuid;
  page record; blocker record; i integer;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES('00000000-0000-0000-0000-000000000000',owner,'authenticated','authenticated',
      'trash-progress-owner@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Trash progress fixture',owner);
  UPDATE public.organisations o SET owner_membership_id=m.id
    FROM public.organisation_memberships m WHERE o.id=org AND m.org_id=org AND m.user_id=owner;
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org,'Trash progress client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
    VALUES(matter_id,org,client_id,'Trash progress matter','TRASH-PROGRESS');
  IF has_table_privilege('service_role','public.trash_purge_sweep_progress','SELECT,UPDATE')
    OR has_table_privilege('authenticated','public.trash_purge_sweep_progress','SELECT,UPDATE')
    OR NOT has_function_privilege('service_role','public.enqueue_due_trash_purges_page(integer,timestamptz,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'durable sweep cursor authority leaked or worker execute grant disappeared';
  END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'role','authenticated','sub',owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);

  FOR i IN 1..102 LOOP
    document_id:=gen_random_uuid();
    INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title)
      VALUES(document_id,org,matter_id,'fixture/progress-'||i||'.pdf',owner,'Progress document '||i);
    SELECT result.operation_id INTO operation_id
      FROM public.trash_resource('document',document_id,'trash.progress.'||i) result;
    IF operation_id IS NULL THEN RAISE EXCEPTION 'fixture Trash command failed at %',i; END IF;
    UPDATE public.trash_operations SET auto_purge_enabled_snapshot=true,
      purge_eligible_at=now()-CASE WHEN i<=101 THEN interval '2 seconds' ELSE interval '1 second' END,
      auto_purge_at=now()-CASE WHEN i<=101 THEN interval '2 seconds' ELSE interval '1 second' END
      WHERE id=operation_id;
    IF i<=101 THEN
      SELECT * INTO blocker FROM public.register_trash_purge_blocker(
        operation_id,'document',document_id,'active_export',gen_random_uuid(),true);
      IF blocker.code<>'active' THEN RAISE EXCEPTION 'fixture blocker failed at %',i; END IF;
    ELSE
      later_operation:=operation_id;
    END IF;
  END LOOP;

  SELECT * INTO page FROM public.enqueue_due_trash_purges_page(100,NULL,NULL);
  IF page.examined_count<>100 OR page.blocked_count<>100 OR page.queued_count<>0
    OR NOT EXISTS(SELECT 1 FROM public.trash_purge_sweep_progress WHERE id=1 AND scan_after_id IS NOT NULL)
    OR EXISTS(SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=later_operation) THEN
    RAISE EXCEPTION 'first bounded sweep did not persist its held-root cursor';
  END IF;
  -- No continuation arrives. The next daily caller supplies a null cursor.
  SELECT * INTO page FROM public.enqueue_due_trash_purges_page(100,NULL,NULL);
  IF page.examined_count<>2 OR page.blocked_count<>1 OR page.queued_count<>1
    OR NOT EXISTS(SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=later_operation)
    OR NOT EXISTS(SELECT 1 FROM public.trash_purge_sweep_progress WHERE id=1 AND scan_after_id IS NULL) THEN
    RAISE EXCEPTION 'next daily null wake stranded the later overdue root';
  END IF;
  SELECT id INTO release_operation FROM public.trash_operations
    WHERE org_id=org AND id<>later_operation ORDER BY auto_purge_at,id LIMIT 1;
  SELECT * INTO blocker FROM public.register_trash_purge_blocker(
    release_operation,'document',(SELECT root_resource_id FROM public.trash_operations WHERE id=release_operation),
    'active_export',(SELECT row_blocker.opaque_reference FROM public.trash_purge_blockers row_blocker
      WHERE row_blocker.operation_id=release_operation LIMIT 1),false);
  IF blocker.code<>'released' THEN RAISE EXCEPTION 'hold release fixture failed'; END IF;
  SELECT * INTO page FROM public.enqueue_due_trash_purges_page(100,NULL,NULL);
  IF page.queued_count<>1
    OR NOT EXISTS(SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=release_operation)
    OR (SELECT count(*) FROM public.trash_purge_jobs job WHERE job.operation_id=later_operation)<>1 THEN
    RAISE EXCEPTION 'released blocker was not revisited safely or duplicate wake requeued a root';
  END IF;
END $test$;
ROLLBACK;
