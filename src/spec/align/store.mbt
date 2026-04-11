///|
let align_manifest_file : String = "manifest.json"

///|
let align_trace_file : String = "trace.json"

///|
let align_report_file : String = "report.json"

///|
let align_history_file : String = "history.json"

///|
fn cache_file_path(cache_dir : String, file_name : String) -> String {
  @reconcile_store.cache_path(cache_dir, file_name)
}

///|
fn resolve_cache_dir(config : SpecAlignConfig) -> String? {
  if config.cache_dir.length() > 0 {
    return Some(config.cache_dir)
  }
  let anchor = if config.impl_path.length() > 0 {
    config.impl_path
  } else {
    config.spec_path
  }
  match @config.resolve_project_indexion_dir(anchor, "cache/spec/align") {
    Some(dir) => Some(dir)
    None => {
      println(
        "Error: failed to resolve `.indexion/cache/spec/align` from project root. " +
        "Specify --cache-dir explicitly or run inside an initialized project.",
      )
      None
    }
  }
}

///|
fn write_json_file(path : String, json : Json) -> Bool {
  @reconcile_store.write_json_file(path, json, "align cache file") is Ok(_)
}

///|
fn read_json_file(path : String) -> Json? {
  match @reconcile_store.read_json_file(path, "align cache file") {
    Ok(json) => Some(json)
    Err(_) => None
  }
}

///|
fn load_history_entries(cache_dir : String) -> Array[AlignHistoryEntry]? {
  let path = cache_file_path(cache_dir, align_history_file)
  if !@fs.path_exists(path) {
    return Some([])
  }
  let json = match read_json_file(path) {
    Some(value) => value
    None => return None
  }
  let store : AlignHistoryStore = @json.from_json(json) catch {
    _ => return None
  }
  Some(store.entries)
}

///|
fn load_snapshot(cache_dir : String) -> AlignSnapshot? {
  let manifest_path = cache_file_path(cache_dir, align_manifest_file)
  if !@fs.path_exists(manifest_path) {
    return None
  }
  let manifest_json = match read_json_file(manifest_path) {
    Some(value) => value
    None => return None
  }
  let trace_json = match
    read_json_file(cache_file_path(cache_dir, align_trace_file)) {
    Some(value) => value
    None => return None
  }
  let report_json = match
    read_json_file(cache_file_path(cache_dir, align_report_file)) {
    Some(value) => value
    None => return None
  }
  let history_entries = match load_history_entries(cache_dir) {
    Some(entries) => entries
    None => return None
  }
  let manifest : AlignCacheManifest = @json.from_json(manifest_json) catch {
    _ => return None
  }
  let trace : AlignTraceStore = @json.from_json(trace_json) catch {
    _ => return None
  }
  let report : AlignDiffStore = @json.from_json(report_json) catch {
    _ => return None
  }
  Some({
    version: manifest.version,
    generated_at: manifest.generated_at,
    config: manifest.config,
    requirements: trace.requirements,
    scenarios: trace.scenarios,
    implementations: trace.implementations,
    trace_edges: trace.edges,
    diff_items: report.items,
    summary: manifest.summary,
    file_hashes: manifest.file_hashes,
    source_fingerprint: manifest.source_fingerprint,
    used_specs: manifest.used_specs,
    commit: manifest.commit,
    history: history_entries,
    cache_hit: true,
  })
}

///|
fn has_cache_artifacts(cache_dir : String) -> Bool {
  @fs.path_exists(cache_file_path(cache_dir, align_manifest_file)) ||
  @fs.path_exists(cache_file_path(cache_dir, align_trace_file)) ||
  @fs.path_exists(cache_file_path(cache_dir, align_report_file)) ||
  @fs.path_exists(cache_file_path(cache_dir, align_history_file)) ||
  @fs.path_exists(cache_file_path(cache_dir, "snapshot.json"))
}

///|
fn purge_cache_file(cache_dir : String, file_name : String) -> Bool {
  let path = cache_file_path(cache_dir, file_name)
  if !@fs.path_exists(path) {
    return true
  }
  @fs.remove_file(path) catch {
    _ => return false
  }
  true
}

///|
fn purge_corrupt_snapshot_cache(cache_dir : String) -> Bool {
  purge_cache_file(cache_dir, align_manifest_file) &&
  purge_cache_file(cache_dir, align_trace_file) &&
  purge_cache_file(cache_dir, align_report_file) &&
  purge_cache_file(cache_dir, align_history_file) &&
  purge_cache_file(cache_dir, "snapshot.json")
}

///|
fn append_history_entry(
  existing : Array[AlignHistoryEntry],
  snapshot : AlignSnapshot,
) -> Array[AlignHistoryEntry] {
  let next = existing.copy()
  let entry : AlignHistoryEntry = {
    generated_at: snapshot.generated_at,
    source_fingerprint: snapshot.source_fingerprint,
    summary: snapshot.summary,
    commit: snapshot.commit,
  }
  let should_append = match next.last() {
    Some(last) =>
      last.source_fingerprint != entry.source_fingerprint ||
      last.commit != entry.commit
    None => true
  }
  if should_append {
    next.push(entry)
  } else if next.length() > 0 {
    next[next.length() - 1] = entry
  }
  next
}

///|
fn save_snapshot(cache_dir : String, snapshot : AlignSnapshot) -> Bool {
  if @reconcile_store.ensure_cache_dir(cache_dir, "align cache path") is Err(_) {
    return false
  }
  let history_entries = match load_history_entries(cache_dir) {
    Some(entries) => append_history_entry(entries, snapshot)
    None => return false
  }
  let manifest : AlignCacheManifest = {
    version: snapshot.version,
    generated_at: snapshot.generated_at,
    config: snapshot.config,
    summary: snapshot.summary,
    file_hashes: snapshot.file_hashes,
    source_fingerprint: snapshot.source_fingerprint,
    used_specs: snapshot.used_specs,
    commit: snapshot.commit,
    history_count: history_entries.length(),
  }
  let trace_store : AlignTraceStore = {
    requirements: snapshot.requirements,
    scenarios: snapshot.scenarios,
    implementations: snapshot.implementations,
    edges: snapshot.trace_edges,
  }
  let diff_store : AlignDiffStore = { items: snapshot.diff_items }
  let history_store : AlignHistoryStore = { entries: history_entries }
  write_json_file(
    cache_file_path(cache_dir, align_manifest_file),
    manifest.to_json(),
  ) &&
  write_json_file(
    cache_file_path(cache_dir, align_trace_file),
    trace_store.to_json(),
  ) &&
  write_json_file(
    cache_file_path(cache_dir, align_report_file),
    diff_store.to_json(),
  ) &&
  write_json_file(
    cache_file_path(cache_dir, align_history_file),
    history_store.to_json(),
  )
}
