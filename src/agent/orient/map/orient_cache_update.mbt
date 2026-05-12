///|
pub(all) struct OrientCacheUpdateResult {
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
priv struct OrientCacheUpdateDecision {
  upsert_briefs : Array[LocalFileBrief]
  new_files : Array[String]
  changed_files : Array[String]
  deleted_files : Array[String]
  unchanged_files : Array[String]
  affected_owners : Array[String]
  knowledge_changed : Bool
}

///|
let orient_cache_update_scan_page_size : Int = 512

///|
pub async fn apply_incremental_cache_updates(
  handle : OrientCacheHandle,
  briefs : Array[LocalFileBrief],
  timestamp_ns? : Int64 = 0L,
) -> OrientCacheUpdateResult raise OrientCacheError {
  let decision = classify_orient_cache_updates(handle, briefs)
  if decision.upsert_briefs.length() > 0 {
    handle.upsert_many(decision.upsert_briefs, timestamp_ns~)
  }
  let removed_files : Array[String] = []
  for path in decision.deleted_files {
    if handle.remove_path(path, timestamp_ns~) {
      removed_files.push(path)
    }
  }
  let cached_after_update = scan_all_orient_cached_files(handle)
  let status = cache_update_status_from_records(
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
pub fn current_orient_cache_status(
  handle : OrientCacheHandle,
) -> AgentOrientMapStatus raise OrientCacheError {
  cache_update_status_from_records(
    scan_all_orient_cached_files(handle),
    [],
    [],
    [],
    false,
    [],
  )
}

///|
fn classify_orient_cache_updates(
  handle : OrientCacheHandle,
  briefs : Array[LocalFileBrief],
) -> OrientCacheUpdateDecision raise OrientCacheError {
  let cached_files = scan_all_orient_cached_files(handle)
  let cached_by_path : Map[String, OrientCachedFile] = {}
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
  for brief in briefs {
    current_hashes.set(brief.path, brief.source_hash)
    match cached_by_path.get(brief.path) {
      Some(cached) if cached.source_hash == brief.source_hash =>
        unchanged_files.push(brief.path)
      Some(_) => {
        changed_files.push(brief.path)
        upsert_briefs.push(brief)
        push_unique_string(affected_owners, owner_dir(brief.path))
        if is_documentation_record(brief) {
          knowledge_changed = true
        }
      }
      None => {
        new_files.push(brief.path)
        upsert_briefs.push(brief)
        push_unique_string(affected_owners, owner_dir(brief.path))
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
    new_files,
    changed_files,
    deleted_files,
    unchanged_files,
    affected_owners,
    knowledge_changed,
  }
}

///|
fn scan_all_orient_cached_files(
  handle : OrientCacheHandle,
) -> Array[OrientCachedFile] raise OrientCacheError {
  let files : Array[OrientCachedFile] = []
  let mut offset : Int64? = None
  while true {
    let page = handle.scan(offset~, limit=orient_cache_update_scan_page_size)
    if page.length() == 0 {
      break
    }
    for file in page {
      files.push(file)
    }
    if page.length() < orient_cache_update_scan_page_size {
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
fn cache_update_status_from_records(
  cached_files : Array[OrientCachedFile],
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
fn cached_file_is_documentation(file : OrientCachedFile) -> Bool {
  file.role == "documentation" || is_documentation_path(file.path)
}

///|
fn push_unique_string(values : Array[String], value : String) -> Unit {
  if !values.contains(value) {
    values.push(value)
  }
}
