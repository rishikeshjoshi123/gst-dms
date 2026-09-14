# September 14 — First production release scope

## Confirmed user decisions

- **Target window:** release to the first design partner between **October 12 and October 15, 2026**. A short safety delay is acceptable, but **October 20, 2026 is the final target date**. The date does not waive confidential-data acceptance.
- **Audience and data:** onboard one trusted design-partner organisation with its actual confidential litigation PDFs. The first Owner signs up, verifies email and creates the organisation; that Owner invites the other members, who sign up or sign in and explicitly accept the pending invitation. An invitation link never joins an account silently.
- **Mandatory journey:** sign up → verify email → create or join the organisation → create a Client and Matter → upload a PDF → process it or use a truthful manual recovery path → resolve the applicable Review work → assign/place it → reopen the exact source in Workbench → inspect it in the Matter workspace.
- **Both upload origins are mandatory:** global Intake and upload from inside a Matter use the same canonical queue and processing lifecycle. A Matter-origin upload retains its intended Matter while still appearing in that queue.
- **Document workspace naming:** the overall user-facing workspace is **Document Inbox**. Its processing-focused queue/view is **Upload Queue**. Existing `/documents` routes, internal identifiers and historical evidence remain unchanged until separately authorised implementation updates the product copy.
- **Timeline minimum:** chronology and a truthful read-only graph are mandatory. Human-authored/correctable relationships and quality-gated relationship suggestions are desirable first-release enhancements. Relationship suggestions are the highest-priority conditional feature and the last optional capability to cut; remove them only when current evidence shows they would threaten mandatory acceptance or stabilisation. Suggestions remain non-authoritative until their typed contextual Review decision. Disconnected documents remain visible rather than receiving invented edges.
- **Deadlines and work:** manually verified legal deadlines, including truthful upcoming/due/missed and lifecycle/completion state, are required. Owned Tasks, Notes-to-Task creation and reminders are desirable but not release-critical. A Task date is never presented as an authoritative legal deadline.
- **Review:** extraction conflicts, placement conflicts, possible duplicates, supported recovery failures and enabled relationship candidates are critical Review cases. A type is required only when its producer is enabled; no generic dismissal substitutes for its typed resolver.
- **AI extraction:** source-grounded PDF metadata extraction followed by efficient human Review is the ordinary mandatory workflow and must pass the approved acquisition/extraction gates. A first release that normally makes lawyers hand-type each PDF's metadata does not meet the product-value or release bar. Manual entry/correction, manual placement and human-confirmed relationships remain exceptional recovery/repair paths for provider failure, unreadable pages or corrections—not the expected throughput path. AI candidates never become consequential facts merely because the provider returned them.
- **Retrieval:** matter/current-document cited retrieval is a high-value but non-critical enhancement. Cut it before the mandatory journey or stabilisation window is endangered. Organisation-wide semantic retrieval is not in this release.
- **Administration minimum:** the release needs governed invitations, a truthful Team/member view and immediate Owner/Admin suspension of an ordinary member. Reactivation means an Owner/Admin reverses that suspension and restores the existing member's access without a new invitation; it is useful but not release-critical. Broad role administration, ownership transfer, removal, resignation and full departure automation are not release-critical and remain governed by their existing safeguards/deferrals.
- **Explicit deferrals:** Dashboard/Today, Case Brief, organisation-wide semantic Search, advanced administration, broad Realtime, bulk/non-PDF ingestion, marketing/demo refinement and broad financial functionality are not October requirements. A limited Financials page is desirable only if it does not displace mandatory work.
- **Delivery order:** freeze the release matrix and gates; close signup/upload/Review/reopen; finish the selected graph/deadline scope; attempt relationship suggestions before lower-priority conditional features; add only other conditional work that still fits; then run deployed rehearsal, recovery, monitoring and exact release acceptance. Conditional work is cut before the stabilisation window is consumed, with relationship suggestions cut last among optional capabilities.
- **Capacity:** plan implementation using the currently available Codex allocation. No subscription upgrade is assumed, and reset credits are transient account capacity rather than release acceptance.

## Invitations and accidental organisation creation

The existing create-or-join decision remains in force. When a verified account has pending invitations, those invitations should be visually primary and `Create organisation` secondary. Creation remains explicit and should warn that the current one-organisation rule prevents accepting another invitation afterwards. The sole-member departure/archive/recovery policy is not inferred from this concern; it remains a separate discussion.

## Environment direction and unresolved production authority

The user intends to use `case-chain.com`, Resend and Trigger.dev, initially on their free tiers, and retain the current Google document-intelligence path with `gemini-2.5-flash` for structured extraction. A separate second-account staging stack is proposed so `dev` can deploy independently from the production services connected to `main`.

This direction is not yet production approval. The current proposed pilot assumed Supabase Pro managed daily database backups, while [Supabase Free does not provide automatic backups](https://supabase.com/docs/guides/platform/backups). [Vercel Hobby is documented for non-commercial personal use](https://vercel.com/docs/plans/hobby), which may not cover a business design-partner deployment even when the partner is not paying. The production-environment and recovery options discussion is targeted for **October 1–2, 2026**, then a compliant application host and a tested database-plus-Storage backup/recovery boundary must be selected before confidential upload. Staging and production credentials, projects, branches, buckets, workers, email domains and secrets must remain isolated regardless of account layout.

Changing from Gemini to another provider/model is not authorised by this decision. Any later model, including an OpenAI vision-capable API model, needs separate API billing, data-region/privacy review, frozen structured-output compatibility, representative quality/cost evidence and rollback. The Codex plan used for software development does not pay for application API inference.

## Parked follow-ups

- [Production go-live ownership and incident response](../discovery/production-go-live-ownership-and-incident-response.md) is the next priority discussion and remains a release blocker.
- [Production environment and recovery options](../discovery/production-environment-and-recovery-options.md) is the separate hosting/backup brainstorm targeted for October 1–2, 2026.
- [Last member and empty organisation](../discovery/last-member-and-empty-organisation.md) now includes the user's archived-organisation and governed recovery proposal.
- [Document workspace naming](../discovery/document-workspace-naming.md) records the approved `Document Inbox` workspace and `Upload Queue` view labels; implementation remains separate.
- [Viewer Matter access](../discovery/viewer-matter-access.md) records the post-October requirement for Owner/Admin-selected Matter visibility.
- [Case Brief rethink](../discovery/case-brief-rethink.md) must finish before Case Brief returns to product scope.

## Implementation effect

This record settles the first-release product boundary and reopens affected acceptance where older receipts assumed mandatory retrieval, deferred graph, organisation-wide semantic Search or an enabled Case Brief. It does not start implementation, configure providers, send invitations, mutate a remote database, deploy, or approve confidential-data go-live.
