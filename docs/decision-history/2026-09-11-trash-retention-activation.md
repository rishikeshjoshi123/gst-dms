# Trash retention activation and expiry boundary

Date: 2026-09-11

## Decision

- The first confidential-data pilot uses the approved organisation Trash retention policy. Each new root Trash operation snapshots the organisation's 30, 60, or 90-day period, with 90 days as the default, and is automatically purged after that period.
- At the exact recorded retention deadline, an ordinary eligible resource is logically expired: it disappears from `/trash`, exact user-facing routes stop disclosing it, and Restore is no longer available even if physical database and Storage cleanup finishes later. Legal holds and other mandatory blockers remain visible to authorised Owner/Admin users with a truthful blocked state instead of being represented as deleted.
- Physical cleanup remains asynchronous, durable, idempotent, dependency ordered, and retryable. A failed purge does not make the resource readable again; authorised platform operations expose only content-safe job state and governed retry.
- The pilot does not surface the previously implemented 24-hour Trash Team-attention item. Its final presentation is deferred to the future Today/Dashboard design, whose product purpose is to answer “what needs my attention?”. Before expiry, the Trash workspace itself should distinguish groups in their final seven days and state the remaining days or hours without relying on colour alone.
- The initial operating assumption is India-only organisations and users. Organisation-facing retention times use India Standard Time (`Asia/Kolkata`); a member travelling abroad does not change the organisation policy or deadline. Database timestamps remain UTC instants.

## Scheduling and cost decision

- The pilot uses one routine physical-purge sweep per day at midnight in `Asia/Kolkata`, not once-per-minute polling. The sweep selects every eligible operation whose exact retention deadline is at or before database `now()`, including overdue work missed by an earlier run, and drains bounded durable jobs.
- The daily sweep allows up to approximately 24 hours between logical expiry and physical cleanup. This does not extend user access: secured readers enforce the exact deadline independently of the batch.
- Retries are created only for actual failed purge jobs under the durable idempotent job contract. Bounded exponential backoff and governed manual retry do not create another always-running purge poller.
- The complete background-job fleet, Trigger.dev usage and opportunities to consolidate, delay or replace polling schedules will be considered in a separate product/engineering brainstorming session. See [Background job scheduling and cost](../discovery/background-job-scheduling-and-cost.md).

As observed on 2026-09-11, the repository declares four once-per-minute Trigger.dev schedules and one five-minute schedule. At the then-current [Trigger.dev production invocation price](https://trigger.dev/pricing) of $0.000025 per run, those schedules alone would create 181,440 monthly runs and about $4.54 in invocation charges in a 30-day month before compute. The minute purge reconciler also triggers a separate dispatcher run, raising the observed fleet's minimum to at least 224,640 runs and about $5.62 before compute if every declared schedule is deployed continuously; work-triggered child runs can increase it further. Provider pricing must be rechecked at implementation and release time.

## Consequences

- `PILOT-RETENTION-SCOPE-2026-09-08` is resolved in favour of activation; the conflicting pilot statements that disabled automatic retention/permanent purge are superseded.
- `PILOT-PURGE-SCHEDULER-CADENCE-2026-09-11` is resolved in favour of one daily midnight-IST sweep. D03/D13 remain open for code reconciliation and deployed acceptance. Current readers, the 24-hour projection, scheduler configuration, job monitoring, and release manifest must be checked against this changed requirement.
- This record authorises documentation reconciliation only. It does not deploy a schedule, enable a remote worker, mutate production data, or establish that the revised behavior is implemented.
