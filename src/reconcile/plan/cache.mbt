// --- Reconcile index file name constants (SoT within this package) ---
// All reconcile-specific file names are defined here.
// index_db.mbt also uses reconcile_path() for records.db.

///|
let reconcile_manifest_file : String = "manifest.json"

///|
let reconcile_report_file : String = "report.json"

///|
let reconcile_stale_index_file : String = "index.json"

///|
let reconcile_records_file : String = "records.db"

///|
fn reconcile_path(index_dir : String, file_name : String) -> String {
  @reconcile_store.cache_path(index_dir, file_name)
}

///|
fn manifest_path(index_dir : String) -> String {
  reconcile_path(index_dir, reconcile_manifest_file)
}

///|
fn report_cache_path(index_dir : String) -> String {
  reconcile_path(index_dir, reconcile_report_file)
}

///|
fn stale_index_path(index_dir : String) -> String {
  reconcile_path(index_dir, reconcile_stale_index_file)
}

///|
fn load_manifest(index_dir : String) -> ReconcileManifest {
  let path = manifest_path(index_dir)
  let json = match @reconcile_store.read_json_file(path, "reconcile manifest") {
    Ok(value) => value
    Err(msg) => {
      println(msg)
      return ReconcileManifest::empty()
    }
  }
  @json.from_json(json) catch {
    _ => ReconcileManifest::empty()
  }
}

///|
fn save_manifest(index_dir : String, manifest : ReconcileManifest) -> Unit {
  let path = manifest_path(index_dir)
  match
    @reconcile_store.ensure_cache_dir(index_dir, "reconcile cache directory") {
    Err(msg) => {
      println(msg)
      return
    }
    Ok(_) => ()
  }
  match
    @reconcile_store.write_json_file(
      path,
      manifest.to_json(),
      "reconcile manifest",
    ) {
    Err(msg) => println(msg)
    Ok(_) => ()
  }
}

///|
fn load_cached_report(index_dir : String) -> ReconcileReport? {
  let path = report_cache_path(index_dir)
  let json = match @reconcile_store.read_json_file(path, "reconcile report") {
    Ok(value) => value
    Err(msg) => {
      println(msg)
      return None
    }
  }
  @json.from_json(json) catch {
    _ => None
  }
}

///|
fn save_cached_report(index_dir : String, report : ReconcileReport) -> Unit {
  let path = report_cache_path(index_dir)
  match
    @reconcile_store.ensure_cache_dir(index_dir, "reconcile cache directory") {
    Err(msg) => {
      println(msg)
      return
    }
    Ok(_) => ()
  }
  match
    @reconcile_store.write_json_file(path, report.to_json(), "reconcile report") {
    Err(msg) => println(msg)
    Ok(_) => ()
  }
}

///|
pub fn cleanup_stale_index(index_dir : String) -> Unit {
  let path = stale_index_path(index_dir)
  if !@fs.path_exists(path) {
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
  @reconcile_tracking.build_source_fingerprint(config_hash, file_states)
}
