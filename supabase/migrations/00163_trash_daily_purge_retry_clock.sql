-- Repair the unrelated 00162 trigger's table-shape branch so purge-induced
-- Matter/Client updates cannot dereference file-asset-only NEW fields.
CREATE OR REPLACE FUNCTION public.ambiguous_intake_review_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_TABLE_NAME='intake_items' THEN
    IF OLD.state='ready' AND NEW.state='assigned' AND EXISTS(
      SELECT 1 FROM public.review_items i WHERE i.intake_id=NEW.id AND i.type='ambiguous_placement' AND i.status='needs_review'
    ) THEN RAISE EXCEPTION 'ambiguous_intake_requires_typed_review'; END IF;
    IF NEW.state<>'ready' OR NEW.asset_id IS DISTINCT FROM OLD.asset_id OR NEW.intended_matter_id IS NOT NULL
      OR NEW.updated_at IS DISTINCT FROM OLD.updated_at THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE intake_id=NEW.id AND type='ambiguous_placement' AND status='needs_review';
      UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
        WHERE intake_id=NEW.id AND state='ambiguous';
    END IF;
  ELSIF TG_TABLE_NAME='file_assets' THEN
    IF (NEW.availability IS DISTINCT FROM OLD.availability
      OR NEW.storage_deleted_at IS DISTINCT FROM OLD.storage_deleted_at
      OR NEW.sha256 IS DISTINCT FROM OLD.sha256
      OR NEW.detected_mime_type IS DISTINCT FROM OLD.detected_mime_type
      OR NEW.validated_page_count IS DISTINCT FROM OLD.validated_page_count) THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE intake_asset_id=NEW.id AND type='ambiguous_placement' AND status='needs_review';
      UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
        WHERE asset_id=NEW.id AND state='ambiguous';
    END IF;
  ELSIF TG_TABLE_NAME='matters' THEN
    IF (NEW.record_state<>'active' OR NEW.deleted_at IS NOT NULL OR NEW.revision<>OLD.revision) THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_unavailable',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE type='ambiguous_placement' AND status='needs_review' AND placement_run_id IN(
          SELECT placement_run_id FROM public.intake_placement_candidates WHERE matter_id=NEW.id
        );
      UPDATE public.intake_placement_runs SET state='unavailable',unavailable_at=now()
        WHERE state='ambiguous' AND id IN(SELECT placement_run_id FROM public.intake_placement_candidates WHERE matter_id=NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- Durable failure-specific retry, keyset daily sweep, and lease recovery.
ALTER TABLE public.trash_purge_jobs ADD COLUMN next_attempt_at timestamptz;
CREATE INDEX trash_purge_retry_due_idx ON public.trash_purge_jobs(next_attempt_at,created_at,id)
  WHERE state IN ('retryable','waiting_storage');

CREATE FUNCTION public.trash_purge_retry_clock_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF NEW.state='retryable' AND NEW.attempt_count=0 AND NEW.safe_error_code IS NULL THEN
    -- Governed manual retry intentionally wakes immediately.
    NEW.next_attempt_at:=NULL;
  ELSIF NEW.state='retryable' AND (OLD.state IS DISTINCT FROM NEW.state OR OLD.safe_error_code IS DISTINCT FROM NEW.safe_error_code) THEN
    NEW.next_attempt_at:=now()+make_interval(secs=>least(3600,30*power(2,least(greatest(NEW.attempt_count-1,0),7))::integer));
  ELSIF NEW.state IN ('queued','running','completed','blocked') THEN
    NEW.next_attempt_at:=NULL;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trash_purge_retry_clock_guard BEFORE UPDATE ON public.trash_purge_jobs
FOR EACH ROW EXECUTE FUNCTION public.trash_purge_retry_clock_guard();

CREATE OR REPLACE FUNCTION public.claim_trash_purge_work(p_batch_size integer DEFAULT 10,p_lease_seconds integer DEFAULT 120)
RETURNS TABLE(job_id uuid,operation_id uuid,org_id uuid,lease_token uuid,database_prepared boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate public.trash_purge_jobs%ROWTYPE; operation public.trash_operations%ROWTYPE;
DECLARE token uuid; active_blockers integer; current_fingerprint text;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 50 OR p_lease_seconds NOT BETWEEN 30 AND 600 THEN
    RAISE EXCEPTION 'invalid Trash purge lease request';
  END IF;
  -- Recover abandoned work. Purging resources remain fenced and inaccessible.
  UPDATE public.trash_purge_jobs job SET state='retryable',lease_token=NULL,lease_expires_at=NULL,
    safe_error_code='stale_lease'
  WHERE job.state='running' AND job.lease_expires_at<=now();
  UPDATE public.trash_operations target_operation SET state='purge_failed',purge_failed_at=now(),
    last_error_code='stale_lease',updated_at=now()
  WHERE target_operation.state='purging' AND EXISTS (
    SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=target_operation.id
      AND job.state='retryable' AND job.safe_error_code='stale_lease'
  );
  UPDATE public.trash_purge_jobs job SET state='blocked',safe_error_code='retry_exhausted'
    WHERE job.state='retryable' AND job.attempt_count>=20;
  FOR candidate IN
    SELECT job.* FROM public.trash_purge_jobs job
    WHERE job.state IN ('queued','retryable','waiting_storage') AND job.attempt_count<20
      AND (job.next_attempt_at IS NULL OR job.next_attempt_at<=now())
    ORDER BY job.created_at,job.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  LOOP
    SELECT * INTO operation FROM public.trash_operations WHERE id=candidate.operation_id FOR UPDATE;
    IF operation.id IS NULL OR operation.state IN ('restored','purged') THEN
      UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='not_available' WHERE id=candidate.id;
      CONTINUE;
    END IF;
    IF candidate.database_prepared_at IS NULL THEN
      SELECT count(*)::integer INTO active_blockers
        FROM public.trash_purge_active_blockers(operation.org_id,operation.id);
      IF active_blockers>0 THEN
        UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='purge_blocked' WHERE id=candidate.id;
        UPDATE public.trash_operations SET blocker_count=active_blockers,last_error_code='purge_blocked',updated_at=now() WHERE id=operation.id;
        CONTINUE;
      END IF;
      current_fingerprint:=public.trash_purge_impact_fingerprint(operation.org_id,operation.id);
      IF candidate.source='manual' AND candidate.attempt_count=0
         AND candidate.impact_fingerprint IS DISTINCT FROM current_fingerprint THEN
        UPDATE public.trash_purge_jobs SET state='blocked',safe_error_code='stale_impact' WHERE id=candidate.id;
        CONTINUE;
      ELSIF candidate.source='retention_schedule' THEN
        UPDATE public.trash_purge_jobs SET impact_fingerprint=current_fingerprint WHERE id=candidate.id;
      END IF;
      IF operation.state IN ('trashed','restore_blocked','purge_scheduled') THEN
        UPDATE public.trash_operations SET state='purging',purge_started_at=coalesce(purge_started_at,now()),
          purge_failed_at=NULL,last_error_code=NULL,blocker_count=0,updated_at=now() WHERE id=operation.id;
        UPDATE public.resource_trash_memberships target_member SET state='purging',updated_at=now()
          WHERE target_member.org_id=operation.org_id AND target_member.operation_id=operation.id AND target_member.state='active';
        UPDATE public.clients client SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='client' AND member.resource_id=client.id AND client.org_id=member.org_id;
        UPDATE public.matters matter SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='matter' AND member.resource_id=matter.id AND matter.org_id=member.org_id;
        UPDATE public.documents document SET record_state='purging'
          FROM public.resource_trash_memberships member WHERE member.org_id=operation.org_id AND member.operation_id=operation.id
            AND member.resource_type='document' AND member.resource_id=document.id AND document.org_id=member.org_id;
      ELSIF operation.state='purge_failed' THEN
        UPDATE public.trash_operations SET state='purging',purge_failed_at=NULL,last_error_code=NULL,updated_at=now() WHERE id=operation.id;
      END IF;
    ELSIF operation.state='purge_failed' THEN
      UPDATE public.trash_operations SET state='purging',purge_failed_at=NULL,last_error_code=NULL,updated_at=now() WHERE id=operation.id;
    END IF;
    token:=gen_random_uuid();
    UPDATE public.trash_purge_jobs SET state='running',attempt_count=attempt_count+1,
      lease_token=token,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),
      started_at=coalesce(started_at,now()),safe_error_code=NULL WHERE id=candidate.id;
    RETURN QUERY SELECT candidate.id,candidate.operation_id,candidate.org_id,token,candidate.database_prepared_at IS NOT NULL;
  END LOOP;
END $$;


CREATE FUNCTION public.enqueue_due_trash_purges_page(p_batch_size integer DEFAULT 100,
  p_after_at timestamptz DEFAULT NULL,p_after_id uuid DEFAULT NULL)
RETURNS TABLE(queued_count integer,blocked_count integer,examined_count integer,last_at timestamptz,last_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate record; queued integer:=0; blocked integer:=0; examined integer:=0; active_blockers integer;
DECLARE cursor_at timestamptz:=p_after_at; cursor_id uuid:=p_after_id;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 500 OR ((cursor_at IS NULL)<>(cursor_id IS NULL)) THEN
    RAISE EXCEPTION 'invalid Trash purge page';
  END IF;
  FOR candidate IN
    SELECT operation.* FROM public.trash_operations operation
    WHERE operation.auto_purge_enabled_snapshot AND operation.auto_purge_at<=now()
      AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
      AND NOT EXISTS (SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=operation.id)
      AND (cursor_at IS NULL OR (operation.auto_purge_at,operation.id)>(cursor_at,cursor_id))
    ORDER BY operation.auto_purge_at,operation.id FOR UPDATE SKIP LOCKED LIMIT p_batch_size
  LOOP
    examined:=examined+1; cursor_at:=candidate.auto_purge_at; cursor_id:=candidate.id;
    SELECT count(*)::integer INTO active_blockers FROM public.trash_purge_active_blockers(candidate.org_id,candidate.id);
    IF active_blockers>0 THEN
      blocked:=blocked+1;
      UPDATE public.trash_operations SET blocker_count=active_blockers,last_error_code='purge_blocked',updated_at=now()
        WHERE id=candidate.id;
    ELSE
      INSERT INTO public.trash_purge_jobs(org_id,operation_id,source,impact_fingerprint)
        VALUES(candidate.org_id,candidate.id,'retention_schedule',public.trash_purge_impact_fingerprint(candidate.org_id,candidate.id));
      queued:=queued+1;
    END IF;
  END LOOP;
  RETURN QUERY SELECT queued,blocked,examined,cursor_at,cursor_id;
END $$;

CREATE FUNCTION public.next_trash_purge_failure_wake()
RETURNS TABLE(wake_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT min(candidate.at) FROM (
    SELECT job.next_attempt_at AS at FROM public.trash_purge_jobs job
      WHERE job.state IN ('retryable','waiting_storage') AND job.attempt_count<20
    UNION ALL
    SELECT job.lease_expires_at AS at FROM public.trash_purge_jobs job
      WHERE job.state='running'
  ) candidate WHERE candidate.at IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.enqueue_due_trash_purges_page(integer,timestamptz,uuid),
  public.next_trash_purge_failure_wake(),public.trash_purge_retry_clock_guard() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_due_trash_purges_page(integer,timestamptz,uuid),
  public.next_trash_purge_failure_wake() TO service_role;
