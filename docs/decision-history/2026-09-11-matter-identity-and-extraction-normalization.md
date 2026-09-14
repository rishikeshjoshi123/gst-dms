# Matter identity, document references, and extraction normalization

- **Decision / date:** `MATTER-IDENTIFIER-POLICY-2026-09-08` resolved on **2026-09-11** by the user after reviewing real GST litigation documents and the consequences of same-year, multi-year, consolidated, and out-of-order proceedings.
- **Canonical plans:** [Document Hub, Ingestion, Placement, Relationships, and Workbench](../plans/features/2026-08-25-document-hub-ingestion-and-workbench.md#matter-identity-correction), [AI Extraction, Provenance, and Model Lifecycle](../plans/platform/2026-08-24-ai-extraction-and-model-lifecycle.md#schema-and-prompt-contract), [Document Record and File Lifecycle](../plans/platform/2026-08-24-document-record-and-file-lifecycle.md), and [Resource Trash, Retention, Restore, and Permanent Purge](../plans/platform/2026-08-24-resource-trash-retention-and-purge.md#restoration).
- **Affected outcomes:** D09 Matter identity and the extraction, placement, relationship, Copy/Move, and Restore acceptance that depends on it. This decision authorises documentation reconciliation only; it does not change schema, data, prompts, placement behavior, or deployment.

## Matter boundary

- A Matter represents one independently progressing or independently challengeable official proceeding chain. It is not defined by client plus financial year, document date, or every financial-year label found in a PDF.
- One SCN or other root proceeding may cover one month, several months, one financial year, several financial years, or non-contiguous periods and normally remains one Matter through its reply, order, appeal, remand, and later orders.
- Separate root SCNs or separately actionable proceedings may be separate Matters even when they concern the same client, GSTIN, provision, tax period, or financial year.
- A consolidated order or appeal can bring several notices or periods into one proceeding chain when an official document explicitly establishes that consolidation or a user confirms it. A PDF that merely contains several independently actionable references does not cause an automatic split or merge; it requires human review.
- The source document's issue/filing/communication dates and its disputed tax periods are different facts. A document issued in FY 2022–23 can belong to a Matter concerning FY 2019–20. `JAN 2020 – JAN 2020` is a valid single-month tax period, not inherently an error.

## Approved identifier policy

- The organisation-unique CaseChain `matter_code` remains the internal identifier. Verified external identifiers are typed and namespaced; GSTIN, PAN, client name, title, financial year, tax period, document date, filename, semantic similarity, and fuzzy/OCR text are evidence only and never establish Matter identity.
- Initial external kinds are `proceeding_case_id`, `notice_reference`, `order_reference`, `appeal_reference`, and `court_case_number`. `other_official_reference` remains suggestion-only until its issuing system, meaning, and collision rules are added to the versioned catalogue.
- Every identifier stores the raw/display text, normalized value and components, kind, issuer or portal namespace, whether it identifies the current document or mentions another document, source page/evidence, verification method, actor/time, and lifecycle state. Normalization can standardize case, Unicode, whitespace, separators, known prefixes, serial/year components, and catalogued aliases without rewriting the displayed source value.
- A verified identity-eligible key is reserved to one Matter within `(organisation, issuer/system namespace, kind, normalized value)` across active and Trash records. A kind may become identity-eligible only when the issuing authority/system defines a sufficiently stable key. Ambiguous, reused, partially read, or unverified values stay candidates and cannot enforce identity.
- AI, OCR, fuzzy matching, dates, document sequence, and client/period agreement may propose a key or candidate but cannot verify it. Verification requires deterministic source evidence plus an authorised human decision or a separately approved trusted official import.
- Corrections and revocations are append-only. They preserve the former value and reason, trigger targeted re-evaluation, and never silently move an assigned document, merge Matters, or rewrite history.
- Trash keeps verified keys reserved. Restore blocks on a genuine active collision and never renames, clears, or merges automatically. After final purge, reuse requires a deliberate authorised creation path; stale references must not auto-place a later unrelated document.

## Extraction and matching contract

- The model returns schema-constrained JSON that is strictly parsed and validated against one canonical Zod/domain contract. The provider schema is generated through a tested compatibility adapter; regex extraction from prose and separately maintained semantic schemas are not supported recovery paths.
- Every material field retains source wording/evidence and a typed normalized value. Confidence and validation state are field-level; one document-wide score cannot conceal an incorrect GSTIN, reference, date, period, or amount.
- Tax periods are a list of typed ranges rather than one display string. The structure supports month, quarter, exact-date range, financial year, multi-financial-year, non-contiguous, and unclear periods while retaining source precision. A month-only source is not expanded into invented day boundaries. Derived and printed financial years are compared; disagreement becomes a focused Review exception.
- The normalization audit covers document/form type and catalogue version; raw/display title; typed client identifiers; client-name aliases for search only; dates classified by legal meaning; financial-year arrays; typed issuer and recipient roles; authority/jurisdiction; self identifiers and outbound references; explicit versus calculated deadlines; decimal-string or integer-paise monetary components with currency, period, and legal posture; typed parties; and normalized legal references with raw evidence preserved.
- Every upload performs both deterministic directions: resolve the current document's outbound reference mentions against existing verified self identifiers, and resolve existing pending mentions against the current document's verified self identifiers. Matching is indexed within the organisation and namespace; it yields unique exact, ambiguous, conflicting, or unresolved outcomes.
- No match is a durable unresolved state, not a failed extraction. A later document or corrected alias triggers targeted re-evaluation. Ambiguity, conflict, missing predecessors, and a document that may contain multiple independent roots remain human decisions.
- Organisation placement remains `manual_suggestions` by default. Even when an Owner/Admin enables strong-evidence auto-placement, only a unique exact verified anchor with no contradiction can place an unassigned item. Already assigned documents never move automatically.

## Repair and storage behavior

- One exact PDF is stored once per organisation. When one source document legitimately belongs in several Matters, each logical document points to the same `file_asset`; CaseChain rebuilds Matter-specific relationships and effective facts without duplicating the bytes.
- An authorised user can repair an initially incorrect boundary by creating the additional Matter, moving exclusive documents, and copying shared documents through the governed Copy/Move flow. The flow shows an impact preview and records the reason and lineage. It does not silently split or merge Matters.
- A controlled Matter-merge workflow remains future scope. The pilot must support safe manual correction without treating an inferred merge as automatic cleanup.

## Implementation impact

The current extraction adapter already uses structured JSON, strict parsing, and Zod validation. Existing plans already specify organisation-default manual placement, shared-asset Copy, and targeted re-evaluation, but those statements are not proof that every live path is implemented. Implementation still needs the approved identifier catalogue and lifecycle, removal of client/year uniqueness with collision-safe creation and Restore, typed tax-period and field normalization, self-identifier storage, bidirectional matching, governed repair, and the new acceptance fixtures. Existing implementation receipts remain historical evidence and affected acceptance is reopened until these changed requirements are implemented and verified.
