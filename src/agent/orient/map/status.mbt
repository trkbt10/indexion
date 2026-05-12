///|
/// Compute file changes, affected owners, and status rows for orient map refresh.
pub fn owner_dir(path : String) -> String {
  let dir = @config_paths.dirname(path)
  if dir.length() == 0 || dir == "." {
    path
  } else {
    dir
  }
}

///|
pub fn cached_file_hashes(cached_map : AgentOrientMap?) -> Map[String, String] {
  let hashes : Map[String, String] = {}
  match cached_map {
    Some(map) =>
      for file in map.files {
        hashes.set(file.path, file.source_hash)
      }
    None => ()
  }
  hashes
}

///|
pub fn deleted_file_paths(
  old_hashes : Map[String, String],
  current_hashes : Map[String, String],
) -> Array[String] {
  let deleted : Array[String] = []
  for entry in old_hashes {
    if !current_hashes.contains(entry.0) {
      deleted.push(entry.0)
    }
  }
  deleted
}

///|
pub fn map_status_for_cached(map : AgentOrientMap) -> AgentOrientMapStatus {
  {
    total_files: map.files.length(),
    total_owners: map.owners.length(),
    total_doc_sources: owner_doc_source_count(map.owners),
    changed_files: [],
    new_files: [],
    deleted_files: [],
    knowledge_changed: false,
    refreshed_owners: [],
    reused_owners: owner_paths(map.owners),
  }
}

///|
pub fn refreshed_map_status(
  total_files : Int,
  owners : Array[AgentOrientMapOwner],
  changed : Array[String],
  new_files : Array[String],
  deleted : Array[String],
  knowledge_changed : Bool,
  affected_owners : Array[String],
  reused : Array[String],
) -> AgentOrientMapStatus {
  {
    total_files,
    total_owners: owners.length(),
    total_doc_sources: owner_doc_source_count(owners),
    changed_files: changed,
    new_files,
    deleted_files: deleted,
    knowledge_changed,
    refreshed_owners: affected_owners,
    reused_owners: reused,
  }
}

///|
pub fn owner_paths(owners : Array[AgentOrientMapOwner]) -> Array[String] {
  let result : Array[String] = []
  for owner in owners {
    result.push(owner.path)
  }
  result
}

///|
pub fn owner_doc_source_count(owners : Array[AgentOrientMapOwner]) -> Int {
  let mut count = 0
  for owner in owners {
    count += owner.doc_sources.length()
  }
  count
}

///|
pub fn affected_owner_dirs(
  changed : Array[String],
  new_files : Array[String],
  deleted : Array[String],
  owner_dirs : Array[String],
  knowledge_changed : Bool,
  cached_map : AgentOrientMap?,
) -> Array[String] {
  let dirs : Array[String] = []
  if knowledge_changed {
    for dir in owner_dirs {
      push_unique_dir(dirs, dir)
    }
  }
  for path in changed {
    push_unique_dir(dirs, owner_dir(path))
  }
  for path in new_files {
    push_unique_dir(dirs, owner_dir(path))
  }
  for path in deleted {
    match cached_map {
      Some(map) =>
        for file in map.files {
          if file.path == path {
            push_unique_dir(dirs, file.owner)
          }
        }
      None => push_unique_dir(dirs, owner_dir(path))
    }
  }
  dirs
}
