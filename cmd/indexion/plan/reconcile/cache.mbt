///|
fn manifest_path(index_dir : String) -> String {
  index_dir + "/manifest.json"
}

///|
fn report_cache_path(index_dir : String) -> String {
  index_dir + "/report.json"
}

///|
fn stale_index_path(index_dir : String) -> String {
  index_dir + "/index.json"
}

///|
fn load_manifest(index_dir : String) -> ReconcileManifest {
  let path = manifest_path(index_dir)
  let content = @fs.read_file_to_string(path) catch {
    _ => return ReconcileManifest::empty()
  }
  let json = @json.parse(content) catch {
    _ => return ReconcileManifest::empty()
  }
  @json.from_json(json) catch {
    _ => ReconcileManifest::empty()
  }
}

///|
fn save_manifest(index_dir : String, manifest : ReconcileManifest) -> Unit {
  @config_paths.ensure_dir_recursive(index_dir)
  let path = manifest_path(index_dir)
  let content = manifest.to_json().stringify(indent=2)
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn load_cached_report(index_dir : String) -> ReconcileReport? {
  let path = report_cache_path(index_dir)
  let content = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(content) catch { _ => return None }
  @json.from_json(json) catch {
    _ => None
  }
}

///|
fn save_cached_report(index_dir : String, report : ReconcileReport) -> Unit {
  @config_paths.ensure_dir_recursive(index_dir)
  let path = report_cache_path(index_dir)
  let content = report.to_json().stringify(indent=2)
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}

///|
fn cleanup_stale_index(index_dir : String) -> Unit {
  let path = stale_index_path(index_dir)
  if not(@fs.path_exists(path)) {
    return
  }
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
fn build_config_hash(config : ReconcileConfig) -> String {
  make_hash([
    config.target_dir,
    config.specs_dir,
    config.index_dir,
    config.format,
    config.documents.scope_name,
    config.documents.doc_paths.join("\u0001"),
    config.documents.doc_specs.join("\u0001"),
    config.threshold_seconds.to_string(),
    config.max_candidates.to_string(),
    config.allow_file_fallback.to_string(),
    config.git_preferred.to_string(),
    config.mtime_fallback.to_string(),
    config.logical_review_mode,
  ])
}

///|
fn build_source_fingerprint(
  config_hash : String,
  file_states : Array[FileState],
) -> String {
  let entries : Array[String] = []
  let sorted = file_states.copy()
  sorted.sort_by(fn(a, b) { a.path.compare(b.path) })
  for state in sorted {
    entries.push(state.path)
    entries.push(state.file_kind)
    entries.push(state.spec)
    entries.push(state.content_hash)
    entries.push(
      match state.git_time {
        Some(v) => v.to_string()
        None => ""
      },
    )
    entries.push(
      match state.mtime {
        Some(v) => v.to_string()
        None => ""
      },
    )
    entries.push(state.git_dirty.to_string())
  }
  make_hash([config_hash, entries.join("\u0000")])
}
