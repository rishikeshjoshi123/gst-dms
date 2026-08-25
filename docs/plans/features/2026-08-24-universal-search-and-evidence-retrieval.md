---
title: CaseChain Universal Search and Evidence Retrieval
status: proposed
created: 2026-08-24
updated: 2026-08-24
owners:
  - product
  - engineering
related:
  - ../design-system/2026-08-20-casechain-design-system-overhaul.md
---

# CaseChain Universal Search and Evidence Retrieval

## Summary

Replace the broken dashboard lookup with an organisation-wide, scope-aware search system that can find entities, exact legal references, structured facts, and semantically related evidence. Search will combine identifier and full-text matching, page-aware vector retrieval, and validated structured filters; it will return explainable results with document/page citations rather than opaque similarity matches.

The global entry point will be available from the authenticated application shell and will open a dedicated Search workspace for deeper investigation. The dashboard may expose the same entry point, but search is an application capability rather than a dashboard-owned feature.

## Context and Goals

The current implementation stores one 768-dimensional vector on each document, generated only from document type, reference number, and summary. The dashboard invokes `searchAll(query, false)`, so semantic retrieval is disabled. If enabled, query text is incorrectly embedded with the document retrieval task type, and vector-only matches are fetched but omitted from the returned result collection. The current design also cannot reliably satisfy queries involving passages absent from the summary, numeric comparisons, dates, or compound filters.

The intended users are GST-litigation professionals searching a growing organisation corpus. Representative queries include:

- `matters where we relied on section 6 in an appeal`
- `documents demanding more than 14 lakh`
- `orders discussing extended limitation for FY 2021-22`
- an exact GSTIN, reference number, matter code, client, or filename
- passages conceptually related to natural justice even when that phrase is not used verbatim

Some organisations will initially import spreadsheet-maintained proceeding registers without possessing every corresponding PDF. These imported rows are valid searchable timeline records, but their search coverage must honestly distinguish supplied metadata from attached source-document content.

The system must find the best evidence quickly, preserve tenant isolation, explain why each result matched, and deep-link to the exact page or application record. It must not present vector similarity as a verified legal conclusion.

Initial scope includes clients, matters, proceeding and supporting documents, document passages, notes, Case Brief sections, deadlines, and financial entries. Activity remains filterable through the Activity workspace and is not semantically embedded in the initial release. Generated answer or chat functionality is deferred until retrieval quality and citation coverage pass the evaluation gate in this plan.

## Decisions

### Product and interaction model

- Name the capability **Search**, not Semantic Search. Users search CaseChain; the retrieval techniques remain implementation details.
- Provide a persistent shell entry point with the `Search CaseChain` label and `Cmd/Ctrl+K` shortcut. The dashboard may show a larger version of the same control but will not own its state or implementation.
- Use two interaction depths:
  - A command palette for rapid entity navigation and exact identifier matches.
  - A full `/search` workspace for natural-language queries, grouped results, scopes, filters, saved searches, and pagination.
- Support Organisation, Client, Matter, and Current document scopes. A scope is a relational filter over one shared index, not a separately generated embedding.
- Run cheap entity/prefix suggestions while typing. Run query embedding and deep retrieval only on explicit submission or after selecting a suggested query; do not create a paid embedding on every keystroke.
- Group results by Matters, Documents and passages, Notes, Case Brief, Deadlines, Financials, and Clients. Users can switch to a relevance-ranked combined view.
- Every result must show why it matched: exact identifier, matched passage, interpreted structured constraint, semantic similarity, or a combination. Similarity percentages are not user-facing confidence scores.
- Document results show client, matter, document type/reference/date, a highlighted passage, and PDF page. Selecting one opens the shared Document Workbench at that page and highlights the cited passage or region.
- Matter results are aggregated from matching matter fields, structured facts, and child content. They show the strongest supporting matches so users can understand why the matter was returned.
- Preserve the submitted query, scope, filters, active group, and pagination in the URL so searches are shareable within the same authorised organisation.
- Saved searches are private by default. Explicit sharing with the organisation is available only to members with access to every included scope. Raw query history is not stored by default.

### Retrieval model

- Implement hybrid retrieval rather than vector-only search:
  1. exact and prefix matches for GSTINs, matter codes, reference numbers, filenames, parties, and normalised legal provisions;
  2. PostgreSQL full-text ranking for literal passage matches;
  3. vector similarity for conceptual passage matches;
  4. typed relational filters for amounts, dates, financial years, statuses, document classes/types, people, clients, and matters;
  5. reciprocal-rank fusion followed by small, documented boosts for exact identifiers and verified facts.
- Never use vector similarity to implement numeric or date comparison. `amount greater than 14L` is parsed as INR `> 1,400,000` and evaluated against normalised financial facts. Indian units such as thousand, lakh/lac/L, and crore/Cr are supported.
- Parse natural-language constraints into a Zod-validated `SearchIntent`. The parser may use deterministic extraction and an AI-assisted fallback, but it produces only an allowlisted typed object. It never produces SQL. Server code compiles the validated object into parameterised queries.
- Normalise legal references into act, provision kind, number, subclauses, and aliases where extraction supports it. Exact legal-reference matches are combined with semantic context such as `used for appeal`.
- Embed page-aware content chunks, not an entire document and not only its summary. Prefer heading and paragraph boundaries, target 600–900 tokens, cap chunks below the embedding model's per-input limit, use approximately 80 tokens of overlap, and retain page-start/page-end plus source offsets.
- Prefix embedded chunks with stable context useful for retrieval: document title/type/reference, client, matter, date, financial year, and applicable act when known. Do not add speculative metadata.
- Create each chunk embedding once and tag it with `org_id`, `client_id`, `matter_id`, `document_id`, document class, page range, content hash, and extraction/model versions. Client- and matter-level search aggregates tagged chunk results; it does not duplicate vectors.
- Use `RETRIEVAL_DOCUMENT` for corpus chunks and `RETRIEVAL_QUERY` for search queries. Introduce an embedding provider interface with explicit task type, model, dimensions, token count, and truncation reporting.
- Use Vertex AI `gemini-embedding-001` at 768 output dimensions for the initial rebuilt index, subject to the fixed offline relevance gate below. Store the model identifier and embedding version on every row so a future migration can run side-by-side. Disable silent truncation and split overlong input instead.
- Keep document summaries searchable as fields, but do not let a summary vector stand in for passage indexing.
- Scanned PDFs use OCR text and word/page coordinates. Pages without reliable text remain searchable by verified metadata and summary and are visibly labelled as having limited content search.
- Treat a document record and its file attachment as separate concerns. Spreadsheet-imported records without a PDF participate in exact, full-text metadata, legal-reference, financial, date, and timeline search immediately and carry `content_availability = metadata_only`.
- Do not generate a document-body embedding from sparse imported fields merely to make every row vector-searchable. If an import supplies a meaningful human-written abstract, index it as an `imported_abstract` chunk with explicit provenance; otherwise use structured and lexical retrieval only.
- Attaching a PDF to an imported record preserves the document identity and timeline links, creates versioned page/OCR chunks, and upgrades search coverage without discarding the original imported values or provenance. Conflicts between imported and extracted fields enter Review rather than silently overwriting either source.
- Notes and Case Brief blocks use the same search-item contract with their own source locators and access checks. Their embeddings are regenerated only when searchable content changes.
- Do not use the search embedding for duplicate detection. Exact duplicates use file/content hashes; near-duplicate review, if retained, uses a separately versioned representation and evaluation threshold.

### Ranking and quality

- Retrieve independent candidate lists for exact, full-text, vector, and structured-fact matches, then fuse ranks using reciprocal-rank fusion. Do not use a single hard cosine threshold as the primary relevance decision.
- Rank verified structured facts above provisional AI-extracted facts when both satisfy the same constraint. Clearly label provisional matches.
- Do not apply a general recency boost to evidence passages. Recency may break ties for navigation entities but must not hide older legally decisive material.
- Collapse many matching chunks from one document in the combined view while allowing users to expand all matching passages.
- Return no generated answer in the initial release. A later `Ask CaseChain` mode may be enabled only after the retrieval evaluation set meets its targets and the answerer can cite every material claim to accessible document pages.

### Security, privacy, and lifecycle

- Every indexed row carries `org_id` and applicable parent IDs and is protected by RLS. Search RPCs derive accessible organisation scope from `auth.uid()` and must not trust a caller-supplied organisation ID as authorisation.
- Search results must obey the same current and future matter/document permissions as their source records. Search must not reveal counts, snippets, filenames, embeddings, or existence of inaccessible records.
- Service-role indexing is asynchronous and writes only to the source record's organisation and parents. Client-supplied parent IDs are revalidated server-side.
- Do not persist raw query telemetry. Store aggregate latency, result-count, source-type, and failure metrics without query text. User-created saved searches are the explicit exception.
- Soft deletion removes content from retrieval immediately; hard deletion removes chunks and saved-result references. Reclassification, reassignment, OCR replacement, or document replacement invalidates and rebuilds affected chunks.
- Treat embeddings as sensitive derived tenant data. They remain in the CaseChain database, are excluded from client payloads, exports, logs, and platform-admin content views, and follow the source content's deletion lifecycle.

### Cost and reliability

- Generate embeddings asynchronously after extraction and page-aware chunking. Document processing can complete while search indexing shows `Indexing`; indexing failure is retryable and does not mark legal extraction as failed.
- Batch corpus embedding requests within provider limits and use content hashes to avoid recomputing unchanged chunks.
- Generate at most one query embedding per submitted query. Use a short-lived in-process cache keyed by a cryptographic hash of normalised query plus embedding version; do not persist raw query text in the cache.
- Track actual provider token/billable usage returned by the API; do not record character count as token count.
- Provide per-organisation indexing counts, last successful indexing time, failure count, and embedding usage to platform operations without exposing indexed content.
- Search degrades gracefully: if query embedding fails, exact, full-text, and structured search still return results and the UI explains that conceptual matching was temporarily unavailable.

## Implementation Plan

1. **Create a relevance and security baseline.** Build an anonymised fixture corpus and a versioned evaluation set containing exact identifiers, legal provisions, synonyms, numeric comparisons, date/FY filters, mixed Hindi/English phrasing where relevant, scanned pages, negative queries, and cross-tenant isolation cases. Record current search results before replacing it.
2. **Separate embedding responsibilities.** Replace the current `generateEmbedding(text)` helper with a typed provider contract for corpus, query, similarity, and optional fact-verification tasks. Return model, dimensions, actual token count, truncation state, and billable usage. Stop using query/document embeddings interchangeably.
3. **Introduce searchable content storage.** Add `search_items`, `search_chunks`, `search_legal_references`, `saved_searches`, and indexing-run/failure records with RLS, source foreign keys, deletion behavior, full-text vectors, source locators, content hashes, and embedding versions. Use HNSW cosine indexing for the rebuilt 768-dimensional chunk index; retain exact search when the corpus is too small to justify approximate search.
4. **Build page-aware extraction and chunking.** Chunk extracted/OCR text along document structure while retaining page and character/region anchors. Upsert only changed chunks. Index metadata-only imported records without fabricating document content, then add page chunks in place when a PDF is attached. Backfill existing active documents in resumable organisation batches with progress and retry controls.
5. **Normalise structured facts.** Index document types, parties, GSTINs, financial years, legal provisions, deadlines, and amounts from the canonical structured domains. Define INR unit parsing and operator semantics. Do not query arbitrary `raw_metadata` paths directly from user input.
6. **Implement the query interpreter.** Produce a Zod-validated `SearchIntent` containing free text, scope, entity types, exact identifiers, legal references, amount predicates, date/FY predicates, status/classification filters, and sort. Reject or ignore unsupported predicates with a visible explanation rather than guessing.
7. **Implement secure hybrid search RPCs.** Run exact, full-text, vector, and structured candidate queries under caller RLS; fuse with reciprocal-rank fusion; aggregate passage matches into document and matter results; return source locators and machine-readable match reasons. Verify query plans with organisation/matter filters and tune HNSW iterative scanning only when supported by the deployed pgvector version and measured corpus size.
8. **Replace the dashboard-only UI.** Add the shell search entry, command palette, and `/search` workspace using shared design-system inputs, filters, rows, status indicators, empty/error/loading states, and mobile drill-down. Keep one principal scroller on mobile and preserve filters in the URL.
9. **Connect deep links.** Open clients and matters directly; open document passage results in `DocumentWorkbench` at the PDF page with a temporary highlight; open notes and Case Brief blocks at their thread/section anchors; open deadline and financial results in their matter sections.
10. **Add operational controls.** Expose indexing state on documents, organisation backfill progress, safe reindex by source/version, failure retry, usage accounting, and provider outage degradation. Do not expose a manual rebuild control to ordinary users.
11. **Run shadow evaluation and cut over.** Compare rebuilt results against the frozen evaluation set and current production-like queries without showing the new ranking to users. Cut over only after relevance, isolation, deep-link, and latency targets pass. Retire `documents.embedding` and the old match RPCs after rollback coverage expires.
12. **Gate cited answers separately.** After search launch, evaluate a small cited-answer prototype over retrieved passages. Ship it only through a separate approved plan if every material answer statement can link to accessible evidence and abstention behavior passes testing.

## Interfaces and Data Changes

### Typed query contract

```ts
type SearchIntent = {
  queryText: string
  scope: {
    kind: 'organisation' | 'client' | 'matter' | 'document'
    id?: string
  }
  entityTypes: Array<
    'client' | 'matter' | 'document' | 'passage' | 'note' |
    'case_brief' | 'deadline' | 'financial'
  >
  identifiers: Array<{
    kind: 'gstin' | 'matter_code' | 'reference_number'
    value: string
  }>
  legalReferences: Array<{
    act?: string
    provisionKind: 'section' | 'rule' | 'notification' | 'circular' | 'other'
    number: string
    subclauses?: string[]
  }>
  amountPredicates: Array<{
    field?: 'demand' | 'tax' | 'interest' | 'penalty' | 'pre_deposit' | 'other'
    operator: 'eq' | 'gt' | 'gte' | 'lt' | 'lte' | 'between'
    valuePaise: number
    upperValuePaise?: number
  }>
  datePredicates: Array<{
    field: 'document_date' | 'deadline' | 'created_at'
    operator: 'on' | 'before' | 'after' | 'between'
    value: string
    upperValue?: string
  }>
  financialYears: string[]
  documentTypes: string[]
  documentClasses: Array<'proceeding' | 'supporting'>
  statuses: string[]
  sort: 'relevance' | 'newest' | 'oldest'
}
```

The runtime schema is authoritative and rejects unknown keys and operators. Currency is stored and compared in paise; UI formatting uses INR lakh/crore conventions without losing exact values.

### Core storage contracts

- `search_items`: one searchable application entity or content owner, including source type/id, organisation/client/matter/document lineage, visibility state, `content_availability` (`metadata_only`, `abstract_only`, `source_attached`, `source_indexed`, or `source_unreadable`), title, searchable metadata, content and indexing versions, and timestamps.
- `search_chunks`: page-aware text content, ordinal, page range, character/source anchors, full-text vector, `vector(768)` embedding, model/version, token count, content hash, and extraction quality.
- `search_legal_references`: normalised act/provision identifiers linked to source items/chunks with provenance and verification state.
- `search_index_runs`: source/version, state, attempt, counts, usage, error code, and timestamps without extracted text.
- `saved_searches`: owner, organisation, name, validated query JSON, visibility, and timestamps; RLS keeps private searches private.
- `SearchResult`: entity identity, lineage, route/source locator, title/subtitle, best snippet, match reasons, provisional/verified state, and grouped supporting matches. Raw embeddings are never returned.

The old `documents.embedding`, `match_documents`, and `match_all_documents` contracts remain temporarily during backfill and are then removed in a follow-up migration. Duplicate detection moves to hash-first logic before removal.

## Testing and Acceptance Criteria

- Maintain a versioned evaluation set with at least 100 anonymised queries across exact navigation, lexical, semantic, legal-reference, numeric, date/FY, compound-filter, scanned-document, multilingual, no-result, and adversarial categories.
- Achieve at least 95% Recall@5 for exact/reference and structured-fact queries and at least 85% Recall@10 for judged semantic queries before cutover. No critical expected result may regress from rank 1 to outside the first page without explicit adjudication.
- Return the correct `> INR 14 lakh` set for boundary values below, equal to, and above INR 1,400,000; cover lakh/lac/L and crore/Cr inputs and paise-safe comparisons.
- Prove with automated cross-tenant tests that a user cannot infer inaccessible result counts, titles, snippets, filenames, saved searches, or vectors through RPC parameters, malformed filters, timing-oriented pagination, or direct table access.
- Verify current and future matter-level permissions across search items, chunks, notes, Case Brief blocks, deadlines, and financial entries.
- Every passage fixture deep-links to the correct document version and PDF page. When a text/region anchor exists, the expected passage is highlighted after zoom, rotation, and responsive layout changes.
- Spreadsheet-imported records appear in exact and structured search before a PDF exists, are labelled `Metadata only`, do not claim passage matches, and gain page-level results after attachment without changing their document ID or timeline relationships.
- Deleting, replacing, reassigning, or reclassifying a source removes stale results and rebuilds only affected index rows. Model-version migration supports side-by-side backfill and rollback without mixing incomparable vectors.
- Keyword/structured search still works during embedding-provider outage. Failed indexing is visible to authorised operators and safely retryable.
- On the representative production-like corpus, target p95 under 300 ms for navigation suggestions and under 1.5 seconds for submitted hybrid search excluding cold provider start; measure and publish actual latency rather than weakening relevance to meet the target silently.
- Query submission creates one query embedding at most, typing creates none, unchanged chunks are not re-embedded, and usage accounting records provider token/billable values rather than character counts.
- Test desktop and mobile, keyboard-only operation, screen readers, long snippets, empty/error/loading/partial-index states, no-result recovery, and 200% zoom under the CaseChain design-system contract.
- Do not enable generated answers until a separately reviewed citation-completeness, abstention, prompt-injection, and access-control evaluation passes.

## Assumptions

- All current organisation members can search the same tenant content they can already open; the schema and RLS design must still support future matter-level restrictions.
- Document extraction or OCR can provide page-aware text for most proceeding documents. Metadata-only fallback remains available when it cannot.
- PostgreSQL full-text search and pgvector remain the primary search infrastructure for the first release; an external search service is not required at the expected initial scale.
- English is the primary legal-document language, but the selected embedding model and evaluation set support multilingual queries and mixed-language content where CaseChain encounters it.
- The full Search capability is part of the application overhaul, but generated legal answers are not implicitly approved by this plan.

## Open Questions

None.
