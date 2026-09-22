///|
let timestamp_cache : Map[String, TimestampInfo] = Map([])

///|
let repo_check_cache : Map[String, Bool] = Map([])

///|
async fn is_repo_cached(root : String) -> Bool {
  match repo_check_cache.get(root) {
    Some(v) => v
    None => {
      let v = @git.is_repo(root)
      repo_check_cache.set(root, v)
      v
    }
  }
}

///|
pub async fn timestamp_for_path(
  root : String,
  path : String,
  config : FileTrackingConfig,
) -> TimestampInfo {
  let cache_key = root +
    "\u0000" +
    path +
    "\u0000" +
    config.git_preferred.to_string() +
    "\u0000" +
    config.mtime_fallback.to_string()
  match timestamp_cache.get(cache_key) {
    Some(cached) => cached
    None => {
      let result = timestamp_for_path_uncached(root, path, config)
      timestamp_cache.set(cache_key, result)
      result
    }
  }
}

///|
async fn timestamp_for_path_uncached(
  root : String,
  path : String,
  config : FileTrackingConfig,
) -> TimestampInfo {
  let repo_ok = config.git_preferred && is_repo_cached(root)
  if repo_ok {
    let git_time = @git.last_commit_seconds(root, path)
    let dirty = @git.status_dirty(root, path)
    if dirty {
      if config.mtime_fallback {
        match @git.file_mtime_seconds(path) {
          Some(seconds) =>
            return {
              epoch_seconds: Some(seconds),
              source: "mtime",
              is_dirty: true,
            }
          None => ()
        }
      }
    } else {
      match git_time {
        Some(seconds) =>
          return {
            epoch_seconds: Some(seconds),
            source: "git",
            is_dirty: false,
          }
        None => ()
      }
    }
  }
  if config.mtime_fallback {
    match @git.file_mtime_seconds(path) {
      Some(seconds) =>
        return {
          epoch_seconds: Some(seconds),
          source: "mtime",
          is_dirty: false,
        }
      None => ()
    }
  }
  TimestampInfo::unknown()
}

///|
pub fn build_source_fingerprint(
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
  @cas_hash.compute_hash([config_hash, entries.join("\u0000")].join("\u0000")).to_string()
}
