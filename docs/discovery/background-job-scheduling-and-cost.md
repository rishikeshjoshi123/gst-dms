# Background job scheduling and cost

Status: parked for a separate brainstorming session on 2026-09-11.

## Problem

CaseChain already contains recurring Trigger.dev schedules for document outbox recovery, document lifecycle reconciliation, Trash attention, Trash purge and terminal-asset cleanup. More background work will arrive with OCR, indexing, reminders, notifications, digests, backups and operational reconciliation. Independent frequent pollers can consume the Trigger.dev Free credit even when they find no work.

The Trash discussion approved one daily midnight-IST purge sweep, but did not optimise the rest of the fleet.

## Future discussion

Inventory every deployed and planned background job, its trigger, urgency/SLA, expected volume, no-work duration, work duration, retry policy, concurrency and provider cost. Compare:

- event-driven or delayed runs with a low-frequency recovery sweep;
- consolidation of compatible maintenance queries into one dispatcher;
- daily, hourly and near-real-time schedules only where the user-facing contract requires them;
- database-native scheduling versus Trigger.dev, including observability and operational ownership;
- bounded exponential backoff for actual failures rather than empty polling;
- Free-plan credits, production spend alerts and the upgrade threshold.

The session should end with a decision-complete schedule catalogue, monthly cost envelope, failure/recovery policy and required Platform Jobs visibility. It must recheck current provider pricing and actual deployed schedules; this note does not approve implementation or remote configuration.

## Related plans

- [Platform Operations](../plans/platform/2026-08-27-platform-operations.md)
- [Trash retention and purge](../plans/platform/2026-08-24-resource-trash-retention-and-purge.md)
- [Work, notifications and Today](../plans/features/2026-08-25-work-review-activity-notifications.md)
