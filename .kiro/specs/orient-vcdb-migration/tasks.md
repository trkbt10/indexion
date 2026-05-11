# Implementation Plan

- [ ] 1. Foundation: cache runtime, layout, and safety prerequisites
- [x] 1.1 Prepare orient cache runtime integration
  - Make the orient cache code able to use the native database, embedding provider, path hashing, and async filesystem lock primitives through the existing package system.
  - Keep the public report model and Markdown / JSON format choices available while preparing the orient entry flow for async cache operations.
  - The package graph reaches a buildable state where the new persistence, embedding, hash, and lock primitives can be imported without unresolved dependency errors.
  - _Requirements: 7, 11_
  - _Boundary: OrientAgentEntry_

- [x] 1.2 Establish versioned cache layout and invalidation decisions
  - Create the new cache-local layout for bounded metadata, persisted vocabulary, writer lock target, and native database storage under the configured cache directory.
  - Recognize prior JSON cache layouts by path only and treat missing, old, or mismatched metadata as a fresh-build trigger when updates are allowed.
  - In read-only mode, invalid cache states surface as an unavailable or empty cache diagnostic without mutating the cache directory.
  - A fresh cache visibly carries the new version identifier, and an old map file does not need to be parsed to continue safely.
  - _Requirements: 5, 7, 9, 12_
  - _Boundary: OrientCacheStore_

- [x] 1.3 Add writer lock behavior for mutable cache access
  - Acquire an exclusive advisory lock before any cache mutation and keep the lock handle alive for the entire update path.
  - Return a typed lock-conflict failure immediately when another writer already owns the cache.
  - Keep lock and storage paths inside the configured cache directory and rely on operating system lock release after process termination.
  - A second concurrent writer exits before mutating cache state while the winning writer can complete normally.
  - _Requirements: 7, 8, 9_
  - _Boundary: OrientWriterLock_

- [ ] 2. Persistence: file records, vocabulary, and incremental updates
- [x] 2.1 (P) Define deterministic file record identity and flat attributes
  - Derive one stable record identity from each normalized analyzed-file path and validate that an existing record's path still matches that identity before overwriting it.
  - Store path, role, owner, source hash, structural summary, and bounded summary preview as separate string attributes, with full pre-tokenized summary text only for documentation records.
  - Avoid packing multiple logical fields into one serialized attribute value.
  - A file brief converts to exactly one filterable record whose role can be matched directly and whose identity is reused across separate runs for the same path.
  - _Requirements: 1, 2, 3, 10_
  - _Boundary: OrientRecordSchema_

- [x] 2.2 (P) Implement persisted TF-IDF vocabulary lifecycle
  - Build the TF-IDF provider from the full analyzed corpus only when creating a fresh cache.
  - Persist and reload the vocabulary so subsequent runs reuse the same dimension and term weights rather than rebuilding from a partial corpus.
  - Treat missing, unreadable, empty, or dimension-mismatched vocabulary state as cache invalidation, with no implicit rebuild unless the cache itself is being rebuilt.
  - A second run visibly loads the persisted vocabulary, and a mismatched vocabulary prevents use of the existing database.
  - _Requirements: 4, 5, 9, 12_
  - _Boundary: OrientVocabularyStore_

- [x] 2.3 Open and operate the vcdb-backed cache store
  - Open the native persistent database only after the vocabulary dimension and cache metadata have been validated.
  - Support record lookup, filtered scanning, vector search, upsert, remove, and checkpoint operations without falling back to aggregate JSON persistence.
  - Propagate database, storage, replay, and checkpoint failures as cache errors rather than silently discarding them.
  - The cache can be created, reopened, counted, searched, updated, and checkpointed with a database dimension matching the persisted vocabulary.
  - _Depends: 2.1, 2.2_
  - _Requirements: 1, 2, 4, 5, 7, 9, 12_
  - _Boundary: OrientCacheStore_

- [x] 2.4 Adapt source brief generation for bounded cache inputs
  - Produce cache-ready structural summaries and bounded previews without creating a repository-sized serialized graph or retaining full code-file content for persistence.
  - Preserve the role and owner signals needed by the record schema and report composition.
  - Keep full pre-tokenized summary text available only for documentation records where the schema allows it.
  - Source discovery yields cache input records that are bounded for code files and still support the existing report shape.
  - _Requirements: 1, 3, 10, 11_
  - _Boundary: SourceDiscovery_

- [x] 2.5 Apply incremental record updates
  - Compare current source hashes with cached record attributes to classify new, changed, deleted, and unchanged files.
  - Embed and upsert only new or changed files, remove deleted records, and skip both embedding and upsert for unchanged files.
  - Populate the existing map status counters from update decisions and cache counts instead of persisted owner profiles.
  - A no-op refresh over an unchanged corpus recomputes zero embeddings, performs zero upserts, and still reports current cache status.
  - _Depends: 2.3, 2.4_
  - _Requirements: 1, 2, 4, 10_
  - _Boundary: OrientCacheUpdater_

- [ ] 3. Query and report composition
- [x] 3.1 Build vector-similarity query service with role filters
  - Embed the task text with the same persisted TF-IDF provider used during ingestion.
  - Use vector search with role filters to derive implementation owners, consumer surfaces, command-line consumers, documentation sources, forbidden surfaces, preflight paths, and evidence candidates.
  - Aggregate owner candidates from top-ranked implementation hits only, not from an in-memory scan of every cached token list.
  - Query results visibly return role-filtered candidates, and a consumer-role filter can find consumer records without JSON parsing.
  - _Depends: 2.3_
  - _Requirements: 3, 6, 11_
  - _Boundary: OrientQueryService_

- [ ] 3.2 Preserve report composition over query results
  - Convert query candidates into the existing orient report fields, workflow, notes, map status, readiness quiz, preflight, and evidence sections.
  - Preserve Markdown section headings, section order, JSON field names, and the existing format choices.
  - Keep storage-specific attributes out of the public report while using bounded previews for evidence text.
  - Reports produced from the new query result have the same public shape and rendered section order as the current orient output.
  - _Depends: 3.1_
  - _Requirements: 6, 11_
  - _Boundary: ReportComposerAdapter_

- [ ] 4. Integration: orient entry, CLI behavior, and build surface
- [ ] 4.1 Integrate the async orient workflow for update and read-only modes
  - Coordinate writer locking, source discovery, vocabulary state, cache opening, incremental update, query execution, and report composition from the orient entry flow.
  - Ensure update mode never mutates without the writer lock and read-only mode never rebuilds or rewrites an invalid cache.
  - Preserve safe recovery behavior by relying on database replay for committed records after interruption.
  - Update mode can build a fresh cache and produce a report, while read-only mode can query an existing cache without mutation.
  - _Depends: 1.3, 2.5, 3.2_
  - _Requirements: 5, 7, 8, 9, 10, 11, 12_
  - _Boundary: OrientAgentEntry_

- [ ] 4.2 Maintain CLI compatibility and failure semantics
  - Await the async orient entry while keeping the existing Markdown and JSON renderers and format flag behavior unchanged.
  - Translate writer-lock conflicts into a non-zero command result with a concise diagnostic.
  - Avoid host-process rename, move, or shell command atomicity in the write path.
  - Markdown and JSON invocations emit the same headings and field shapes, and lock conflict exits non-zero before cache mutation.
  - _Depends: 4.1_
  - _Requirements: 7, 8, 11_
  - _Boundary: Agent CLI_

- [ ] 4.3 Regenerate interfaces and resolve package build integration
  - Regenerate affected package interfaces after the async orient entry and cache components are wired.
  - Keep dependency usage within the approved native database, embedding, hash, and filesystem-lock boundaries.
  - Confirm the public report and renderer contracts remain compatible after interface generation.
  - Relevant MoonBit package checks succeed with generated interfaces matching the new async cache workflow.
  - _Depends: 4.2_
  - _Requirements: 7, 11_
  - _Boundary: PackageIntegration_

- [ ] 5. Validation: storage, recovery, queries, and compatibility
- [ ] 5.1 Verify schema and vocabulary behavior
  - Cover stable path identity, different-path identity separation, collision protection, required flat attributes, documentation-only full summaries, bounded previews, and absence of packed JSON attributes.
  - Cover vector length, deterministic embedding with a persisted vocabulary, vocabulary reuse, and vocabulary mismatch invalidation.
  - Tests fail if required attributes are missing, duplicate path records are created, or vectors no longer match the persisted dimension.
  - _Requirements: 1, 2, 3, 4, 5, 12_
  - _Boundary: OrientRecordSchema, OrientVocabularyStore_

- [ ] 5.2 Verify incremental update and query selection
  - Cover unchanged-file skips, changed-file upserts to the same identity, deleted-record removal, and status counter updates.
  - Cover role-filtered vector search for owners, consumers, command-line consumers, documentation sources, and evidence candidates.
  - Tests demonstrate that a no-op refresh performs zero embeddings and zero upserts, and that query selection no longer depends on full-map token intersection.
  - _Depends: 5.1_
  - _Requirements: 3, 4, 6, 10_
  - _Boundary: OrientCacheUpdater, OrientQueryService_

- [ ] 5.3 Verify native persistence, locking, and recovery
  - Cover cache creation, process-local reopen, persisted record visibility, old-layout invalidation, and vocabulary/database dimension checks with native storage.
  - Cover concurrent writer attempts where exactly one writer succeeds and the losing writer reports a lock conflict.
  - Cover interrupted-write recovery by reopening through the persistent database and confirming committed records remain queryable.
  - A subsequent read-only orient run succeeds against the winning writer's state after a conflict or interruption.
  - _Depends: 5.1_
  - _Requirements: 7, 8, 9, 12_
  - _Boundary: OrientCacheStore, OrientWriterLock_

- [ ] 5.4 Verify CLI output compatibility and large-corpus boundedness
  - Compare Markdown section headings and order before and after the migration.
  - Compare JSON output shape for version, task, map status, workflow, and notes.
  - Exercise a synthetic large corpus whose aggregate summaries exceed the previous single-value failure case and verify the update completes without repository-sized JSON serialization.
  - Exercise an unchanged corpus through the command path and verify no embeddings or upserts are performed while the report still renders.
  - CLI regression and large-corpus checks pass with the existing public output shape preserved.
  - _Depends: 4.3, 5.2, 5.3_
  - _Requirements: 1, 6, 10, 11_
  - _Boundary: Agent CLI, EndToEndValidation_
