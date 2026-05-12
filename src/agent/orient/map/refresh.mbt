///|
/// Refresh the agent orient map from current file briefs and cached owner data.
pub fn build_or_update(
  config : AgentOrientConfig,
  briefs : Array[LocalFileBrief],
  cached_map : AgentOrientMap?,
) -> AgentOrientMap {
  if config.no_update {
    match cached_map {
      Some(map) => return { ..map, status: map_status_for_cached(map) }
      None => ()
    }
  }
  let old_hashes = cached_file_hashes(cached_map)
  let current_hashes : Map[String, String] = {}
  let files : Array[AgentOrientMapFile] = []
  let changed : Array[String] = []
  let new_files : Array[String] = []
  for brief in briefs {
    current_hashes.set(brief.path, brief.source_hash)
    files.push(file_from_brief(brief))
    match old_hashes.get(brief.path) {
      Some(hash) if hash == brief.source_hash => ()
      Some(_) => changed.push(brief.path)
      None => new_files.push(brief.path)
    }
  }
  let deleted = deleted_file_paths(old_hashes, current_hashes)
  let owner_dirs = owner_dirs_from_files(files)
  let wiki_docs = collect_wiki_docs(config.wiki_dir, owner_dirs)
  let knowledge_hash = knowledge_hash(wiki_docs)
  let knowledge_changed = match cached_map {
    Some(map) => map.knowledge_hash != knowledge_hash
    None => true
  }
  let affected_owners = affected_owner_dirs(
    changed, new_files, deleted, owner_dirs, knowledge_changed, cached_map,
  )
  let owners = build_owner_map_entries(
    files, wiki_docs, cached_map, affected_owners,
  )
  let reused = reused_owner_dirs(owners, affected_owners)
  {
    version: version(),
    knowledge_hash,
    files,
    owners,
    status: refreshed_map_status(
      files.length(),
      owners,
      changed,
      new_files,
      deleted,
      knowledge_changed,
      affected_owners,
      reused,
    ),
  }
}

///|
pub fn file_from_brief(brief : LocalFileBrief) -> AgentOrientMapFile {
  {
    path: brief.path,
    role: brief.role,
    source_hash: brief.source_hash,
    owner: owner_dir(brief.path),
    structural_summary: brief.structural_summary,
    summary: brief.summary,
  }
}
