///|
/// Build and reuse owner profile entries for the cached agent orient map.
pub fn build_owner_map_entries(
  files : Array[AgentOrientMapFile],
  wiki_docs : Array[LocalDocSource],
  cached_map : AgentOrientMap?,
  affected_owners : Array[String],
) -> Array[AgentOrientMapOwner] {
  let dirs = owner_dirs_from_files(files)
  let owners : Array[AgentOrientMapOwner] = []
  for dir in dirs {
    match cached_owner_for(dir, cached_map) {
      Some(owner) =>
        if !affected_owners.contains(dir) &&
          owner_files_still_match(owner, files) {
          owners.push(owner)
        } else {
          owners.push(build_owner_map_entry(dir, files, wiki_docs))
        }
      _ => owners.push(build_owner_map_entry(dir, files, wiki_docs))
    }
  }
  owners
}

///|
pub fn owner_dirs_from_files(
  files : Array[AgentOrientMapFile],
) -> Array[String] {
  let dirs : Array[String] = []
  for file in files {
    if map_file_is_consumer(file) {
      continue
    }
    push_unique_dir(dirs, file.owner)
  }
  dirs
}

///|
pub fn cached_owner_for(
  dir : String,
  cached_map : AgentOrientMap?,
) -> AgentOrientMapOwner? {
  match cached_map {
    None => None
    Some(map) => {
      for owner in map.owners {
        if owner.path == dir {
          return Some(owner)
        }
      }
      None
    }
  }
}

///|
pub fn owner_files_still_match(
  owner : AgentOrientMapOwner,
  files : Array[AgentOrientMapFile],
) -> Bool {
  let current : Array[String] = []
  for file in files {
    if file.owner == owner.path && !map_file_is_consumer(file) {
      current.push(file.path)
    }
  }
  current.sort()
  let expected = owner.files.copy()
  expected.sort()
  current == expected
}

///|
pub fn build_owner_map_entry(
  dir : String,
  files : Array[AgentOrientMapFile],
  wiki_docs : Array[LocalDocSource],
) -> AgentOrientMapOwner {
  let owner_files : Array[String] = []
  let doc_sources : Array[String] = []
  let summary = StringBuilder::new()
  summary.write_string(dir)
  summary.write_string("\n")
  let hashes : Array[String] = []
  summary.write_string("Documentation knowledge\n")
  for file in files {
    if file.owner != dir || map_file_is_consumer(file) {
      continue
    }
    owner_files.push(file.path)
    hashes.push(file.source_hash)
    if is_documentation_path(file.path) {
      doc_sources.push(file.path)
      summary.write_string(file.summary)
      summary.write_string("\n")
    }
  }
  for doc in wiki_docs {
    if doc.owner == dir {
      doc_sources.push(doc.path)
      hashes.push(doc.source_hash)
      summary.write_string(doc.content)
      summary.write_string("\n")
    }
  }
  summary.write_string("Code structure\n")
  for file in files {
    if file.owner != dir ||
      map_file_is_consumer(file) ||
      is_documentation_path(file.path) {
      continue
    }
    summary.write_string(file.structural_summary)
    summary.write_string("\n")
  }
  owner_files.sort()
  hashes.sort()
  doc_sources.sort()
  {
    path: dir,
    source_hash: @cas_hash.compute_hash(hashes.join("\n")).to_string(),
    files: owner_files,
    doc_sources,
    summary: summary.to_string(),
  }
}

///|
pub fn reused_owner_dirs(
  owners : Array[AgentOrientMapOwner],
  affected_owners : Array[String],
) -> Array[String] {
  let reused : Array[String] = []
  for owner in owners {
    if !affected_owners.contains(owner.path) {
      reused.push(owner.path)
    }
  }
  reused
}

///|
pub fn push_unique_dir(dirs : Array[String], dir : String) -> Unit {
  if dir.length() > 0 && !dirs.contains(dir) {
    dirs.push(dir)
  }
}
