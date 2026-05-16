///|
pub(all) struct UpdateResult {
  status : AgentOrientMapStatus
  new_files : Array[String]
  changed_files : Array[String]
  deleted_files : Array[String]
  unchanged_files : Array[String]
  upserted_files : Array[String]
  removed_files : Array[String]
  embedding_count : Int
  upsert_count : Int
  remove_count : Int
}

///|
priv struct UpdateDecision {
  upsert_briefs : Array[LocalFileBrief]
  // Files whose source content hash already matches the cache but whose
  // FileSignature (mtime / size) drifted. We refresh just their attrs via
  // vcdb's `update_attrs` so the next stat-only pass can skip them — without
  // paying for a vector re-embedding pass on every untouched file.
  signature_refresh_briefs : Array[LocalFileBrief]
  new_files : Array[String]
  changed_files : Array[String]
  deleted_files : Array[String]
  unchanged_files : Array[String]
  affected_owners : Array[String]
  knowledge_changed : Bool
}

///|
let update_scan_page_size : Int = 512

///|
pub async fn apply_incremental_updates(
  handle : Handle,
  briefs : Array[LocalFileBrief],
  timestamp_ns? : Int64 = 0L,
) -> UpdateResult raise CacheError {
  apply_incremental_updates_with_cache(handle, briefs, None, timestamp_ns~)
}

///|
/// Same as `apply_incremental_updates`, but lets the caller supply a
/// previously scanned cache snapshot to avoid rescanning the vcdb twice when
/// the caller already paid for one full scan during the classification step.
pub async fn apply_incremental_updates_with_cache(
  handle : Handle,
  briefs : Array[LocalFileBrief],
  cached_files_in : Array[CachedFile]?,
  timestamp_ns? : Int64 = 0L,
) -> UpdateResult raise CacheError {
  let decision = classify_updates_with_cache(handle, briefs, cached_files_in)
  if decision.upsert_briefs.length() > 0 {
    handle.upsert_many(decision.upsert_briefs, timestamp_ns~)
  }
  // Apply signature-only attr refreshes via the cheap update_attrs path —
  // skips vector re-embedding for files whose content is unchanged.
  let cached_by_path : Map[String, CachedFile] = {}
  match cached_files_in {
    Some(files) =>
      for cached in files {
        cached_by_path.set(cached.path, cached)
      }
    None => ()
  }
  for brief in decision.signature_refresh_briefs {
    match cached_by_path.get(brief.path) {
      Some(cached) =>
        handle.refresh_signature_for(cached, brief.mtime_ns, brief.size_bytes,
          timestamp_ns~,
        )
      None => ()
    }
  }
  let removed_files : Array[String] = []
  for path in decision.deleted_files {
    if handle.remove_path(path, timestamp_ns~) {
      removed_files.push(path)
    }
  }
  let cached_after_update = scan_all_cached_files(handle)
  let status = status_from_records(
    cached_after_update,
    decision.changed_files,
    decision.new_files,
    decision.deleted_files,
    decision.knowledge_changed,
    decision.affected_owners,
  )
  let upserted_files = paths_from_briefs(decision.upsert_briefs)
  {
    status,
    new_files: decision.new_files,
    changed_files: decision.changed_files,
    deleted_files: decision.deleted_files,
    unchanged_files: decision.unchanged_files,
    upserted_files,
    removed_files,
    embedding_count: upserted_files.length(),
    upsert_count: upserted_files.length(),
    remove_count: removed_files.length(),
  }
}

///|
pub fn current_status(
  handle : Handle,
) -> AgentOrientMapStatus raise CacheError {
  status_from_records(
    scan_all_cached_files(handle),
    [],
    [],
    [],
    false,
    [],
  )
}

///|
fn classify_updates_with_cache(
  handle : Handle,
  briefs : Array[LocalFileBrief],
  cached_files_in : Array[CachedFile]?,
) -> UpdateDecision raise CacheError {
  let cached_files = match cached_files_in {
    Some(files) => files
    None => scan_all_cached_files(handle)
  }
  let cached_by_path : Map[String, CachedFile] = {}
  for file in cached_files {
    cached_by_path.set(file.path, file)
  }
  let current_hashes : Map[String, String] = {}
  let upsert_briefs : Array[LocalFileBrief] = []
  let new_files : Array[String] = []
  let changed_files : Array[String] = []
  let unchanged_files : Array[String] = []
  let deleted_files : Array[String] = []
  let affected_owners : Array[String] = []
  let mut knowledge_changed = false
  let signature_refresh_briefs : Array[LocalFileBrief] = []
  for brief in briefs {
    current_hashes.set(brief.path, brief.source_hash)
    match cached_by_path.get(brief.path) {
      Some(cached) if cached.source_hash == brief.source_hash => {
        // Source content is unchanged. If the FileSignature drifted, queue
        // an attrs-only refresh so the next stat-only pass can skip this
        // file at the cheaper signature stage. No vector re-embedding.
        if cached.mtime_ns != brief.mtime_ns ||
          cached.size_bytes != brief.size_bytes {
          signature_refresh_briefs.push(brief)
        }
        unchanged_files.push(brief.path)
      }
      Some(_) => {
        changed_files.push(brief.path)
        upsert_briefs.push(brief)
        push_unique_string(affected_owners, @map.owner_dir(brief.path))
        if is_documentation_record(brief) {
          knowledge_changed = true
        }
      }
      None => {
        new_files.push(brief.path)
        upsert_briefs.push(brief)
        push_unique_string(affected_owners, @map.owner_dir(brief.path))
        if is_documentation_record(brief) {
          knowledge_changed = true
        }
      }
    }
  }
  for file in cached_files {
    if !current_hashes.contains(file.path) {
      deleted_files.push(file.path)
      push_unique_string(affected_owners, file.owner)
      if cached_file_is_documentation(file) {
        knowledge_changed = true
      }
    }
  }
  {
    upsert_briefs,
    signature_refresh_briefs,
    new_files,
    changed_files,
    deleted_files,
    unchanged_files,
    affected_owners,
    knowledge_changed,
  }
}

///|
/// Page through the orient vcdb and return every cached file record.
///
/// Callers that need to classify a fresh discovery against the cache should
/// call this once and then pass the result into `apply_incremental_updates`
/// via `apply_incremental_updates_with_cache`, so the cache is scanned only
/// once per orient run instead of twice.
pub fn scan_all_cached_files(
  handle : Handle,
) -> Array[CachedFile] raise CacheError {
  let files : Array[CachedFile] = []
  let mut offset : Int64? = None
  while true {
    let page = handle.scan(offset~, limit=update_scan_page_size)
    if page.length() == 0 {
      break
    }
    for file in page {
      files.push(file)
    }
    if page.length() < update_scan_page_size {
      break
    }
    match page[page.length() - 1].vector_id.as_int64() {
      Some(last_id) => offset = Some(last_id)
      None => break
    }
  }
  files
}

///|
fn status_from_records(
  cached_files : Array[CachedFile],
  changed_files : Array[String],
  new_files : Array[String],
  deleted_files : Array[String],
  knowledge_changed : Bool,
  affected_owners : Array[String],
) -> AgentOrientMapStatus {
  let owner_dirs : Array[String] = []
  let reused_owners : Array[String] = []
  // Until owner profiles are query-backed, count cached documentation records
  // as the conservative doc-source status.
  let mut total_doc_sources = 0
  for file in cached_files {
    push_unique_string(owner_dirs, file.owner)
    if cached_file_is_documentation(file) {
      total_doc_sources += 1
    }
  }
  for owner in owner_dirs {
    if !affected_owners.contains(owner) {
      reused_owners.push(owner)
    }
  }
  {
    total_files: cached_files.length(),
    total_owners: owner_dirs.length(),
    total_doc_sources,
    changed_files,
    new_files,
    deleted_files,
    knowledge_changed,
    refreshed_owners: affected_owners,
    reused_owners,
  }
}

///|
fn paths_from_briefs(briefs : Array[LocalFileBrief]) -> Array[String] {
  let paths : Array[String] = []
  for brief in briefs {
    paths.push(brief.path)
  }
  paths
}

///|
fn cached_file_is_documentation(file : CachedFile) -> Bool {
  file.role == "documentation" || @map.is_documentation_path(file.path)
}

///|
fn push_unique_string(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}
