-- Rename 'assigned' to 'manually_assigned' (if 'assigned' exists) and add 'auto_assigned' (if not exists)

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_enum 
    WHERE enumtypid = 'staged_status'::regtype 
    AND enumlabel = 'assigned'
  ) THEN
    ALTER TYPE staged_status RENAME VALUE 'assigned' TO 'manually_assigned';
  END IF;
END $$;

ALTER TYPE staged_status ADD VALUE IF NOT EXISTS 'auto_assigned';

