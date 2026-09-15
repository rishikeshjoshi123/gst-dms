-- Persist page progress so a missed Trigger continuation cannot leave later
-- overdue operations behind a long sequence of held roots.
CREATE TABLE public.trash_purge_sweep_progress (
  id integer PRIMARY KEY CHECK (id=1),
  scan_after_at timestamptz,
  scan_after_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trash_purge_sweep_cursor_shape CHECK ((scan_after_at IS NULL)=(scan_after_id IS NULL))
);
INSERT INTO public.trash_purge_sweep_progress(id) VALUES(1);
ALTER TABLE public.trash_purge_sweep_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trash_purge_sweep_progress FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.trash_purge_sweep_progress FROM PUBLIC,anon,authenticated,service_role;

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
    WHERE job.state IN ('retryable','waiting_storage') AND job.attempt_count>=20;
  UPDATE public.trash_operations exhausted_operation SET state='purge_failed',
    purge_failed_at=coalesce(exhausted_operation.purge_failed_at,now()),last_error_code='retry_exhausted',updated_at=now()
  WHERE exhausted_operation.state IN ('purging','purge_failed') AND EXISTS (
    SELECT 1 FROM public.trash_purge_jobs job WHERE job.operation_id=exhausted_operation.id
      AND job.state='blocked' AND job.safe_error_code='retry_exhausted'
  );
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


CREATE OR REPLACE FUNCTION public.enqueue_due_trash_purges_page(p_batch_size integer DEFAULT 100,
  p_after_at timestamptz DEFAULT NULL,p_after_id uuid DEFAULT NULL)
RETURNS TABLE(queued_count integer,blocked_count integer,examined_count integer,last_at timestamptz,last_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE candidate record; queued integer:=0; blocked integer:=0; examined integer:=0; active_blockers integer;
DECLARE cursor_at timestamptz:=p_after_at; cursor_id uuid:=p_after_id;
BEGIN
  IF p_batch_size NOT BETWEEN 1 AND 500 OR ((cursor_at IS NULL)<>(cursor_id IS NULL)) THEN
    RAISE EXCEPTION 'invalid Trash purge page';
  END IF;
  -- Trigger payload cursors are hints only; the singleton database cursor is
  -- authoritative and survives a lost continuation or duplicate daily wake.
  SELECT progress.scan_after_at,progress.scan_after_id INTO cursor_at,cursor_id
    FROM public.trash_purge_sweep_progress progress WHERE progress.id=1 FOR UPDATE;
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
  UPDATE public.trash_purge_sweep_progress SET
    scan_after_at=CASE WHEN examined=p_batch_size THEN cursor_at ELSE NULL END,
    scan_after_id=CASE WHEN examined=p_batch_size THEN cursor_id ELSE NULL END,
    updated_at=now() WHERE id=1;
  RETURN QUERY SELECT queued,blocked,examined,cursor_at,cursor_id;
END $$;



-- Exhausted waiting_storage/retryable work is reconciled by one failure wake,
-- not by a second routine schedule.
CREATE OR REPLACE FUNCTION public.next_trash_purge_failure_wake()
RETURNS TABLE(wake_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT min(candidate.at) FROM (
    SELECT job.next_attempt_at AS at FROM public.trash_purge_jobs job
      WHERE job.state IN ('retryable','waiting_storage') AND job.attempt_count<20
    UNION ALL
    SELECT job.lease_expires_at AS at FROM public.trash_purge_jobs job WHERE job.state='running'
    UNION ALL
    SELECT now() AS at FROM public.trash_purge_jobs job
      WHERE job.state IN ('retryable','waiting_storage') AND job.attempt_count>=20
  ) candidate WHERE candidate.at IS NOT NULL
$$;
