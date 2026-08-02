-- Rename 'assigned' to 'manually_assigned' and add 'auto_assigned'

BEGIN;

ALTER TYPE staged_status RENAME VALUE 'assigned' TO 'manually_assigned';
ALTER TYPE staged_status ADD VALUE 'auto_assigned';

COMMIT;
